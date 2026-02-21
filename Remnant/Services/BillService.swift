import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class BillService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func fetchAll(activeOnly: Bool = true) throws -> [Bill] {
        let descriptor = FetchDescriptor<Bill>(
            predicate: activeOnly ? #Predicate { $0.isActive } : nil,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByCategory(_ category: Category) throws -> [Bill] {
        let categoryID = category.persistentModelID
        let descriptor = FetchDescriptor<Bill>(
            predicate: #Predicate { $0.category?.persistentModelID == categoryID && $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func create(
        name: String,
        expectedAmount: Decimal?,
        dueDay: Int?,
        dueDate: Date?,
        frequency: BillFrequency,
        category: Category?
    ) -> Bill {
        let bill = Bill(
            name: name,
            expectedAmount: expectedAmount,
            dueDay: dueDay,
            dueDate: dueDate,
            frequency: frequency,
            category: category
        )
        modelContext.insert(bill)
        return bill
    }

    func archive(_ bill: Bill) {
        bill.isActive = false
    }

    func delete(_ bill: Bill) {
        modelContext.delete(bill)
    }

    // MARK: - Queries

    func upcomingBills(within days: Int = 7) throws -> [Bill] {
        let allBills = try fetchAll()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: days, to: today) else {
            return []
        }

        return allBills
            .filter { bill in
                guard let nextDue = bill.nextDueDate else { return false }
                return nextDue >= today && nextDue <= cutoff
            }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    func save() throws {
        try modelContext.save()
    }
}
