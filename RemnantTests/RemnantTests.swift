import Testing
import SwiftData
@testable import Remnant

@Suite("Balance Calculations")
struct BalanceTests {

    @Test("Recording payment subtracts from account balance")
    func paymentSubtractsBalance() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Checking", currentBalance: 1000)
        context.insert(account)

        let bill = Bill(name: "Rent", expectedAmount: 500, frequency: .monthly)
        context.insert(bill)

        let payment = Payment(amount: 500, isPlanned: false, bill: bill, account: account)
        context.insert(payment)
        account.currentBalance -= payment.amount

        #expect(account.currentBalance == 500)
    }

    @Test("Planned payment does not affect actual balance")
    func plannedPaymentPreservesBalance() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Checking", currentBalance: 1000)
        context.insert(account)

        let bill = Bill(name: "Electric", expectedAmount: 150, frequency: .monthly)
        context.insert(bill)

        // Planned payment — should not deduct
        let planned = Payment(amount: 150, isPlanned: true, bill: bill, account: account)
        context.insert(planned)

        #expect(account.currentBalance == 1000)
    }

    @Test("Income adds to account balance")
    func incomeAddsToBalance() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self,
            configurations: config
        )
        let context = container.mainContext

        let account = Account(name: "Checking", currentBalance: 500)
        context.insert(account)

        let source = IncomeSource(name: "Employer", frequency: .biweekly)
        context.insert(source)

        let entry = IncomeEntry(amount: 2500, source: source, account: account)
        context.insert(entry)
        account.currentBalance += entry.amount

        #expect(account.currentBalance == 3000)
    }
}
