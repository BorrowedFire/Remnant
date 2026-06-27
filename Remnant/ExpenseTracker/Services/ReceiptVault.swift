import CryptoKit
import Foundation
import SwiftData

enum ReceiptVaultImportStatus: Equatable {
    case imported
    case duplicateUnlinked
    case duplicateLinked(expenseID: UUID)
}

struct ReceiptVaultImportResult {
    let attachment: ReceiptAttachment
    let status: ReceiptVaultImportStatus

    var isDuplicate: Bool {
        status != .imported
    }
}

struct ReceiptVaultBatchSummary {
    let importedCount: Int
    let duplicateCount: Int
    let failedFilenames: [String]
}

enum ReceiptVaultError: LocalizedError {
    case missingApplicationSupportDirectory
    case unreadableReceipt(URL)

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            "Remnant could not locate an Application Support directory for the local receipt vault."
        case .unreadableReceipt(let url):
            "Remnant could not read \(url.lastPathComponent)."
        }
    }
}

@MainActor
enum ReceiptVault {
    static func importReceipt(
        at sourceURL: URL,
        context: ModelContext,
        expense: Expense? = nil,
        vaultDirectory: URL? = nil
    ) throws -> ReceiptVaultImportResult {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: sourceURL) else {
            throw ReceiptVaultError.unreadableReceipt(sourceURL)
        }

        let hash = contentHash(for: data)
        let metadata = ReceiptMetadataExtractor.extract(from: sourceURL, data: data)
        let existing = try existingAttachment(withHash: hash, context: context)

        if let existing {
            applyMetadataIfMissing(metadata, to: existing)
            let status = attachDuplicateIfSafe(existing, to: expense)
            return ReceiptVaultImportResult(attachment: existing, status: status)
        }

        let directory = try vaultDirectory ?? defaultVaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent(vaultFilename(for: sourceURL, hash: hash))
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try data.write(to: destinationURL, options: .atomic)
        }

        let attachment = ReceiptAttachment(
            expenseID: expense?.id,
            originalFilename: sourceURL.lastPathComponent,
            localPath: destinationURL.path,
            contentHash: hash,
            extractedMerchant: metadata.merchant,
            extractedDate: metadata.date,
            extractedAmount: metadata.amount,
            extractionConfidence: metadata.confidence
        )
        context.insert(attachment)
        attachIfNeeded(attachment, to: expense)

        return ReceiptVaultImportResult(attachment: attachment, status: .imported)
    }

    static func link(attachment: ReceiptAttachment, to expense: Expense) {
        guard attachment.expenseID == nil || attachment.expenseID == expense.id else {
            return
        }

        attachment.expenseID = expense.id
        expense.receiptAttachmentID = attachment.id
        expense.receiptFilename = attachment.originalFilename
        expense.receiptContentHash = attachment.contentHash
        expense.updatedAt = Date()
    }

    @discardableResult
    static func createDraftExpense(
        from attachment: ReceiptAttachment,
        context: ModelContext,
        vendorRules: [VendorRule] = []
    ) -> Expense? {
        guard attachment.expenseID == nil,
              let amount = attachment.extractedAmount else {
            return nil
        }

        let merchant = attachment.extractedMerchant ?? fallbackMerchant(for: attachment)
        let expense = Expense(
            date: attachment.extractedDate ?? attachment.importedAt,
            merchant: merchant,
            amount: amount,
            categoryName: VendorRuleMatcher.categoryName(for: merchant, rules: vendorRules) ?? "Uncategorized",
            status: .draft,
            source: .receiptDraft
        )

        context.insert(expense)
        link(attachment: attachment, to: expense)
        return expense
    }

    @discardableResult
    static func createDraftExpenses(
        from attachments: [ReceiptAttachment],
        context: ModelContext,
        vendorRules: [VendorRule] = []
    ) -> Int {
        var createdCount = 0
        for attachment in attachments {
            if createDraftExpense(from: attachment, context: context, vendorRules: vendorRules) != nil {
                createdCount += 1
            }
        }
        return createdCount
    }

    @discardableResult
    static func unlinkAttachments(from expense: Expense, context: ModelContext) throws -> Int {
        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        var changedCount = 0

        for attachment in attachments where isLinked(attachment, to: expense) {
            attachment.expenseID = nil
            changedCount += 1
        }

        if expense.receiptAttachmentID != nil
            || expense.receiptFilename != nil
            || expense.receiptContentHash != nil {
            expense.receiptAttachmentID = nil
            expense.receiptFilename = nil
            expense.receiptContentHash = nil
            expense.updatedAt = Date()
        }

        return changedCount
    }

    static func importReceipts(
        at sourceURLs: [URL],
        context: ModelContext,
        vaultDirectory: URL? = nil
    ) -> ReceiptVaultBatchSummary {
        var importedCount = 0
        var duplicateCount = 0
        var failedFilenames: [String] = []

        for sourceURL in sourceURLs {
            do {
                let result = try importReceipt(
                    at: sourceURL,
                    context: context,
                    vaultDirectory: vaultDirectory
                )
                if result.isDuplicate {
                    duplicateCount += 1
                } else {
                    importedCount += 1
                }
            } catch {
                failedFilenames.append(sourceURL.lastPathComponent)
            }
        }

        return ReceiptVaultBatchSummary(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failedFilenames: failedFilenames
        )
    }

    static func defaultVaultDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ReceiptVaultError.missingApplicationSupportDirectory
        }

        return applicationSupport
            .appendingPathComponent("com.borrowedfire.remnant", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
    }

    static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func existingAttachment(
        withHash hash: String,
        context: ModelContext
    ) throws -> ReceiptAttachment? {
        var descriptor = FetchDescriptor<ReceiptAttachment>(
            predicate: #Predicate { attachment in
                attachment.contentHash == hash
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func attachIfNeeded(_ attachment: ReceiptAttachment, to expense: Expense?) {
        guard let expense else { return }
        link(attachment: attachment, to: expense)
    }

    private static func attachDuplicateIfSafe(
        _ attachment: ReceiptAttachment,
        to expense: Expense?
    ) -> ReceiptVaultImportStatus {
        if let linkedExpenseID = attachment.expenseID {
            return .duplicateLinked(expenseID: linkedExpenseID)
        }

        guard let expense else {
            return .duplicateUnlinked
        }

        link(attachment: attachment, to: expense)
        return .duplicateUnlinked
    }

    private static func isLinked(_ attachment: ReceiptAttachment, to expense: Expense) -> Bool {
        if attachment.expenseID == expense.id {
            return true
        }
        if let receiptAttachmentID = expense.receiptAttachmentID,
           attachment.id == receiptAttachmentID {
            return true
        }
        if let receiptContentHash = expense.receiptContentHash,
           !receiptContentHash.isEmpty,
           attachment.contentHash == receiptContentHash {
            return true
        }
        return false
    }

    private static func applyMetadataIfMissing(_ metadata: ReceiptMetadata, to attachment: ReceiptAttachment) {
        if attachment.extractedMerchant == nil {
            attachment.extractedMerchant = metadata.merchant
        }
        if attachment.extractedDate == nil {
            attachment.extractedDate = metadata.date
        }
        if attachment.extractedAmount == nil {
            attachment.extractedAmount = metadata.amount
        }
        if attachment.extractionConfidence == 0 {
            attachment.extractionConfidence = metadata.confidence
        }
    }

    private static func vaultFilename(for sourceURL: URL, hash: String) -> String {
        let pathExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathExtension.isEmpty else { return hash }
        return "\(hash).\(pathExtension.lowercased())"
    }

    private static func fallbackMerchant(for attachment: ReceiptAttachment) -> String {
        let stem = (attachment.originalFilename as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Receipt" : stem.capitalized
    }
}
