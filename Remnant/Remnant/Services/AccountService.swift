import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AccountService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func fetchAll() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor)
    }

    func create(name: String, type: AccountType, balance: Decimal) -> Account {
        let account = Account(name: name, type: type, currentBalance: balance)
        modelContext.insert(account)
        return account
    }

    func delete(_ account: Account) {
        modelContext.delete(account)
    }

    // MARK: - Balance

    func updateBalance(_ account: Account, to amount: Decimal) {
        account.currentBalance = amount
        account.updatedAt = Date()
    }

    func addToBalance(_ account: Account, amount: Decimal) {
        account.currentBalance += amount
        account.updatedAt = Date()
    }

    func subtractFromBalance(_ account: Account, amount: Decimal) {
        account.currentBalance -= amount
        account.updatedAt = Date()
    }

    func save() throws {
        try modelContext.save()
    }
}
