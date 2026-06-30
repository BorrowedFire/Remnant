import Foundation
import SwiftData

struct ReceiptBackfillImportSummary: Codable, Equatable {
    let sourceName: String
    let importedCount: Int
    let duplicateCount: Int
    let failedCount: Int
    let failedItems: [String]
    let totalAmount: Decimal
}

enum ReceiptBackfillImportError: LocalizedError {
    case missingManifestPath
    case unreadableManifest(URL)
    case invalidAmount(String)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .missingManifestPath:
            "Pass --import-receipts-manifest followed by a manifest JSON path."
        case .unreadableManifest(let url):
            "Remnant could not read the receipt import manifest at \(url.path)."
        case .invalidAmount(let value):
            "Invalid receipt amount: \(value)."
        case .invalidDate(let value):
            "Invalid receipt date: \(value)."
        }
    }
}

@MainActor
enum ReceiptBackfillImportService {
    static func runFromCommandLine(arguments: [String]) throws {
        guard let markerIndex = arguments.firstIndex(of: "--import-receipts-manifest"),
              arguments.indices.contains(markerIndex + 1) else {
            throw ReceiptBackfillImportError.missingManifestPath
        }

        let manifestURL = URL(fileURLWithPath: arguments[markerIndex + 1])
        let summary = try importManifest(at: manifestURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    @discardableResult
    static func importManifest(
        at manifestURL: URL,
        storeURL: URL? = nil,
        vaultDirectory: URL? = nil
    ) throws -> ReceiptBackfillImportSummary {
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ReceiptBackfillImportError.unreadableManifest(manifestURL)
        }

        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ReceiptBackfillManifest.self, from: data)
        let container = try RemnantStore.makeContainer(storeURL: storeURL)
        let context = container.mainContext
        try ExpenseLedger.seedDefaultCategoriesIfNeeded(context: context)

        let batch = ImportBatch(
            sourceName: manifest.sourceName,
            importMode: .statementReview,
            rowCount: manifest.items.count,
            notes: manifest.notes ?? ""
        )
        context.insert(batch)

        var importedCount = 0
        var duplicateCount = 0
        var failedItems: [String] = []
        var totalAmount = Decimal(0)

        for item in manifest.items {
            do {
                let imported = try importItem(
                    item,
                    context: context,
                    batchID: batch.id,
                    vaultDirectory: vaultDirectory
                )
                if imported {
                    importedCount += 1
                    totalAmount += try item.decimalAmount()
                } else {
                    duplicateCount += 1
                }
            } catch {
                failedItems.append(item.failureLabel)
            }
        }

        batch.acceptedCount = importedCount
        batch.duplicateCount = duplicateCount
        batch.ignoredCount = 0
        try context.save()

        return ReceiptBackfillImportSummary(
            sourceName: manifest.sourceName,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failedCount: failedItems.count,
            failedItems: failedItems,
            totalAmount: totalAmount
        )
    }

    private static func importItem(
        _ item: ReceiptBackfillItem,
        context: ModelContext,
        batchID: UUID,
        vaultDirectory: URL?
    ) throws -> Bool {
        let fileURL = URL(fileURLWithPath: item.filePath)
        let amount = try item.decimalAmount()
        let date = try item.parsedDate()
        let status = item.parsedStatus
        let categoryName = item.categoryName ?? "Uncategorized"

        let receiptResult = try ReceiptVault.importReceipt(
            at: fileURL,
            context: context,
            vaultDirectory: vaultDirectory
        )
        let attachment = receiptResult.attachment
        apply(item: item, date: date, amount: amount, to: attachment)

        guard item.createExpense != false else {
            return false
        }

        let expense = Expense(
            date: date,
            merchant: item.merchant,
            amount: amount,
            currencyCode: item.currencyCode ?? "USD",
            categoryName: categoryName,
            note: item.note ?? "",
            paymentAccount: item.paymentAccount ?? "",
            paymentMethod: item.paymentMethod ?? "",
            vendorName: item.vendorName ?? item.merchant,
            clientName: item.clientName ?? "",
            projectName: item.projectName ?? "",
            isBillable: item.isBillable ?? false,
            isReimbursable: item.isReimbursable,
            status: status,
            source: .receiptDraft,
            importBatchID: batchID
        )
        expense.receiptFilename = attachment.originalFilename
        expense.receiptContentHash = attachment.contentHash

        let existingExpenses = try context.fetch(FetchDescriptor<Expense>())
        if let duplicate = ExpenseLedger.possibleDuplicate(of: expense, in: existingExpenses) {
            if item.replaceDuplicateReceipt == true {
                try ReceiptVault.unlinkAttachments(from: duplicate, context: context)
                ReceiptVault.link(attachment: attachment, to: duplicate)
                return false
            }

            guard shouldSkipImport(
                candidate: expense,
                attachment: attachment,
                duplicate: duplicate,
                batchID: batchID
            ) else {
                context.insert(expense)
                ReceiptVault.link(attachment: attachment, to: expense)
                return true
            }

            if attachment.expenseID == nil, duplicate.receiptAttachmentID == nil {
                ReceiptVault.link(attachment: attachment, to: duplicate)
            }
            return false
        }

        context.insert(expense)
        ReceiptVault.link(attachment: attachment, to: expense)
        return true
    }

    private static func apply(
        item: ReceiptBackfillItem,
        date: Date,
        amount: Decimal,
        to attachment: ReceiptAttachment
    ) {
        attachment.extractedMerchant = item.merchant
        attachment.extractedDate = date
        attachment.extractedAmount = amount
        attachment.extractionConfidence = max(attachment.extractionConfidence, 0.90)
        attachment.sourceMessageFilename = item.sourceMessageFilename
        attachment.sourceMessageSubject = item.sourceMessageSubject
        attachment.sourceMessageSender = item.sourceMessageSender
        attachment.sourceMessageDate = item.parsedSourceMessageDate
        attachment.sourceMessageID = item.sourceMessageID
    }

    private static func shouldSkipImport(
        candidate: Expense,
        attachment: ReceiptAttachment,
        duplicate: Expense,
        batchID: UUID
    ) -> Bool {
        if normalized(candidate.receiptContentHash) == normalized(duplicate.receiptContentHash) {
            return true
        }

        if duplicate.importBatchID == batchID,
           normalized(attachment.contentHash) != normalized(duplicate.receiptContentHash) {
            return false
        }

        return true
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

private struct ReceiptBackfillManifest: Decodable {
    let sourceName: String
    let notes: String?
    let items: [ReceiptBackfillItem]
}

private struct ReceiptBackfillItem: Decodable {
    let filePath: String
    let merchant: String
    let amount: String
    let date: String
    let currencyCode: String?
    let categoryName: String?
    let status: String?
    let note: String?
    let paymentAccount: String?
    let paymentMethod: String?
    let vendorName: String?
    let clientName: String?
    let projectName: String?
    let isBillable: Bool?
    let isReimbursable: Bool?
    let sourceMessageFilename: String?
    let sourceMessageSubject: String?
    let sourceMessageSender: String?
    let sourceMessageDate: String?
    let sourceMessageID: String?
    let replaceDuplicateReceipt: Bool?
    let createExpense: Bool?

    var parsedStatus: ExpenseStatus {
        guard let status else { return .draft }
        return ExpenseStatus(rawValue: status) ?? .draft
    }

    var parsedSourceMessageDate: Date? {
        guard let sourceMessageDate else { return nil }
        return Self.date(from: sourceMessageDate)
    }

    var failureLabel: String {
        "\(date) \(merchant) \(amount)"
    }

    func decimalAmount() throws -> Decimal {
        let cleaned = amount
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ReceiptBackfillImportError.invalidAmount(amount)
        }
        return value
    }

    func parsedDate() throws -> Date {
        guard let date = Self.date(from: date) else {
            throw ReceiptBackfillImportError.invalidDate(self.date)
        }
        return date
    }

    private static func date(from value: String) -> Date? {
        let iso8601DateFormatterWithFractions = ISO8601DateFormatter()
        iso8601DateFormatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601DateFormatterWithFractions.date(from: value) {
            return date
        }

        let iso8601DateFormatter = ISO8601DateFormatter()
        iso8601DateFormatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601DateFormatter.date(from: value) {
            return date
        }

        let yyyyMMddFormatter = DateFormatter()
        yyyyMMddFormatter.calendar = Calendar(identifier: .gregorian)
        yyyyMMddFormatter.locale = Locale(identifier: "en_US_POSIX")
        yyyyMMddFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        yyyyMMddFormatter.dateFormat = "yyyy-MM-dd"
        return yyyyMMddFormatter.date(from: value)
    }
}
