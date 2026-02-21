import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case other
}

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var currentBalance: Decimal
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Payment.account)
    var payments: [Payment]

    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.account)
    var incomeEntries: [IncomeEntry]

    init(
        name: String,
        type: AccountType = .checking,
        currentBalance: Decimal = 0,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.payments = []
        self.incomeEntries = []
    }
}
