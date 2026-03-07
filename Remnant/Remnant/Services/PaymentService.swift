import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PaymentService {
    private let modelContext: ModelContext
    private let accountService: AccountService

    init(modelContext: ModelContext, accountService: AccountService) {
        self.modelContext = modelContext
        self.accountService = accountService
    }

    // MARK: - Record Payment

    func recordPayment(
        bill: Bill,
        amount: Decimal,
        date: Date = Date(),
        account: Account?,
        note: String? = nil
    ) -> Payment {
        let payment = Payment(
            amount: amount,
            date: date,
            note: note,
            isPlanned: false,
            bill: bill,
            account: account
        )
        modelContext.insert(payment)

        if let account {
            accountService.subtractFromBalance(account, amount: amount)
        }

        return payment
    }

    // MARK: - Quick Confirm

    /// Records a payment for a bill's expected amount. Returns nil if the bill has no expected amount.
    func quickConfirmBill(_ bill: Bill, account: Account?) -> Payment? {
        guard let amount = bill.expectedAmount, amount > 0 else { return nil }
        return recordPayment(bill: bill, amount: amount, account: account)
    }

    /// Batch-confirms all provided bills using their expected amounts.
    func batchConfirmBills(_ bills: [Bill], account: Account?) -> [Payment] {
        bills.compactMap { quickConfirmBill($0, account: account) }
    }

    // MARK: - Planning Mode

    func createPlannedPayment(
        bill: Bill,
        amount: Decimal,
        account: Account?
    ) -> Payment {
        let payment = Payment(
            amount: amount,
            date: Date(),
            isPlanned: true,
            bill: bill,
            account: account
        )
        modelContext.insert(payment)
        return payment
    }

    func confirmPlannedPayment(_ payment: Payment) {
        payment.isPlanned = false
        payment.date = Date()
        if let account = payment.account {
            accountService.subtractFromBalance(account, amount: payment.amount)
        }
    }

    func confirmAllPlanned(for account: Account) throws {
        let accountID = account.persistentModelID
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.isPlanned && $0.account?.persistentModelID == accountID }
        )
        let planned = try modelContext.fetch(descriptor)
        for payment in planned {
            confirmPlannedPayment(payment)
        }
        try modelContext.save()
    }

    func discardPlannedPayment(_ payment: Payment) {
        modelContext.delete(payment)
    }

    func discardAllPlanned(for account: Account) throws {
        let accountID = account.persistentModelID
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.isPlanned && $0.account?.persistentModelID == accountID }
        )
        let planned = try modelContext.fetch(descriptor)
        for payment in planned {
            modelContext.delete(payment)
        }
    }

    // MARK: - Queries

    func fetchPlanned(for account: Account) throws -> [Payment] {
        let accountID = account.persistentModelID
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.isPlanned && $0.account?.persistentModelID == accountID },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    func totalPlanned(for account: Account) throws -> Decimal {
        try fetchPlanned(for: account).reduce(0) { $0 + $1.amount }
    }

    func paymentsForMonth(month: Int, year: Int) throws -> [Payment] {
        let calendar = Calendar.current
        var startComponents = DateComponents(year: year, month: month, day: 1)
        guard let startDate = calendar.date(from: startComponents) else { return [] }
        startComponents.month = month + 1
        guard let endDate = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) else { return [] }

        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate {
                !$0.isPlanned && $0.date >= startDate && $0.date < endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func totalPaidThisMonth() throws -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let payments = try paymentsForMonth(month: month, year: year)
        return payments.reduce(0) { $0 + $1.amount }
    }

    func monthlyTotals(for year: Int) throws -> [(month: Int, total: Decimal)] {
        (1...12).map { month in
            let total = (try? paymentsForMonth(month: month, year: year))?.reduce(0) { $0 + $1.amount } ?? 0
            return (month: month, total: total)
        }
    }

    func categoryTotals(month: Int, year: Int) throws -> [(category: String, colorHex: String, total: Decimal)] {
        let payments = try paymentsForMonth(month: month, year: year)
        var totals: [String: (colorHex: String, total: Decimal)] = [:]
        for payment in payments {
            let name = payment.bill?.category?.name ?? "Other"
            let hex = payment.bill?.category?.colorHex ?? "AC8E68"
            let existing = totals[name]
            totals[name] = (colorHex: hex, total: (existing?.total ?? 0) + payment.amount)
        }
        return totals
            .map { (category: $0.key, colorHex: $0.value.colorHex, total: $0.value.total) }
            .sorted { $0.total > $1.total }
    }

    func deletePayment(_ payment: Payment) {
        // If confirmed payment, restore balance
        if !payment.isPlanned, let account = payment.account {
            accountService.addToBalance(account, amount: payment.amount)
        }
        modelContext.delete(payment)
    }

    func save() throws {
        try modelContext.save()
    }
}
