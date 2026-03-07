import AppIntents
import SwiftData

struct BillEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill")
    static var defaultQuery = BillEntityQuery()

    var id: UUID
    var name: String
    var expectedAmount: Decimal?

    var displayRepresentation: DisplayRepresentation {
        if let amount = expectedAmount {
            DisplayRepresentation(title: "\(name)", subtitle: "\(amount.currencyFormatted)")
        } else {
            DisplayRepresentation(title: "\(name)")
        }
    }
}

struct BillEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [BillEntity] {
        let context = try ModelContext(sharedModelContainer())
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.isActive })
        let bills = try context.fetch(descriptor)
        return bills
            .filter { identifiers.contains($0.id) }
            .map { BillEntity(id: $0.id, name: $0.name, expectedAmount: $0.expectedAmount) }
    }

    func entities(matching string: String) async throws -> [BillEntity] {
        let context = try ModelContext(sharedModelContainer())
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.isActive })
        let bills = try context.fetch(descriptor)
        return bills
            .filter { $0.name.localizedStandardContains(string) }
            .map { BillEntity(id: $0.id, name: $0.name, expectedAmount: $0.expectedAmount) }
    }

    func suggestedEntities() async throws -> [BillEntity] {
        let context = try ModelContext(sharedModelContainer())
        let descriptor = FetchDescriptor<Bill>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let bills = try context.fetch(descriptor)
        return bills.map { BillEntity(id: $0.id, name: $0.name, expectedAmount: $0.expectedAmount) }
    }
}

/// Shared model container for App Intents (which may run out-of-process).
func sharedModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Account.self, Category.self, IncomeSource.self,
        IncomeEntry.self, Bill.self, Payment.self
    ])
    let config = ModelConfiguration(schema: schema)
    return try ModelContainer(for: schema, configurations: [config])
}
