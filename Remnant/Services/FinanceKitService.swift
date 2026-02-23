import Foundation
import SwiftData

#if canImport(FinanceKit)
import FinanceKit

@MainActor
@Observable
final class FinanceKitService {
    private let modelContext: ModelContext
    private let accountService: AccountService

    var isAvailable: Bool { FinanceStore.isDataAvailable(.financialData) }
    var isAuthorized = false

    init(modelContext: ModelContext, accountService: AccountService) {
        self.modelContext = modelContext
        self.accountService = accountService
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let store = FinanceStore.shared
        do {
            let status = try await store.requestAuthorization()
            isAuthorized = (status == .authorized)
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorization() async {
        let store = FinanceStore.shared
        do {
            let status = try await store.authorizationStatus()
            isAuthorized = (status == .authorized)
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Accounts

    func fetchAccounts() async throws -> [FinanceKit.Account] {
        let store = FinanceStore.shared
        let query = AccountQuery(sortDescriptors: [], predicate: nil)
        return try await store.accounts(query: query)
    }

    // MARK: - Balance Sync

    /// Syncs the balance of all linked Remnant accounts with their FinanceKit counterparts.
    func syncLinkedBalances() async {
        guard isAuthorized else { return }

        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.financeKitAccountID != nil }
        )
        guard let linkedAccounts = try? modelContext.fetch(descriptor) else { return }

        let store = FinanceStore.shared
        for account in linkedAccounts {
            guard let fkID = account.financeKitAccountID else { continue }

            do {
                let query = AccountQuery(sortDescriptors: [], predicate: nil)
                let fkAccounts = try await store.accounts(query: query)
                if let fkAccount = fkAccounts.first(where: { $0.id.uuidString == fkID }) {
                    let balance = try await store.accountBalance(account: fkAccount)
                    account.currentBalance = balance.available?.amount ?? account.currentBalance
                    account.updatedAt = Date()
                }
            } catch {
                continue
            }
        }
        try? modelContext.save()
    }

    // MARK: - Transaction Fetch

    func fetchTransactions(for fkAccountID: String, since date: Date) async throws -> [ImportedTransaction] {
        let store = FinanceStore.shared
        let query = TransactionQuery(sortDescriptors: [.init(\.postedDate, order: .reverse)], predicate: nil)
        let fkTransactions = try await store.transactions(query: query)

        return fkTransactions
            .filter { $0.postedDate >= date }
            .map { tx in
                ImportedTransaction(
                    name: tx.merchantName ?? tx.originalDescription ?? "Unknown",
                    amount: abs(tx.transactionAmount.amount),
                    date: tx.postedDate,
                    type: tx.creditDebitIndicator == .debit ? .debit : .credit
                )
            }
    }
}

#else

// Stub for platforms where FinanceKit is unavailable (simulators, older iOS)
@MainActor
@Observable
final class FinanceKitService {
    private let modelContext: ModelContext
    private let accountService: AccountService

    var isAvailable: Bool { false }
    var isAuthorized = false

    init(modelContext: ModelContext, accountService: AccountService) {
        self.modelContext = modelContext
        self.accountService = accountService
    }

    func requestAuthorization() async { }
    func checkAuthorization() async { }
    func syncLinkedBalances() async { }
}

#endif
