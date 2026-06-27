import Foundation
import SwiftData
import Testing
@testable import Remnant

@MainActor
@Suite("Expense Ledger")
struct ExpenseLedgerTests {
    @Test("Monthly total excludes ignored expenses")
    func monthlyTotalExcludesIgnoredExpenses() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let active = Expense(date: date, merchant: "Apple", amount: 100)
        let ignored = Expense(date: date, merchant: "Ignored", amount: 50, status: .ignored)

        let total = ExpenseLedger.totalSpent(
            in: [active, ignored],
            for: ExpenseLedger.monthInterval(containing: date)
        )

        #expect(total == 100)
    }

    @Test("Duplicate detection matches merchant, date, and amount")
    func duplicateDetectionMatchesMerchantDateAmount() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let existing = Expense(date: date, merchant: "OpenAI", amount: 20)
        let candidate = Expense(date: date, merchant: " openai ", amount: 20)

        let duplicate = ExpenseLedger.possibleDuplicate(of: candidate, in: [existing, candidate])

        #expect(duplicate?.id == existing.id)
    }

    @Test("Duplicate detection matches receipt hash")
    func duplicateDetectionMatchesReceiptHash() {
        let existing = Expense(merchant: "Vendor A", amount: 30, receiptContentHash: "abc123")
        let candidate = Expense(merchant: "Vendor B", amount: 90, receiptContentHash: "ABC123")

        let duplicate = ExpenseLedger.possibleDuplicate(of: candidate, in: [existing, candidate])

        #expect(duplicate?.id == existing.id)
    }

    @Test("CSV export guards formula-like cells")
    func csvExportGuardsFormulaLikeCells() {
        let expense = Expense(merchant: "=SUM(1,1)", amount: 12)

        let csv = ExpenseLedger.exportCSV(expenses: [expense])

        #expect(csv.contains("\"'=SUM(1,1)\""))
    }

    @Test("Missing receipt filtering excludes ignored expenses")
    func missingReceiptFilteringExcludesIgnoredExpenses() {
        let missing = Expense(merchant: "No Receipt", amount: 10)
        let attached = Expense(merchant: "Receipt", amount: 20, receiptContentHash: "abc123")
        let ignored = Expense(merchant: "Ignored", amount: 30, status: .ignored)

        let result = ExpenseLedger.expensesMissingReceipts(in: [missing, attached, ignored])

        #expect(result.map(\.id) == [missing.id])
    }

    @Test("Bulk status update changes only different statuses")
    func bulkStatusUpdateChangesOnlyDifferentStatuses() throws {
        let timestamp = try makeUTCDate(year: 2026, month: 6, day: 1)
        let draft = Expense(merchant: "Draft", amount: 10, status: .draft)
        let reviewed = Expense(merchant: "Reviewed", amount: 20, status: .reviewed)

        let changedCount = ExpenseLedger.updateStatus(
            of: [draft, reviewed],
            to: .reviewed,
            updatedAt: timestamp
        )

        #expect(changedCount == 1)
        #expect(draft.status == .reviewed)
        #expect(draft.updatedAt == timestamp)
        #expect(reviewed.status == .reviewed)
        #expect(reviewed.updatedAt != timestamp)
    }

    @Test("Default category seeding inserts defaults once")
    func defaultCategorySeedingInsertsDefaultsOnce() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Expense.self, ReceiptAttachment.self, ExpenseCategory.self, ImportBatch.self, VendorRule.self,
            configurations: config
        )

        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: container.mainContext)
        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: container.mainContext)

        let categories = try container.mainContext.fetch(FetchDescriptor<ExpenseCategory>())
        #expect(categories.count == ExpenseCategory.defaultCategoryDefinitions.count)
    }

    @Test("Expense store can use explicit 1.0 store URL")
    func expenseStoreCanUseExplicitV1StoreURL() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("RemnantExpenseTrackerV1.store")
        let container = try RemnantStore.makeContainer(storeURL: storeURL)
        let expense = Expense(merchant: "OpenAI", amount: 20)

        container.mainContext.insert(expense)
        try container.mainContext.save()

        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("Expense store migrates readable legacy default store")
    func expenseStoreMigratesReadableLegacyDefaultStore() throws {
        let directory = try makeTemporaryDirectory()
        let legacyStoreURL = directory.appendingPathComponent(RemnantStore.legacyDefaultStoreFilename)
        let targetStoreURL = directory.appendingPathComponent(RemnantStore.storeFilename)
        let legacyExpenseID: UUID

        do {
            let legacyContainer = try RemnantStore.makeContainer(storeURL: legacyStoreURL)
            let expense = Expense(merchant: "Legacy OpenAI", amount: 20)
            legacyExpenseID = expense.id
            legacyContainer.mainContext.insert(expense)
            try legacyContainer.mainContext.save()
        }

        let didMigrate = try RemnantStore.migrateLegacyStoreIfNeeded(
            from: legacyStoreURL,
            to: targetStoreURL
        )
        let migratedContainer = try RemnantStore.makeContainer(storeURL: targetStoreURL)
        let migratedExpenses = try migratedContainer.mainContext.fetch(FetchDescriptor<Expense>())

        #expect(didMigrate)
        #expect(migratedExpenses.map(\.id).contains(legacyExpenseID))
    }

    @Test("Expense source decodes legacy Gmail review value")
    func expenseSourceDecodesLegacyGmailReviewValue() throws {
        let legacyData = try #require("\"gmailReview\"".data(using: .utf8))
        let source = try JSONDecoder().decode(ExpenseSource.self, from: legacyData)
        let encodedData = try JSONEncoder().encode(ExpenseSource.receiptDraft)
        let encodedValue = String(data: encodedData, encoding: .utf8)

        #expect(source == .receiptDraft)
        #expect(encodedValue == "\"receiptDraft\"")
    }

    @Test("CSV import parses accepted expenses and skips credit rows")
    func csvImportParsesAcceptedExpensesAndSkipsCreditRows() throws {
        let csv = """
        Date,Description,Debit,Credit,Category,Account,Payment Method,Receipt,Memo
        2026-06-01,"OpenAI, LLC",20,,Software,Amex,Card,openai.pdf,API usage
        2026-06-02,Refund,,5,Software,Amex,Card,refund.pdf,Refund
        """
        let url = try writeTemporaryCSV(csv)

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: .waveImport
        )

        #expect(summary.rowCount == 2)
        #expect(summary.accepted.count == 1)
        #expect(summary.duplicates.isEmpty)
        #expect(summary.ignoredRows == [3])
        #expect(summary.accepted.first?.expense.merchant == "OpenAI, LLC")
        #expect(summary.accepted.first?.expense.amount == 20)
        #expect(summary.accepted.first?.expense.categoryName == "Software")
        #expect(summary.accepted.first?.expense.receiptFilename == "openai.pdf")
        #expect(summary.accepted.first?.expense.status == .draft)
    }

    @Test("CSV import handles Wave-style aliases, currency, and transaction types")
    func csvImportHandlesWaveStyleAliasesCurrencyAndTransactionTypes() throws {
        let csv = """
        \u{FEFF}Transaction Date,Vendor Name,Paid Amount,Currency Code,Expense Category,Paid Through,Method,Receipt Attachment,Details,Type
        06/01/2026,Apple Developer,"-$99.00",usd,Software,Amex,Card,apple.pdf,Developer Program,Expense
        06/02/2026,Stripe,"$12.00",USD,Software,Checking,ACH,,Payout,Payment received
        """
        let url = try writeTemporaryCSV(csv)

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: .waveImport
        )

        #expect(summary.rowCount == 2)
        #expect(summary.accepted.count == 1)
        #expect(summary.ignoredRows == [3])
        #expect(summary.accepted.first?.expense.merchant == "Apple Developer")
        #expect(summary.accepted.first?.expense.amount == 99)
        #expect(summary.accepted.first?.expense.currencyCode == "USD")
        #expect(summary.accepted.first?.expense.categoryName == "Software")
        #expect(summary.accepted.first?.expense.paymentAccount == "Amex")
        #expect(summary.accepted.first?.expense.paymentMethod == "Card")
        #expect(summary.accepted.first?.expense.receiptFilename == "apple.pdf")
        #expect(summary.accepted.first?.expense.note == "Developer Program")
    }

    @Test("CSV import parses money-out columns and skips money-in credits")
    func csvImportParsesMoneyOutColumnsAndSkipsMoneyInCredits() throws {
        let csv = """
        Date,Description,Money Out,Money In,Direction,Currency
        2026-06-03,OpenAI,"($20.00)",,Debit,USD
        2026-06-04,Refund,,"$20.00",Credit,USD
        """
        let url = try writeTemporaryCSV(csv)

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: .csvImport
        )

        #expect(summary.accepted.count == 1)
        #expect(summary.ignoredRows == [3])
        #expect(summary.accepted.first?.expense.merchant == "OpenAI")
        #expect(summary.accepted.first?.expense.amount == 20)
    }

    @Test("CSV import keeps duplicate rows out of accepted results")
    func csvImportDetectsDuplicates() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let existing = Expense(date: date, merchant: "OpenAI, LLC", amount: 20)
        let csv = """
        Date,Description,Amount
        2026-06-01,"openai, llc",-20
        """
        let url = try writeTemporaryCSV(csv)

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [existing],
            source: .waveImport
        )

        #expect(summary.accepted.isEmpty)
        #expect(summary.duplicates.count == 1)
        #expect(summary.duplicates.first?.duplicateOf?.id == existing.id)
    }

    @Test("Vendor rule matcher chooses the most specific match")
    func vendorRuleMatcherChoosesMostSpecificMatch() {
        let generic = VendorRule(
            merchantPattern: "open",
            defaultCategoryName: "Office",
            defaultTaxBucket: "Office"
        )
        let specific = VendorRule(
            merchantPattern: "OpenAI",
            defaultCategoryName: "Software",
            defaultTaxBucket: "Software and subscriptions"
        )

        let category = VendorRuleMatcher.categoryName(
            for: "OPENAI, LLC",
            rules: [generic, specific]
        )

        #expect(category == "Software")
    }

    @Test("CSV import applies vendor rules when category is blank")
    func csvImportAppliesVendorRulesWhenCategoryIsBlank() throws {
        let csv = """
        Date,Description,Amount,Category
        2026-06-01,"OPENAI, LLC",-20,
        """
        let url = try writeTemporaryCSV(csv)
        let rule = VendorRule(
            merchantPattern: "openai",
            defaultCategoryName: "Software",
            defaultTaxBucket: "Software and subscriptions"
        )

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: .waveImport,
            vendorRules: [rule]
        )

        #expect(summary.accepted.first?.expense.categoryName == "Software")
    }

    @Test("CSV import keeps explicit CSV category over vendor rule")
    func csvImportKeepsExplicitCSVCategoryOverVendorRule() throws {
        let csv = """
        Date,Description,Amount,Category
        2026-06-01,"OPENAI, LLC",-20,Contractors
        """
        let url = try writeTemporaryCSV(csv)
        let rule = VendorRule(
            merchantPattern: "openai",
            defaultCategoryName: "Software",
            defaultTaxBucket: "Software and subscriptions"
        )

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: .waveImport,
            vendorRules: [rule]
        )

        #expect(summary.accepted.first?.expense.categoryName == "Contractors")
    }

    @Test("Wave migration import marks accepted expenses reviewed")
    func waveMigrationImportMarksAcceptedExpensesReviewed() throws {
        let csv = """
        Date,Description,Amount,Category
        2026-06-01,"OpenAI, LLC",-20,Software
        """
        let url = try writeTemporaryCSV(csv)

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: ExpenseImportMode.waveMigration.source,
            defaultStatus: ExpenseImportMode.waveMigration.defaultStatus
        )

        #expect(summary.accepted.first?.expense.source == .waveImport)
        #expect(summary.accepted.first?.expense.status == .reviewed)
    }

    @Test("Import batch records import mode")
    func importBatchRecordsImportMode() {
        let batch = ImportBatch(
            sourceName: "wave-export.csv",
            importMode: .waveMigration,
            rowCount: 10,
            acceptedCount: 8
        )

        #expect(batch.importMode == .waveMigration)
        #expect(batch.importMode.source == .waveImport)
        #expect(batch.importMode.defaultStatus == .reviewed)
    }

    @Test("Receipt metadata parser extracts merchant date and amount")
    func receiptMetadataParserExtractsMerchantDateAndAmount() throws {
        let text = """
        OpenAI, LLC
        Receipt
        Date: 2026-06-01
        Subtotal $18.00
        Total $20.00
        """

        let metadata = ReceiptMetadataExtractor.parse(text: text, fallbackFilename: "openai.pdf")
        let expectedDate = try makeUTCDate(year: 2026, month: 6, day: 1)

        #expect(metadata.merchant == "OpenAI, LLC")
        #expect(metadata.date == expectedDate)
        #expect(metadata.amount == 20)
        #expect(metadata.confidence > 0.8)
    }

    @Test("Receipt metadata parser falls back to filename merchant")
    func receiptMetadataParserFallsBackToFilenameMerchant() throws {
        let text = """
        Receipt
        Date: 06/02/2026
        Total $99.00
        """

        let metadata = ReceiptMetadataExtractor.parse(
            text: text,
            fallbackFilename: "apple-developer-2026-06-02.pdf"
        )
        let expectedDate = try makeUTCDate(year: 2026, month: 6, day: 2)

        #expect(metadata.merchant == "Apple Developer")
        #expect(metadata.date == expectedDate)
        #expect(metadata.amount == 99)
    }

    @Test("Receipt vault copies files into a local hashed path")
    func receiptVaultCopiesFilesIntoLocalHashedPath() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let sourceURL = try writeTemporaryFile(named: "receipt.txt", contents: "OpenAI receipt")
        let vaultURL = try makeTemporaryDirectory()
        let expense = Expense(merchant: "OpenAI", amount: 20)
        context.insert(expense)

        let result = try ReceiptVault.importReceipt(
            at: sourceURL,
            context: context,
            expense: expense,
            vaultDirectory: vaultURL
        )
        try context.save()

        #expect(result.isDuplicate == false)
        #expect(result.attachment.originalFilename == "receipt.txt")
        #expect(result.attachment.contentHash.count == 64)
        #expect(result.attachment.localPath.hasPrefix(vaultURL.path))
        #expect(FileManager.default.fileExists(atPath: result.attachment.localPath))
        #expect(expense.receiptAttachmentID == result.attachment.id)
        #expect(expense.receiptContentHash == result.attachment.contentHash)
        #expect(expense.receiptFilename == "receipt.txt")
    }

    @Test("Receipt vault stores extracted metadata")
    func receiptVaultStoresExtractedMetadata() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let sourceURL = try writeTemporaryFile(
            named: "openai-receipt.txt",
            contents: """
            OpenAI, LLC
            Receipt
            Date: 2026-06-01
            Total $20.00
            """
        )
        let vaultURL = try makeTemporaryDirectory()

        let result = try ReceiptVault.importReceipt(
            at: sourceURL,
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()
        let expectedDate = try makeUTCDate(year: 2026, month: 6, day: 1)

        #expect(result.attachment.extractedMerchant == "OpenAI, LLC")
        #expect(result.attachment.extractedDate == expectedDate)
        #expect(result.attachment.extractedAmount == 20)
        #expect(result.attachment.extractionConfidence > 0.8)
    }

    @Test("Receipt vault dedupes matching content hashes")
    func receiptVaultDedupesMatchingContentHashes() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let sourceURL = try writeTemporaryFile(named: "duplicate.txt", contents: "same receipt")
        let vaultURL = try makeTemporaryDirectory()

        let first = try ReceiptVault.importReceipt(at: sourceURL, context: context, vaultDirectory: vaultURL)
        let second = try ReceiptVault.importReceipt(at: sourceURL, context: context, vaultDirectory: vaultURL)
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        #expect(first.isDuplicate == false)
        #expect(second.isDuplicate == true)
        #expect(second.attachment.id == first.attachment.id)
        #expect(attachments.count == 1)
    }

    @Test("Receipt vault does not relink duplicate attached receipt")
    func receiptVaultDoesNotRelinkDuplicateAttachedReceipt() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let sourceURL = try writeTemporaryFile(named: "duplicate-linked.txt", contents: "same linked receipt")
        let vaultURL = try makeTemporaryDirectory()
        let originalExpense = Expense(merchant: "Original", amount: 20)
        let newExpense = Expense(merchant: "New", amount: 20)
        context.insert(originalExpense)
        context.insert(newExpense)

        let first = try ReceiptVault.importReceipt(
            at: sourceURL,
            context: context,
            expense: originalExpense,
            vaultDirectory: vaultURL
        )
        let second = try ReceiptVault.importReceipt(
            at: sourceURL,
            context: context,
            expense: newExpense,
            vaultDirectory: vaultURL
        )
        try context.save()

        #expect(first.status == .imported)
        #expect(second.status == .duplicateLinked(expenseID: originalExpense.id))
        #expect(second.attachment.expenseID == originalExpense.id)
        #expect(originalExpense.receiptAttachmentID == first.attachment.id)
        #expect(newExpense.receiptAttachmentID == nil)
        #expect(newExpense.receiptContentHash == nil)
    }

    @Test("Receipt vault linking clears missing receipt state")
    func receiptVaultLinkingClearsMissingReceiptState() {
        let expense = Expense(merchant: "Apple", amount: 15)
        let attachment = ReceiptAttachment(
            originalFilename: "apple.pdf",
            localPath: "/tmp/apple.pdf",
            contentHash: "abc123"
        )

        ReceiptVault.link(attachment: attachment, to: expense)

        #expect(attachment.expenseID == expense.id)
        #expect(expense.receiptAttachmentID == attachment.id)
        #expect(expense.receiptFilename == "apple.pdf")
        #expect(expense.receiptContentHash == "abc123")
        #expect(ExpenseLedger.expensesMissingReceipts(in: [expense]).isEmpty)
    }

    @Test("Receipt vault unlinks attachments before expense deletion")
    func receiptVaultUnlinksAttachmentsBeforeExpenseDeletion() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let expense = Expense(merchant: "Apple", amount: 15)
        let attachment = ReceiptAttachment(
            originalFilename: "apple.pdf",
            localPath: "/tmp/apple.pdf",
            contentHash: "abc123"
        )
        context.insert(expense)
        context.insert(attachment)
        ReceiptVault.link(attachment: attachment, to: expense)

        let changedCount = try ReceiptVault.unlinkAttachments(from: expense, context: context)

        #expect(changedCount == 1)
        #expect(attachment.expenseID == nil)
        #expect(expense.receiptAttachmentID == nil)
        #expect(expense.receiptFilename == nil)
        #expect(expense.receiptContentHash == nil)
        #expect(!ExpenseLedger.expensesMissingReceipts(in: [expense]).isEmpty)
    }

    @Test("Receipt vault does not unlink attachment owned by another expense")
    func receiptVaultDoesNotUnlinkAttachmentOwnedByAnotherExpense() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let owner = Expense(merchant: "Owner", amount: 15)
        let deletingExpense = Expense(
            merchant: "Deleting",
            amount: 15,
            receiptContentHash: "abc123"
        )
        let attachment = ReceiptAttachment(
            expenseID: owner.id,
            originalFilename: "apple.pdf",
            localPath: "/tmp/apple.pdf",
            contentHash: "abc123"
        )
        context.insert(owner)
        context.insert(deletingExpense)
        context.insert(attachment)

        let changedCount = try ReceiptVault.unlinkAttachments(from: deletingExpense, context: context)

        #expect(changedCount == 0)
        #expect(attachment.expenseID == owner.id)
        #expect(deletingExpense.receiptContentHash == nil)
    }

    @Test("Receipt vault creates draft expenses from usable receipt metadata")
    func receiptVaultCreatesDraftExpensesFromUsableReceiptMetadata() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let receiptDate = try makeUTCDate(year: 2026, month: 6, day: 1)
        let eligible = ReceiptAttachment(
            originalFilename: "openai-receipt.txt",
            localPath: "/tmp/openai.txt",
            contentHash: "abc123",
            extractedMerchant: "OpenAI, LLC",
            extractedDate: receiptDate,
            extractedAmount: 20
        )
        let amountless = ReceiptAttachment(
            originalFilename: "unknown.txt",
            localPath: "/tmp/unknown.txt",
            contentHash: "def456"
        )
        let alreadyLinked = ReceiptAttachment(
            expenseID: UUID(),
            originalFilename: "linked.txt",
            localPath: "/tmp/linked.txt",
            contentHash: "ghi789",
            extractedMerchant: "Linked",
            extractedAmount: 10
        )
        let rule = VendorRule(
            merchantPattern: "openai",
            defaultCategoryName: "Software",
            defaultTaxBucket: "Software and subscriptions"
        )
        context.insert(eligible)
        context.insert(amountless)
        context.insert(alreadyLinked)

        let createdCount = ReceiptVault.createDraftExpenses(
            from: [eligible, amountless, alreadyLinked],
            context: context,
            vendorRules: [rule]
        )
        try context.save()

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let expense = try #require(expenses.first)
        #expect(createdCount == 1)
        #expect(expenses.count == 1)
        #expect(expense.date == receiptDate)
        #expect(expense.merchant == "OpenAI, LLC")
        #expect(expense.amount == 20)
        #expect(expense.categoryName == "Software")
        #expect(expense.status == .draft)
        #expect(expense.source == .receiptDraft)
        #expect(expense.receiptAttachmentID == eligible.id)
        #expect(eligible.expenseID == expense.id)
        #expect(amountless.expenseID == nil)
        #expect(alreadyLinked.expenseID != nil)
    }

    @Test("Receipt matcher suggests same amount same day merchant match")
    func receiptMatcherSuggestsSameAmountSameDayMerchantMatch() throws {
        let date = try makeUTCDate(year: 2026, month: 6, day: 1)
        let expense = Expense(date: date, merchant: "OpenAI, LLC", amount: 20)
        let receipt = ReceiptAttachment(
            originalFilename: "openai.pdf",
            localPath: "/tmp/openai.pdf",
            contentHash: "abc123",
            extractedMerchant: "OpenAI",
            extractedDate: date,
            extractedAmount: 20,
            extractionConfidence: 0.9
        )

        let suggestion = ReceiptMatcher.bestSuggestion(for: receipt, expenses: [expense])

        #expect(suggestion?.expense.id == expense.id)
        #expect(suggestion?.score == 100)
        #expect(suggestion?.reasons == ["amount", "same day", "merchant"])
    }

    @Test("Receipt matcher rejects mismatched amounts")
    func receiptMatcherRejectsMismatchedAmounts() throws {
        let date = try makeUTCDate(year: 2026, month: 6, day: 1)
        let expense = Expense(date: date, merchant: "OpenAI", amount: 21)
        let receipt = ReceiptAttachment(
            originalFilename: "openai.pdf",
            localPath: "/tmp/openai.pdf",
            contentHash: "abc123",
            extractedMerchant: "OpenAI",
            extractedDate: date,
            extractedAmount: 20
        )

        let suggestion = ReceiptMatcher.bestSuggestion(for: receipt, expenses: [expense])

        #expect(suggestion == nil)
    }

    @Test("Receipt matcher ranks stronger date match first")
    func receiptMatcherRanksStrongerDateMatchFirst() throws {
        let receiptDate = try makeUTCDate(year: 2026, month: 6, day: 1)
        let sameDay = Expense(date: receiptDate, merchant: "OpenAI", amount: 20)
        let nearDay = Expense(
            date: try makeUTCDate(year: 2026, month: 6, day: 3),
            merchant: "OpenAI",
            amount: 20
        )
        let receipt = ReceiptAttachment(
            originalFilename: "openai.pdf",
            localPath: "/tmp/openai.pdf",
            contentHash: "abc123",
            extractedMerchant: "OpenAI",
            extractedDate: receiptDate,
            extractedAmount: 20
        )

        let suggestion = ReceiptMatcher.bestSuggestion(for: receipt, expenses: [nearDay, sameDay])

        #expect(suggestion?.expense.id == sameDay.id)
    }

    private func writeTemporaryCSV(_ csv: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remnant-\(UUID().uuidString)")
            .appendingPathExtension("csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeTemporaryFile(named filename: String, contents: String) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent(filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeUTCDate(year: Int, month: Int, day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remnant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExpenseContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Expense.self, ReceiptAttachment.self, ExpenseCategory.self, ImportBatch.self, VendorRule.self,
            configurations: config
        )
    }
}
