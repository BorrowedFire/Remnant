import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class IncomeService {
    private let modelContext: ModelContext
    private let accountService: AccountService

    init(modelContext: ModelContext, accountService: AccountService) {
        self.modelContext = modelContext
        self.accountService = accountService
    }

    // MARK: - Sources

    func fetchSources(activeOnly: Bool = true) throws -> [IncomeSource] {
        let descriptor = FetchDescriptor<IncomeSource>(
            predicate: activeOnly ? #Predicate { $0.isActive } : nil,
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func createSource(name: String, frequency: PayFrequency, expectedAmount: Decimal?) -> IncomeSource {
        let source = IncomeSource(name: name, frequency: frequency, expectedAmount: expectedAmount)
        modelContext.insert(source)
        return source
    }

    func archiveSource(_ source: IncomeSource) {
        source.isActive = false
    }

    // MARK: - Entries

    func recordIncome(
        source: IncomeSource,
        amount: Decimal,
        date: Date = Date(),
        account: Account?,
        note: String? = nil
    ) -> IncomeEntry {
        let entry = IncomeEntry(
            amount: amount,
            date: date,
            note: note,
            source: source,
            account: account
        )
        modelContext.insert(entry)

        if let account {
            accountService.addToBalance(account, amount: amount)
        }

        return entry
    }

    func totalIncomeThisMonth() throws -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        let descriptor = FetchDescriptor<IncomeEntry>(
            predicate: #Predicate { $0.date >= startOfMonth && $0.date < startOfNextMonth }
        )
        let entries = try modelContext.fetch(descriptor)
        return entries.reduce(0) { $0 + $1.amount }
    }

    func deleteEntry(_ entry: IncomeEntry) {
        if let account = entry.account {
            accountService.subtractFromBalance(account, amount: entry.amount)
        }
        modelContext.delete(entry)
    }

    func save() throws {
        try modelContext.save()
    }
}
