import Foundation

struct AuditPackageSummary: Equatable {
    let expenseCount: Int
    let copiedReceiptCount: Int
    let missingReceiptCount: Int
}

struct AuditPackageManifest: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let expenseCount: Int
    let copiedReceiptCount: Int
    let missingReceiptCount: Int
    let rawExpensesCSVPath: String
    let taxBucketSummaryCSVPath: String
    let expenses: [AuditPackageExpenseRecord]
}

struct AuditPackageExpenseRecord: Codable, Equatable {
    let expenseID: String
    let date: String
    let merchant: String
    let amount: String
    let currencyCode: String
    let categoryName: String?
    let taxBucket: String
    let status: String
    let receiptStatus: String
    let receiptOriginalFilename: String?
    let receiptExportPath: String?
    let receiptSHA256: String?
    let sourceMessageSubject: String?
    let sourceMessageSender: String?
    let sourceMessageDate: String?
}

enum AuditPackageError: LocalizedError {
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let url):
            "An audit package already exists at \(url.lastPathComponent)."
        }
    }
}

@MainActor
enum AuditPackageService {
    static let packageExtension = "remnantaudit"

    private static let manifestFilename = "manifest.json"
    private static let reportsDirectoryName = "Reports"
    private static let receiptsDirectoryName = "Receipts"
    private static let rawExpensesFilename = "raw-expenses.csv"
    private static let taxBucketSummaryFilename = "tax-bucket-summary.csv"

    @discardableResult
    static func createPackage(
        at destinationURL: URL,
        expenses: [Expense],
        categories: [ExpenseCategory],
        attachments: [ReceiptAttachment],
        vaultDirectory: URL? = nil,
        allowOverwrite: Bool = false
    ) throws -> AuditPackageSummary {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard allowOverwrite else {
                throw AuditPackageError.destinationExists(destinationURL)
            }
            try fileManager.removeItem(at: destinationURL)
        }

        let reportsURL = destinationURL.appendingPathComponent(reportsDirectoryName, isDirectory: true)
        let receiptsURL = destinationURL.appendingPathComponent(receiptsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: reportsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: receiptsURL, withIntermediateDirectories: true)

        let sortedExpenses = expenses.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant) == .orderedAscending
            }
            return lhs.date < rhs.date
        }

        try ExpenseLedger.exportCSV(expenses: sortedExpenses, categories: categories)
            .write(to: reportsURL.appendingPathComponent(rawExpensesFilename), atomically: true, encoding: .utf8)
        try ExpenseLedger.exportTaxBucketSummaryCSV(expenses: sortedExpenses, categories: categories)
            .write(to: reportsURL.appendingPathComponent(taxBucketSummaryFilename), atomically: true, encoding: .utf8)

        var copiedReceiptPathsByHash: [String: String] = [:]
        var copiedReceiptCount = 0
        var missingReceiptCount = 0
        var records: [AuditPackageExpenseRecord] = []

        for expense in sortedExpenses {
            let resolvedAttachment = attachment(for: expense, attachments: attachments)
            let receiptRecord = try exportReceiptRecord(
                expense: expense,
                attachment: resolvedAttachment,
                categories: categories,
                receiptsURL: receiptsURL,
                copiedReceiptPathsByHash: &copiedReceiptPathsByHash,
                copiedReceiptCount: &copiedReceiptCount,
                vaultDirectory: vaultDirectory
            )
            if receiptRecord.receiptStatus != "attached" {
                missingReceiptCount += 1
            }
            records.append(receiptRecord)
        }

        let manifest = AuditPackageManifest(
            version: AuditPackageManifest.currentVersion,
            createdAt: Date(),
            expenseCount: sortedExpenses.count,
            copiedReceiptCount: copiedReceiptCount,
            missingReceiptCount: missingReceiptCount,
            rawExpensesCSVPath: "\(reportsDirectoryName)/\(rawExpensesFilename)",
            taxBucketSummaryCSVPath: "\(reportsDirectoryName)/\(taxBucketSummaryFilename)",
            expenses: records
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: destinationURL.appendingPathComponent(manifestFilename),
            options: .atomic
        )

        return AuditPackageSummary(
            expenseCount: sortedExpenses.count,
            copiedReceiptCount: copiedReceiptCount,
            missingReceiptCount: missingReceiptCount
        )
    }

    private static func exportReceiptRecord(
        expense: Expense,
        attachment: ReceiptAttachment?,
        categories: [ExpenseCategory],
        receiptsURL: URL,
        copiedReceiptPathsByHash: inout [String: String],
        copiedReceiptCount: inout Int,
        vaultDirectory: URL?
    ) throws -> AuditPackageExpenseRecord {
        guard let attachment else {
            return manifestRecord(
                for: expense,
                categories: categories,
                receiptStatus: "missing",
                attachment: nil,
                exportPath: nil,
                receiptHash: nil
            )
        }

        let normalizedHash = normalizedHash(attachment.contentHash)
        let copyKey = normalizedHash.isEmpty ? attachment.id.uuidString : normalizedHash
        if let copiedPath = copiedReceiptPathsByHash[copyKey] {
            return manifestRecord(
                for: expense,
                categories: categories,
                receiptStatus: "attached",
                attachment: attachment,
                exportPath: copiedPath,
                receiptHash: normalizedHash
            )
        }

        guard let receiptURL = receiptFileURL(for: attachment, vaultDirectory: vaultDirectory),
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            return manifestRecord(
                for: expense,
                categories: categories,
                receiptStatus: "missingFile",
                attachment: attachment,
                exportPath: nil,
                receiptHash: normalizedHash.isEmpty ? nil : normalizedHash
            )
        }

        let destinationFilename = uniqueReceiptFilename(
            for: expense,
            attachment: attachment,
            in: receiptsURL
        )
        let destinationURL = receiptsURL.appendingPathComponent(destinationFilename)
        try FileManager.default.copyItem(at: receiptURL, to: destinationURL)
        let relativePath = "\(receiptsDirectoryName)/\(destinationFilename)"
        copiedReceiptPathsByHash[copyKey] = relativePath
        copiedReceiptCount += 1

        return manifestRecord(
            for: expense,
            categories: categories,
            receiptStatus: "attached",
            attachment: attachment,
            exportPath: relativePath,
            receiptHash: normalizedHash.isEmpty ? try sha256(for: destinationURL) : normalizedHash
        )
    }

    private static func manifestRecord(
        for expense: Expense,
        categories: [ExpenseCategory],
        receiptStatus: String,
        attachment: ReceiptAttachment?,
        exportPath: String?,
        receiptHash: String?
    ) -> AuditPackageExpenseRecord {
        AuditPackageExpenseRecord(
            expenseID: expense.id.uuidString,
            date: isoDateFormatter.string(from: expense.date),
            merchant: expense.merchant,
            amount: "\(expense.amount)",
            currencyCode: expense.currencyCode,
            categoryName: expense.categoryName,
            taxBucket: ExpenseLedger.taxBucket(for: expense.categoryName, categories: categories),
            status: expense.status.rawValue,
            receiptStatus: receiptStatus,
            receiptOriginalFilename: attachment?.originalFilename,
            receiptExportPath: exportPath,
            receiptSHA256: receiptHash,
            sourceMessageSubject: attachment?.sourceMessageSubject,
            sourceMessageSender: attachment?.sourceMessageSender,
            sourceMessageDate: attachment?.sourceMessageDate.map { isoDateTimeFormatter.string(from: $0) }
        )
    }

    private static func attachment(
        for expense: Expense,
        attachments: [ReceiptAttachment]
    ) -> ReceiptAttachment? {
        if let receiptAttachmentID = expense.receiptAttachmentID,
           let match = attachments.first(where: { $0.id == receiptAttachmentID }) {
            return match
        }

        let expenseHash = normalizedHash(expense.receiptContentHash ?? "")
        if !expenseHash.isEmpty,
           let match = attachments.first(where: { normalizedHash($0.contentHash) == expenseHash }) {
            return match
        }

        if let match = attachments.first(where: { $0.expenseID == expense.id }) {
            return match
        }

        if let receiptFilename = expense.receiptFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !receiptFilename.isEmpty,
           let match = attachments.first(where: { $0.originalFilename == receiptFilename }) {
            return match
        }

        return nil
    }

    private static func receiptFileURL(for attachment: ReceiptAttachment, vaultDirectory: URL?) -> URL? {
        let localURL = URL(fileURLWithPath: attachment.localPath)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        guard let vaultDirectory,
              !normalizedHash(attachment.contentHash).isEmpty else {
            return nil
        }

        let pathExtension = (attachment.originalFilename as NSString).pathExtension.lowercased()
        let filename = pathExtension.isEmpty
            ? normalizedHash(attachment.contentHash)
            : "\(normalizedHash(attachment.contentHash)).\(pathExtension)"
        let vaultURL = vaultDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: vaultURL.path) ? vaultURL : nil
    }

    private static func uniqueReceiptFilename(
        for expense: Expense,
        attachment: ReceiptAttachment,
        in directory: URL
    ) -> String {
        let hashPrefix = String(normalizedHash(attachment.contentHash).prefix(12))
        let extensionCandidate = (attachment.originalFilename as NSString).pathExtension
        let pathExtension = extensionCandidate.isEmpty ? "receipt" : extensionCandidate.lowercased()
        let base = safeFilenameStem(
            "\(isoDateFormatter.string(from: expense.date))-\(expense.merchant)-\(hashPrefix)"
        )
        var filename = "\(base).\(pathExtension)"
        var suffix = 2

        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
            filename = "\(base)-\(suffix).\(pathExtension)"
            suffix += 1
        }

        return filename
    }

    private static func safeFilenameStem(_ value: String) -> String {
        let ascii = value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let cleaned = ascii
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "receipt" : String(cleaned.prefix(96)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func sha256(for fileURL: URL) throws -> String {
        ReceiptVault.contentHash(for: try Data(contentsOf: fileURL))
    }

    private static func normalizedHash(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static var isoDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static var isoDateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }
}
