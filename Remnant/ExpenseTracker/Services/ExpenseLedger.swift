import Foundation
import SwiftData

@MainActor
enum ExpenseLedger {
    static func seedDefaultCategoriesIfNeeded(context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        guard categories.isEmpty else { return }

        for (index, definition) in ExpenseCategory.defaultCategoryDefinitions.enumerated() {
            context.insert(ExpenseCategory(
                name: definition.name,
                taxBucket: definition.taxBucket,
                icon: definition.icon,
                colorHex: definition.colorHex,
                sortOrder: index
            ))
        }

        try context.save()
    }

    static func totalSpent(in expenses: [Expense], for interval: DateInterval) -> Decimal {
        expenses
            .filter { interval.contains($0.date) && $0.status != .ignored }
            .reduce(0) { $0 + $1.amount }
    }

    static func expensesMissingReceipts(in expenses: [Expense]) -> [Expense] {
        expenses.filter { expense in
            expense.status != .ignored
                && isBlank(expense.receiptFilename)
                && isBlank(expense.receiptContentHash)
                && expense.receiptAttachmentID == nil
        }
    }

    static func uncategorizedExpenses(in expenses: [Expense]) -> [Expense] {
        expenses.filter { expense in
            expense.status != .ignored
                && (isBlank(expense.categoryName) || expense.categoryName == "Uncategorized")
        }
    }

    @discardableResult
    static func updateStatus(
        of expenses: [Expense],
        to status: ExpenseStatus,
        updatedAt: Date = Date()
    ) -> Int {
        var changedCount = 0
        for expense in expenses where expense.status != status {
            expense.status = status
            expense.updatedAt = updatedAt
            changedCount += 1
        }
        return changedCount
    }

    static func possibleDuplicate(of candidate: Expense, in expenses: [Expense]) -> Expense? {
        expenses.first { expense in
            guard expense.id != candidate.id else { return false }

            if let candidateHash = normalizedOptional(candidate.receiptContentHash),
               let expenseHash = normalizedOptional(expense.receiptContentHash),
               candidateHash == expenseHash {
                return true
            }

            return Calendar.current.isDate(candidate.date, inSameDayAs: expense.date)
                && candidate.amount == expense.amount
                && normalized(candidate.merchant) == normalized(expense.merchant)
        }
    }

    static func exportCSV(expenses: [Expense]) -> String {
        let header = [
            "Date",
            "Merchant",
            "Amount",
            "Currency",
            "Category",
            "Status",
            "Source",
            "Payment Account",
            "Payment Method",
            "Receipt",
            "Note",
            "Tax Year"
        ]

        let rows = expenses
            .sorted { $0.date < $1.date }
            .map { expense in
                [
                    isoDateFormatter.string(from: expense.date),
                    expense.merchant,
                    "\(expense.amount)",
                    expense.currencyCode,
                    expense.categoryName ?? "",
                    expense.status.rawValue,
                    expense.source.rawValue,
                    expense.paymentAccount,
                    expense.paymentMethod,
                    expense.receiptFilename ?? "",
                    expense.note,
                    "\(expense.taxYear)"
                ].map(csvCell).joined(separator: ",")
            }

        return ([header.map(csvCell).joined(separator: ",")] + rows).joined(separator: "\n")
    }

    static func monthInterval(containing date: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    static func yearInterval(_ year: Int) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func csvCell(_ value: String) -> String {
        var sanitized = value
        if let first = sanitized.first, ["=", "+", "-", "@"].contains(first) {
            sanitized = "'" + sanitized
        }
        let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    static func isBlank(_ value: String?) -> Bool {
        normalizedOptional(value) == nil
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
