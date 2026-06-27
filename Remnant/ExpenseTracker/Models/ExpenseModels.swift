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
    case receiptDraft

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if rawValue == "gmailReview" {
            self = .receiptDraft
            return
        }

        guard let source = ExpenseSource(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown expense source: \(rawValue)"
            )
        }

        self = source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

enum BusinessDimensionKind: String, Codable, CaseIterable, Identifiable {
    case account
    case vendor
    case client
    case project

    var id: String { rawValue }

    var label: String {
        switch self {
        case .account: "Account"
        case .vendor: "Vendor"
        case .client: "Client"
        case .project: "Project"
        }
    }

    var pluralLabel: String {
        switch self {
        case .account: "Accounts"
        case .vendor: "Vendors"
        case .client: "Clients"
        case .project: "Projects"
        }
    }
}

enum ExpenseReviewIssue: String, Codable, CaseIterable, Identifiable {
    case importedDraft
    case missingReceipt
    case uncategorized
    case duplicateCandidate
    case manualReview

    var id: String { rawValue }
}

struct CSVColumnMapping: Codable, Equatable {
    var dateHeader: String = ""
    var merchantHeader: String = ""
    var amountHeader: String = ""
    var debitHeader: String = ""
    var creditHeader: String = ""
    var categoryHeader: String = ""
    var accountHeader: String = ""
    var paymentMethodHeader: String = ""
    var noteHeader: String = ""
    var receiptHeader: String = ""
    var transactionTypeHeader: String = ""
    var directionHeader: String = ""
    var currencyHeader: String = ""

    var mappedCount: Int {
        [
            dateHeader,
            merchantHeader,
            amountHeader,
            debitHeader,
            creditHeader,
            categoryHeader,
            accountHeader,
            paymentMethodHeader,
            noteHeader,
            receiptHeader,
            transactionTypeHeader,
            directionHeader,
            currencyHeader
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .count
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
    var vendorName: String = ""
    var clientName: String = ""
    var projectName: String = ""
    var isBillable: Bool = false
    var isReimbursable: Bool = false
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
        vendorName: String? = nil,
        clientName: String = "",
        projectName: String = "",
        isBillable: Bool = false,
        isReimbursable: Bool? = nil,
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
        self.vendorName = vendorName ?? merchant
        self.clientName = clientName
        self.projectName = projectName
        self.isBillable = isBillable
        self.isReimbursable = isReimbursable ?? (status == .reimbursable)
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
final class CSVImportProfile {
    var id: UUID = UUID()
    var name: String = ""
    var importMode: ExpenseImportMode = ExpenseImportMode.statementReview
    var dateHeader: String = ""
    var merchantHeader: String = ""
    var amountHeader: String = ""
    var debitHeader: String = ""
    var creditHeader: String = ""
    var categoryHeader: String = ""
    var accountHeader: String = ""
    var paymentMethodHeader: String = ""
    var noteHeader: String = ""
    var receiptHeader: String = ""
    var transactionTypeHeader: String = ""
    var directionHeader: String = ""
    var currencyHeader: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        importMode: ExpenseImportMode = .statementReview,
        mapping: CSVColumnMapping = CSVColumnMapping()
    ) {
        self.id = UUID()
        self.name = name
        self.importMode = importMode
        self.createdAt = Date()
        self.updatedAt = Date()
        apply(mapping: mapping)
    }

    var mapping: CSVColumnMapping {
        CSVColumnMapping(
            dateHeader: dateHeader,
            merchantHeader: merchantHeader,
            amountHeader: amountHeader,
            debitHeader: debitHeader,
            creditHeader: creditHeader,
            categoryHeader: categoryHeader,
            accountHeader: accountHeader,
            paymentMethodHeader: paymentMethodHeader,
            noteHeader: noteHeader,
            receiptHeader: receiptHeader,
            transactionTypeHeader: transactionTypeHeader,
            directionHeader: directionHeader,
            currencyHeader: currencyHeader
        )
    }

    func apply(mapping: CSVColumnMapping) {
        dateHeader = mapping.dateHeader
        merchantHeader = mapping.merchantHeader
        amountHeader = mapping.amountHeader
        debitHeader = mapping.debitHeader
        creditHeader = mapping.creditHeader
        categoryHeader = mapping.categoryHeader
        accountHeader = mapping.accountHeader
        paymentMethodHeader = mapping.paymentMethodHeader
        noteHeader = mapping.noteHeader
        receiptHeader = mapping.receiptHeader
        transactionTypeHeader = mapping.transactionTypeHeader
        directionHeader = mapping.directionHeader
        currencyHeader = mapping.currencyHeader
        updatedAt = Date()
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
        ("Software", "Office expense", "desktopcomputer", "3B82F6"),
        ("AI Tools", "Office expense", "sparkles", "8B5CF6"),
        ("Hosting", "Utilities", "server.rack", "06B6D4"),
        ("Domains", "Advertising", "globe", "0EA5E9"),
        ("Contractors", "Contract labor", "person.2", "A855F7"),
        ("Professional Services", "Legal and professional services", "briefcase", "6366F1"),
        ("Advertising", "Advertising", "megaphone", "EF4444"),
        ("Fees", "Commissions and fees", "dollarsign.circle", "64748B"),
        ("Payment Processing", "Commissions and fees", "creditcard", "475569"),
        ("Meals", "Meals", "fork.knife", "F97316"),
        ("Travel", "Travel", "airplane", "10B981"),
        ("Education", "Other business expense", "book", "14B8A6"),
        ("Hardware", "Depreciation and section 179", "display", "2563EB"),
        ("Office Supplies", "Office expense", "tray.full", "F59E0B"),
        ("Internet & Phone", "Utilities", "wifi", "0891B2"),
        ("Taxes & Licenses", "Taxes and licenses", "building.columns", "6B7280"),
        ("Insurance", "Insurance", "checkmark.shield", "059669"),
        ("Rent & Coworking", "Rent or lease", "building.2", "92400E"),
        ("Postage & Shipping", "Other business expense", "shippingbox", "B45309"),
        ("Uncategorized", "Needs review", "questionmark.folder", "6B7280")
    ]
}

@Model
final class BusinessDimension {
    var id: UUID = UUID()
    var kind: BusinessDimensionKind = BusinessDimensionKind.account
    var name: String = ""
    var note: String = ""
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(
        kind: BusinessDimensionKind,
        name: String,
        note: String = "",
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.kind = kind
        self.name = name
        self.note = note
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
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
