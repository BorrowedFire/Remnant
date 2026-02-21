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
            var row = "\"\(bill.name)\",\"\(categoryName)\""
            var yearTotal: Decimal = 0

            for month in 1...12 {
                let amount = bill.totalPaid(month: month, year: year)
                yearTotal += amount
                row += ",\(amount)"
            }
            row += ",\(yearTotal)"
            csv += row + "\n"
        }

        let fileName = "Remnant-\(year).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
