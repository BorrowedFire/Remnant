import Foundation
import SwiftData

@MainActor
final class ExportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func exportToCSV(year: Int) throws -> URL {
        let bills = try modelContext.fetch(FetchDescriptor<Bill>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        ))

        var csv = "Bill,Category,Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec,Total\n"

        for bill in bills {
            let categoryName = bill.category?.name ?? "Other"
            var row = "\(csvEscape(bill.name)),\(csvEscape(categoryName))"
            var yearTotal: Decimal = 0

            for month in 1...12 {
                let amount = bill.totalPaid(month: month, year: year)
                yearTotal += amount
                row += ",\(amount)"
            }
            row += ",\(yearTotal)"
            csv += row + "\n"
        }

        // Use unique filename to avoid collisions
        let fileName = "Remnant-\(year)-\(UUID().uuidString.prefix(8)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    /// Escapes a string for safe CSV inclusion — prevents formula injection and handles embedded quotes.
    private func csvEscape(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        // Prevent formula injection: prefix dangerous first characters with a single quote
        if let first = escaped.first, ["=", "+", "-", "@"].contains(first) {
            escaped = "'" + escaped
        }
        return "\"\(escaped)\""
    }
}
