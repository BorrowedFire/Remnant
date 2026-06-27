import Foundation
import SwiftData

enum ExpenseStatus: String, Codable, CaseIterable {
    case draft
    case reviewed
    case reimbursable
    case ignored
}

enum ExpenseSource: String, Codable, CaseIterable {
    case manual
    case csvImport
    case waveImport
    case gmailReview
}

enum ExpenseImportMode: String, Codable, CaseIterable, Identifiable {
    case statementReview
    case waveMigration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .statementReview:
            "New Review"
        case .waveMigration:
            "Wave Migration"
        }
    }

    var detail: String {
        switch self {
        case .statementReview:
            "Fresh bank or card CSVs stay in draft until reviewed."
        case .waveMigration:
            "Historical Wave exports import as reviewed expenses."
        }
    }

    var source: ExpenseSource {
        switch self {
        case .statementReview:
            .csvImport
        case .waveMigration:
            .waveImport
        }
    }

    var defaultStatus: ExpenseStatus {
        switch self {
        case .statementReview:
            .draft
        case .waveMigration:
            .reviewed
        }
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var date: Date = Date()
    var merchant: String = ""
    var amount: Decimal = 0
    var currencyCode: String = "USD"
    var categoryName: String?
    var note: String = ""
    var paymentAccount: String = ""
    var paymentMethod: String = ""
    var taxYear: Int = Calendar.current.component(.year, from: Date())
    var status: ExpenseStatus = ExpenseStatus.draft
    var source: ExpenseSource = ExpenseSource.manual
    var receiptAttachmentID: UUID?
    var receiptFilename: String?
    var receiptContentHash: String?
    var importBatchID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        date: Date = Date(),
        merchant: String,
        amount: Decimal,
        currencyCode: String = "USD",
        categoryName: String? = nil,
        note: String = "",
        paymentAccount: String = "",
        paymentMethod: String = "",
        taxYear: Int? = nil,
        status: ExpenseStatus = .draft,
        source: ExpenseSource = .manual,
        receiptAttachmentID: UUID? = nil,
        receiptFilename: String? = nil,
        receiptContentHash: String? = nil,
        importBatchID: UUID? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.note = note
        self.paymentAccount = paymentAccount
        self.paymentMethod = paymentMethod
        self.taxYear = taxYear ?? Calendar.current.component(.year, from: date)
        self.status = status
        self.source = source
        self.receiptAttachmentID = receiptAttachmentID
        self.receiptFilename = receiptFilename
        self.receiptContentHash = receiptContentHash
        self.importBatchID = importBatchID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ReceiptAttachment {
    var id: UUID = UUID()
    var expenseID: UUID?
    var originalFilename: String = ""
    var localPath: String = ""
    var contentHash: String = ""
    var importedAt: Date = Date()
    var extractedMerchant: String?
    var extractedDate: Date?
    var extractedAmount: Decimal?
    var extractionConfidence: Double = 0

    init(
        expenseID: UUID? = nil,
        originalFilename: String,
        localPath: String,
        contentHash: String,
        importedAt: Date = Date(),
        extractedMerchant: String? = nil,
        extractedDate: Date? = nil,
        extractedAmount: Decimal? = nil,
        extractionConfidence: Double = 0
    ) {
        self.id = UUID()
        self.expenseID = expenseID
        self.originalFilename = originalFilename
        self.localPath = localPath
        self.contentHash = contentHash
        self.importedAt = importedAt
        self.extractedMerchant = extractedMerchant
        self.extractedDate = extractedDate
        self.extractedAmount = extractedAmount
        self.extractionConfidence = extractionConfidence
    }
}

@Model
final class ExpenseCategory {
    var id: UUID = UUID()
    var name: String = ""
    var taxBucket: String = ""
    var icon: String = "folder"
    var colorHex: String = "6B7280"
    var isArchived: Bool = false
    var sortOrder: Int = 0

    init(
        name: String,
        taxBucket: String,
        icon: String,
        colorHex: String,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.taxBucket = taxBucket
        self.icon = icon
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    static let defaultCategoryDefinitions: [(name: String, taxBucket: String, icon: String, colorHex: String)] = [
        ("Software", "Software and subscriptions", "desktopcomputer", "3B82F6"),
        ("Hosting", "Cloud infrastructure", "server.rack", "06B6D4"),
        ("Contractors", "Professional services", "person.2", "8B5CF6"),
        ("Office", "Office supplies", "tray.full", "F59E0B"),
        ("Marketing", "Advertising and marketing", "megaphone", "EF4444"),
        ("Travel", "Business travel", "airplane", "10B981"),
        ("Meals", "Business meals", "fork.knife", "F97316"),
        ("Taxes", "Taxes and fees", "building.columns", "64748B"),
        ("Uncategorized", "Needs review", "questionmark.folder", "6B7280")
    ]
}

@Model
final class ImportBatch {
    var id: UUID = UUID()
    var sourceName: String = ""
    var importMode: ExpenseImportMode = ExpenseImportMode.statementReview
    var importedAt: Date = Date()
    var rowCount: Int = 0
    var acceptedCount: Int = 0
    var duplicateCount: Int = 0
    var ignoredCount: Int = 0
    var notes: String = ""

    init(
        sourceName: String,
        importMode: ExpenseImportMode = .statementReview,
        importedAt: Date = Date(),
        rowCount: Int = 0,
        acceptedCount: Int = 0,
        duplicateCount: Int = 0,
        ignoredCount: Int = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.sourceName = sourceName
        self.importMode = importMode
        self.importedAt = importedAt
        self.rowCount = rowCount
        self.acceptedCount = acceptedCount
        self.duplicateCount = duplicateCount
        self.ignoredCount = ignoredCount
        self.notes = notes
    }
}

@Model
final class VendorRule {
    var id: UUID = UUID()
    var merchantPattern: String = ""
    var defaultCategoryName: String = ""
    var defaultTaxBucket: String = ""
    var createdAt: Date = Date()

    init(
        merchantPattern: String,
        defaultCategoryName: String,
        defaultTaxBucket: String,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.merchantPattern = merchantPattern
        self.defaultCategoryName = defaultCategoryName
        self.defaultTaxBucket = defaultTaxBucket
        self.createdAt = createdAt
    }
}
