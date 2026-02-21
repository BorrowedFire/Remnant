import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class CategoryService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor)
    }

    func seedDefaultsIfNeeded() throws {
        let existing = try fetchAll()
        guard existing.isEmpty else { return }

        for (index, def) in Category.defaults.enumerated() {
            let category = Category(
                name: def.name,
                icon: def.icon,
                colorHex: def.colorHex,
                isDefault: true,
                sortOrder: index
            )
            modelContext.insert(category)
        }
        try modelContext.save()
    }

    func create(name: String, icon: String, colorHex: String) throws -> Category {
        let allCategories = try fetchAll()
        let category = Category(
            name: name,
            icon: icon,
            colorHex: colorHex,
            isDefault: false,
            sortOrder: allCategories.count
        )
        modelContext.insert(category)
        return category
    }

    func delete(_ category: Category) throws {
        guard !category.isDefault else { return }
        guard category.bills.isEmpty else { return }
        modelContext.delete(category)
    }

    func save() throws {
        try modelContext.save()
    }
}
