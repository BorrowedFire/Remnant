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

    @Test("CSV export includes tax bucket from local categories")
    func csvExportIncludesTaxBucketFromLocalCategories() {
        let expense = Expense(merchant: "OpenAI", amount: 20, categoryName: "AI Tools")
        let category = ExpenseCategory(
            name: "AI Tools",
            taxBucket: "Office expense",
            icon: "sparkles",
            colorHex: "8B5CF6"
        )

        let csv = ExpenseLedger.exportCSV(expenses: [expense], categories: [category])

        #expect(csv.starts(with: "\"Date\",\"Merchant\",\"Amount\",\"Currency\",\"Category\",\"Tax Bucket\""))
        #expect(csv.contains("\"AI Tools\",\"Office expense\""))
    }

    @Test("CSV export includes reporting dimension fields")
    func csvExportIncludesReportingDimensionFields() {
        let expense = Expense(
            merchant: "OpenAI",
            amount: 20,
            paymentAccount: "Amex",
            vendorName: "OpenAI",
            clientName: "Acme",
            projectName: "Launch"
        )

        let csv = ExpenseLedger.exportCSV(expenses: [expense])

        #expect(csv.starts(with: "\"Date\",\"Merchant\",\"Amount\",\"Currency\",\"Category\",\"Tax Bucket\",\"Account\",\"Vendor\",\"Client\",\"Project\""))
        #expect(csv.contains("\"Amex\",\"OpenAI\",\"Acme\",\"Launch\""))
    }

    @Test("Reporting dimension values fall back for existing expenses")
    func reportingDimensionValuesFallBackForExistingExpenses() {
        let expense = Expense(merchant: "Stripe", amount: 10, paymentAccount: "Checking", vendorName: "")

        #expect(ExpenseLedger.dimensionValue(for: expense, kind: .account) == "Checking")
        #expect(ExpenseLedger.dimensionValue(for: expense, kind: .vendor) == "Stripe")
        #expect(ExpenseLedger.dimensionValue(for: expense, kind: .client) == "")
        #expect(ExpenseLedger.dimensionValue(for: expense, kind: .project) == "")
    }

    @Test("CSV export includes billable and reimbursable flags")
    func csvExportIncludesBillableAndReimbursableFlags() {
        let expense = Expense(
            merchant: "OpenAI",
            amount: 20,
            clientName: "Acme",
            projectName: "Launch",
            isBillable: true,
            isReimbursable: true
        )

        let csv = ExpenseLedger.exportCSV(expenses: [expense])

        #expect(csv.starts(with: "\"Date\",\"Merchant\",\"Amount\",\"Currency\",\"Category\",\"Tax Bucket\",\"Account\",\"Vendor\",\"Client\",\"Project\",\"Billable\",\"Reimbursable\""))
        #expect(csv.contains("\"Acme\",\"Launch\",\"Yes\",\"Yes\""))
    }

    @Test("Tax bucket summary CSV groups and sorts buckets")
    func taxBucketSummaryCSVGroupsAndSortsBuckets() {
        let software = Expense(merchant: "OpenAI", amount: 20, categoryName: "AI Tools")
        let hosting = Expense(merchant: "Fly", amount: 15, categoryName: "Hosting")
        let uncategorized = Expense(merchant: "Unknown", amount: 5, categoryName: "Uncategorized")
        let categories = [
            ExpenseCategory(name: "AI Tools", taxBucket: "Office expense", icon: "sparkles", colorHex: "8B5CF6"),
            ExpenseCategory(name: "Hosting", taxBucket: "Utilities", icon: "server.rack", colorHex: "06B6D4")
        ]

        let csv = ExpenseLedger.exportTaxBucketSummaryCSV(
            expenses: [software, hosting, uncategorized],
            categories: categories
        )

        #expect(csv.split(separator: "\n").map(String.init) == [
            "\"Tax Bucket\",\"Expense Count\",\"Amount\"",
            "\"Needs review\",\"1\",\"5\"",
            "\"Office expense\",\"1\",\"20\"",
            "\"Utilities\",\"1\",\"15\""
        ])
    }

    @Test("Tax bucket summary CSV is formula safe")
    func taxBucketSummaryCSVIsFormulaSafe() {
        let expense = Expense(merchant: "Vendor", amount: 20, categoryName: "Risky")
        let category = ExpenseCategory(name: "Risky", taxBucket: "=SUM(1,1)", icon: "folder", colorHex: "6B7280")

        let csv = ExpenseLedger.exportTaxBucketSummaryCSV(expenses: [expense], categories: [category])

        #expect(csv.contains("\"'=SUM(1,1)\",\"1\",\"20\""))
    }

    @Test("Expenses can be filtered by reporting dimension")
    func expensesCanBeFilteredByReportingDimension() {
        let launch = Expense(merchant: "OpenAI", amount: 20, projectName: "Launch")
        let support = Expense(merchant: "Apple", amount: 99, projectName: "Support")

        let filtered = ExpenseLedger.expenses([launch, support], matching: .project, value: "launch")

        #expect(filtered.map(\.id) == [launch.id])
    }

    @Test("Outstanding follow-up filters use flags and legacy status")
    func outstandingFollowUpFiltersUseFlagsAndLegacyStatus() {
        let billable = Expense(merchant: "Design", amount: 100, isBillable: true)
        let reimbursable = Expense(merchant: "Travel", amount: 40, isReimbursable: true)
        let legacyReimbursable = Expense(merchant: "Legacy", amount: 25, status: .reimbursable)
        let ignoredBillable = Expense(merchant: "Ignored", amount: 10, isBillable: true, status: .ignored)
        let regular = Expense(merchant: "Regular", amount: 12)

        let expenses = [billable, reimbursable, legacyReimbursable, ignoredBillable, regular]

        #expect(ExpenseLedger.outstandingBillableExpenses(in: expenses).map(\.id) == [billable.id])
        #expect(ExpenseLedger.outstandingReimbursableExpenses(in: expenses).map(\.id) == [reimbursable.id, legacyReimbursable.id])
        #expect(ExpenseLedger.outstandingFollowUpExpenses(in: expenses).map(\.id) == [billable.id, reimbursable.id, legacyReimbursable.id])
    }

    @Test("Review issues classify imported cleanup rows")
    func reviewIssuesClassifyImportedCleanupRows() {
        let imported = Expense(
            merchant: "OpenAI",
            amount: 20,
            categoryName: "Uncategorized",
            status: .draft,
            source: .csvImport
        )

        let issues = ExpenseLedger.reviewIssues(for: imported, allExpenses: [imported])

        #expect(issues == Set([
            .importedDraft,
            .manualReview,
            .missingReceipt,
            .uncategorized
        ]))
    }

    @Test("Review issues classify duplicate candidates")
    func reviewIssuesClassifyDuplicateCandidates() throws {
        let date = try makeUTCDate(year: 2026, month: 6, day: 1)
        let first = Expense(
            date: date,
            merchant: "OpenAI",
            amount: 20,
            categoryName: "Software",
            status: .reviewed,
            receiptFilename: "openai-a.pdf"
        )
        let second = Expense(
            date: date,
            merchant: " openai ",
            amount: 20,
            categoryName: "Software",
            status: .reviewed,
            receiptFilename: "openai-b.pdf"
        )

        let issues = ExpenseLedger.reviewIssues(for: first, allExpenses: [first, second])

        #expect(issues == Set([.duplicateCandidate]))
    }

    @Test("Review inbox excludes ignored and clean reviewed expenses")
    func reviewInboxExcludesIgnoredAndCleanReviewedExpenses() {
        let clean = Expense(
            merchant: "Apple",
            amount: 99,
            categoryName: "Software",
            status: .reviewed,
            receiptFilename: "apple.pdf"
        )
        let ignored = Expense(
            merchant: "Ignored",
            amount: 10,
            categoryName: "Uncategorized",
            status: .ignored
        )
        let importedDraft = Expense(
            merchant: "OpenAI",
            amount: 20,
            categoryName: "Software",
            status: .draft,
            source: .csvImport,
            receiptFilename: "openai.pdf"
        )

        let inbox = ExpenseLedger.reviewInboxExpenses(in: [clean, ignored, importedDraft])

        #expect(inbox.map(\.id) == [importedDraft.id])
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
            for: Expense.self, ReceiptAttachment.self, ExpenseCategory.self, BusinessDimension.self, CSVImportProfile.self, ImportBatch.self, VendorRule.self,
            configurations: config
        )

        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: container.mainContext)
        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: container.mainContext)

        let categories = try container.mainContext.fetch(FetchDescriptor<ExpenseCategory>())
        #expect(categories.count == ExpenseCategory.defaultCategoryDefinitions.count)
    }

    @Test("Default categories cover developer business expenses")
    func defaultCategoriesCoverDeveloperBusinessExpenses() {
        let names = Set(ExpenseCategory.defaultCategoryDefinitions.map { $0.name })
        let buckets = Dictionary(
            uniqueKeysWithValues: ExpenseCategory.defaultCategoryDefinitions.map { ($0.name, $0.taxBucket) }
        )

        #expect(names.isSuperset(of: [
            "Software",
            "AI Tools",
            "Hosting",
            "Contractors",
            "Advertising",
            "Fees",
            "Meals",
            "Travel",
            "Education",
            "Hardware",
            "Office Supplies",
            "Professional Services"
        ]))
        #expect(buckets["AI Tools"] == "Office expense")
        #expect(buckets["Hosting"] == "Utilities")
        #expect(buckets["Contractors"] == "Contract labor")
        #expect(buckets["Fees"] == "Commissions and fees")
    }

    @Test("Default category seeding adds missing defaults without overwriting existing categories")
    func defaultCategorySeedingAddsMissingDefaultsWithoutOverwritingExistingCategories() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let existing = ExpenseCategory(
            name: "Software",
            taxBucket: "Custom software bucket",
            icon: "hammer",
            colorHex: "111111",
            sortOrder: 42
        )
        context.insert(existing)
        try context.save()

        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: context)

        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let softwareRows = categories.filter { $0.name == "Software" }

        #expect(categories.count == ExpenseCategory.defaultCategoryDefinitions.count)
        #expect(softwareRows.count == 1)
        #expect(softwareRows.first?.taxBucket == "Custom software bucket")
        #expect(categories.contains { $0.name == "AI Tools" })
    }

    @Test("Business dimensions persist locally")
    func businessDimensionsPersistLocally() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        context.insert(BusinessDimension(kind: .account, name: "Amex", sortOrder: 0))
        context.insert(BusinessDimension(kind: .vendor, name: "OpenAI", sortOrder: 1))
        context.insert(BusinessDimension(kind: .client, name: "Acme", sortOrder: 2))
        context.insert(BusinessDimension(kind: .project, name: "Launch", sortOrder: 3))
        try context.save()

        let dimensions = try context.fetch(FetchDescriptor<BusinessDimension>())
        let kinds = Set(dimensions.map(\.kind))

        #expect(dimensions.count == 4)
        #expect(kinds == Set(BusinessDimensionKind.allCases))
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

    @Test("CSV import uses saved profile for custom headers")
    func csvImportUsesSavedProfileForCustomHeaders() throws {
        let csv = """
        When,Counterparty,Cash Out,Curr,Acct,Memo
        2026-06-01,OpenAI,20.00,USD,Amex,API usage
        """
        let url = try writeTemporaryCSV(csv)
        let profile = CSVImportProfile(
            name: "Custom Card",
            importMode: .statementReview,
            mapping: CSVColumnMapping(
                dateHeader: "When",
                merchantHeader: "Counterparty",
                debitHeader: "Cash Out",
                accountHeader: "Acct",
                noteHeader: "Memo",
                currencyHeader: "Curr"
            )
        )

        let summary = try ExpenseImportService.previewCSV(
            at: url,
            existingExpenses: [],
            source: profile.importMode.source,
            defaultStatus: profile.importMode.defaultStatus,
            profile: profile
        )

        let expense = try #require(summary.accepted.first?.expense)
        #expect(summary.activeProfileName == "Custom Card")
        #expect(summary.columnMapping.dateHeader == "When")
        #expect(summary.columnMapping.merchantHeader == "Counterparty")
        #expect(summary.columnMapping.debitHeader == "Cash Out")
        #expect(expense.merchant == "OpenAI")
        #expect(expense.amount == 20)
        #expect(expense.paymentAccount == "Amex")
        #expect(expense.note == "API usage")
        #expect(expense.status == .draft)
        #expect(expense.source == .csvImport)
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

    @Test("CSV import profiles persist locally")
    func csvImportProfilesPersistLocally() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let profile = CSVImportProfile(
            name: "Amex Export",
            importMode: .waveMigration,
            mapping: CSVColumnMapping(
                dateHeader: "Posted",
                merchantHeader: "Description",
                amountHeader: "Amount",
                categoryHeader: "Category"
            )
        )
        context.insert(profile)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<CSVImportProfile>())
        let storedProfile = try #require(profiles.first)

        #expect(storedProfile.name == "Amex Export")
        #expect(storedProfile.importMode == .waveMigration)
        #expect(storedProfile.mapping.dateHeader == "Posted")
        #expect(storedProfile.mapping.mappedCount == 4)
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

    @Test("Email receipt import extracts supported attachments and source metadata")
    func emailReceiptImportExtractsSupportedAttachmentsAndSourceMetadata() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let receiptData = Data("OpenAI receipt".utf8)
        let emlURL = try writeTemporaryFile(
            named: "openai-message.eml",
            contents: emailMessage(
                attachmentFilename: "openai.txt",
                attachmentContentType: "text/plain",
                attachmentBody: receiptData.base64EncodedString()
            )
        )

        let summary = EmailReceiptImportService.importEMLFiles(
            at: [emlURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        let attachment = try #require(attachments.first)
        #expect(summary.messageCount == 1)
        #expect(summary.importedCount == 1)
        #expect(summary.duplicateCount == 0)
        #expect(summary.skippedAttachmentCount == 0)
        #expect(summary.failedFilenames.isEmpty)
        #expect(attachments.count == 1)
        #expect(attachment.originalFilename == "openai.txt")
        #expect(attachment.sourceMessageFilename == "openai-message.eml")
        #expect(attachment.sourceMessageSubject == "OpenAI receipt")
        #expect(attachment.sourceMessageSender == "billing@example.com")
        #expect(attachment.sourceMessageID == "<openai@example.com>")
        #expect(attachment.sourceMessageDate != nil)
        #expect(FileManager.default.fileExists(atPath: attachment.localPath))
    }

    @Test("Email receipt import dedupes attachments through receipt vault")
    func emailReceiptImportDedupesAttachmentsThroughReceiptVault() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let receiptData = Data("duplicate receipt".utf8)
        let emlURL = try writeTemporaryFile(
            named: "duplicate-message.eml",
            contents: emailMessage(
                attachmentFilename: "duplicate.txt",
                attachmentContentType: "text/plain",
                attachmentBody: receiptData.base64EncodedString()
            )
        )

        let first = EmailReceiptImportService.importEMLFiles(
            at: [emlURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()
        let second = EmailReceiptImportService.importEMLFiles(
            at: [emlURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        #expect(first.importedCount == 1)
        #expect(first.duplicateCount == 0)
        #expect(second.importedCount == 0)
        #expect(second.duplicateCount == 1)
        #expect(attachments.count == 1)
    }

    @Test("Email receipt import handles multiple message files")
    func emailReceiptImportHandlesMultipleMessageFiles() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let firstURL = try writeTemporaryFile(
            named: "first.eml",
            contents: emailMessage(
                attachmentFilename: "first.txt",
                attachmentContentType: "text/plain",
                attachmentBody: Data("first receipt".utf8).base64EncodedString()
            )
        )
        let secondURL = try writeTemporaryFile(
            named: "second.eml",
            contents: emailMessage(
                attachmentFilename: "second.txt",
                attachmentContentType: "text/plain",
                attachmentBody: Data("second receipt".utf8).base64EncodedString()
            )
        )

        let summary = EmailReceiptImportService.importEMLFiles(
            at: [firstURL, secondURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        #expect(summary.messageCount == 2)
        #expect(summary.importedCount == 2)
        #expect(summary.duplicateCount == 0)
        #expect(summary.failedFilenames.isEmpty)
        #expect(attachments.count == 2)
    }

    @Test("Email receipt import skips unsupported attachments")
    func emailReceiptImportSkipsUnsupportedAttachments() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let emlURL = try writeTemporaryFile(
            named: "unsupported-message.eml",
            contents: emailMessage(
                attachmentFilename: "installer.exe",
                attachmentContentType: "application/octet-stream",
                attachmentBody: Data("nope".utf8).base64EncodedString()
            )
        )

        let summary = EmailReceiptImportService.importEMLFiles(
            at: [emlURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        #expect(summary.importedCount == 0)
        #expect(summary.duplicateCount == 0)
        #expect(summary.skippedAttachmentCount == 1)
        #expect(summary.failedFilenames.isEmpty)
        #expect(attachments.isEmpty)
    }

    @Test("Email receipt import reports malformed messages safely")
    func emailReceiptImportReportsMalformedMessagesSafely() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let emlURL = try writeTemporaryFile(named: "bad.eml", contents: "this is not a valid message")

        let summary = EmailReceiptImportService.importEMLFiles(
            at: [emlURL],
            context: context,
            vaultDirectory: vaultURL
        )
        try context.save()

        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        #expect(summary.importedCount == 0)
        #expect(summary.duplicateCount == 0)
        #expect(summary.failedFilenames == ["bad.eml"])
        #expect(attachments.isEmpty)
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

    @Test("Backup integrity reports corrupt and missing receipts")
    func backupIntegrityReportsCorruptAndMissingReceipts() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let receiptURL = vaultURL.appendingPathComponent("openai.pdf")
        let receiptData = try #require("receipt-data".data(using: .utf8))
        try receiptData.write(to: receiptURL)
        let receiptHash = ReceiptVault.contentHash(for: receiptData)
        let expense = Expense(merchant: "OpenAI", amount: 20, receiptContentHash: receiptHash)
        let attachment = ReceiptAttachment(
            expenseID: expense.id,
            originalFilename: "openai.pdf",
            localPath: receiptURL.path,
            contentHash: receiptHash
        )
        expense.receiptAttachmentID = attachment.id
        context.insert(expense)
        context.insert(attachment)
        try context.save()

        let cleanReport = try RemnantBackupService.integrityReport(context: context, vaultDirectory: vaultURL)
        #expect(cleanReport.issues.isEmpty)

        try "changed".write(to: receiptURL, atomically: true, encoding: .utf8)
        let corruptReport = try RemnantBackupService.integrityReport(context: context, vaultDirectory: vaultURL)
        #expect(corruptReport.issues.contains { $0.kind == .corruptReceiptFile })

        try FileManager.default.removeItem(at: receiptURL)
        let missingReport = try RemnantBackupService.integrityReport(context: context, vaultDirectory: vaultURL)
        #expect(missingReport.issues.contains { $0.kind == .missingReceiptFile })
    }

    @Test("Backup integrity reports broken links")
    func backupIntegrityReportsBrokenLinks() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let receiptURL = vaultURL.appendingPathComponent("receipt.pdf")
        let receiptData = try #require("receipt".data(using: .utf8))
        try receiptData.write(to: receiptURL)
        let receiptHash = ReceiptVault.contentHash(for: receiptData)
        let expense = Expense(merchant: "Missing Attachment", amount: 20, receiptAttachmentID: UUID())
        let attachment = ReceiptAttachment(
            expenseID: UUID(),
            originalFilename: "receipt.pdf",
            localPath: receiptURL.path,
            contentHash: receiptHash
        )
        context.insert(expense)
        context.insert(attachment)
        try context.save()

        let report = try RemnantBackupService.integrityReport(context: context, vaultDirectory: vaultURL)

        #expect(report.issues.contains { $0.kind == .brokenExpenseAttachmentLink })
        #expect(report.issues.contains { $0.kind == .brokenAttachmentExpenseLink })
    }

    @Test("Backup repair updates restored receipt paths")
    func backupRepairUpdatesRestoredReceiptPaths() throws {
        let container = try makeExpenseContainer()
        let context = container.mainContext
        let vaultURL = try makeTemporaryDirectory()
        let receiptData = try #require("receipt".data(using: .utf8))
        let receiptHash = ReceiptVault.contentHash(for: receiptData)
        let receiptURL = vaultURL.appendingPathComponent("\(receiptHash).pdf")
        try receiptData.write(to: receiptURL)
        let attachment = ReceiptAttachment(
            originalFilename: "receipt.pdf",
            localPath: "/old/remnant/\(receiptHash).pdf",
            contentHash: receiptHash
        )
        context.insert(attachment)
        try context.save()

        let staleReport = try RemnantBackupService.integrityReport(context: context, vaultDirectory: vaultURL)
        let repairedCount = try RemnantBackupService.repairReceiptPaths(context: context, vaultDirectory: vaultURL)

        #expect(staleReport.issues.contains { $0.kind == .staleReceiptPath })
        #expect(repairedCount == 1)
        #expect(attachment.localPath == receiptURL.path)
    }

    @Test("Backup package validation detects copied receipt corruption")
    func backupPackageValidationDetectsCopiedReceiptCorruption() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("RemnantExpenseTrackerV1.store")
        let vaultURL = directory.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let receiptURL = vaultURL.appendingPathComponent("receipt.pdf")
        let receiptData = try #require("receipt".data(using: .utf8))
        try receiptData.write(to: receiptURL)
        let receiptHash = ReceiptVault.contentHash(for: receiptData)
        let container = try RemnantStore.makeContainer(storeURL: storeURL)
        let context = container.mainContext
        let expense = Expense(merchant: "OpenAI", amount: 20, receiptContentHash: receiptHash)
        let attachment = ReceiptAttachment(
            expenseID: expense.id,
            originalFilename: "receipt.pdf",
            localPath: receiptURL.path,
            contentHash: receiptHash
        )
        expense.receiptAttachmentID = attachment.id
        context.insert(expense)
        context.insert(attachment)
        try context.save()

        let backupURL = directory.appendingPathComponent("backup.remnantbackup", isDirectory: true)
        _ = try RemnantBackupService.createBackup(
            at: backupURL,
            context: context,
            storeURL: storeURL,
            vaultDirectory: vaultURL,
            allowOverwrite: true
        )

        let cleanReport = try RemnantBackupService.validateBackup(at: backupURL)
        try "tampered".write(
            to: backupURL
                .appendingPathComponent("Receipts", isDirectory: true)
                .appendingPathComponent("receipt.pdf"),
            atomically: true,
            encoding: .utf8
        )
        let corruptReport = try RemnantBackupService.validateBackup(at: backupURL)

        #expect(cleanReport.issues.isEmpty)
        #expect(corruptReport.issues.contains { $0.kind == .corruptBackupFile })
    }

    @Test("Restore staging requires explicit confirmation")
    func restoreStagingRequiresExplicitConfirmation() throws {
        let backupURL = try makeTemporaryDirectory()

        do {
            _ = try RemnantBackupService.stageRestore(from: backupURL, allowOverwrite: false)
            Issue.record("Restore should require confirmation.")
        } catch RemnantBackupError.restoreRequiresConfirmation {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

    private func emailMessage(
        attachmentFilename: String,
        attachmentContentType: String,
        attachmentBody: String
    ) -> String {
        """
        From: billing@example.com
        Subject: OpenAI receipt
        Date: Tue, 02 Jun 2026 10:30:00 -0400
        Message-ID: <openai@example.com>
        Content-Type: multipart/mixed; boundary="remnant-boundary"

        --remnant-boundary
        Content-Type: text/plain; charset="utf-8"

        Attached.
        --remnant-boundary
        Content-Type: \(attachmentContentType); name="\(attachmentFilename)"
        Content-Disposition: attachment; filename="\(attachmentFilename)"
        Content-Transfer-Encoding: base64

        \(attachmentBody)
        --remnant-boundary--
        """
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
            for: Expense.self, ReceiptAttachment.self, ExpenseCategory.self, BusinessDimension.self, CSVImportProfile.self, ImportBatch.self, VendorRule.self,
            configurations: config
        )
    }
}
