import Foundation
import SwiftData

@MainActor
enum ExpenseLedger {
    static func seedDefaultCategoriesIfNeeded(context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        var existingNames = Set(categories.map { normalized($0.name) })
        var nextSortOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        var insertedCount = 0

        for (index, definition) in ExpenseCategory.defaultCategoryDefinitions.enumerated() {
            let normalizedName = normalized(definition.name)
            guard !existingNames.contains(normalizedName) else { continue }

            context.insert(ExpenseCategory(
                name: definition.name,
                taxBucket: definition.taxBucket,
                icon: definition.icon,
                colorHex: definition.colorHex,
                sortOrder: categories.isEmpty ? index : nextSortOrder
            ))
            existingNames.insert(normalizedName)
            insertedCount += 1
            nextSortOrder += 1
        }

        if insertedCount > 0 {
            try context.save()
        }
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

    static func reviewIssues(for expense: Expense, allExpenses: [Expense]) -> Set<ExpenseReviewIssue> {
        guard expense.status != .ignored else { return [] }

        let activeExpenses = allExpenses.filter { $0.status != .ignored }
        var issues = Set<ExpenseReviewIssue>()

        if expense.status == .draft {
            issues.insert(.manualReview)

            if expense.source != .manual {
                issues.insert(.importedDraft)
            }
        }

        if expensesMissingReceipts(in: activeExpenses).contains(where: { $0.id == expense.id }) {
            issues.insert(.missingReceipt)
        }

        if uncategorizedExpenses(in: activeExpenses).contains(where: { $0.id == expense.id }) {
            issues.insert(.uncategorized)
        }

        if possibleDuplicate(of: expense, in: activeExpenses) != nil {
            issues.insert(.duplicateCandidate)
        }

        return issues
    }

    static func reviewInboxExpenses(in expenses: [Expense]) -> [Expense] {
        expenses.filter { !reviewIssues(for: $0, allExpenses: expenses).isEmpty }
    }

    static func expenses(
        _ expenses: [Expense],
        matchingReviewIssue issue: ExpenseReviewIssue,
        allExpenses: [Expense]
    ) -> [Expense] {
        expenses.filter { reviewIssues(for: $0, allExpenses: allExpenses).contains(issue) }
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

    static func exportCSV(expenses: [Expense], categories: [ExpenseCategory] = []) -> String {
        let header = [
            "Date",
            "Merchant",
            "Amount",
            "Currency",
            "Category",
            "Tax Bucket",
            "Account",
            "Vendor",
            "Client",
            "Project",
            "Billable",
            "Reimbursable",
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
                    taxBucket(for: expense.categoryName, categories: categories),
                    dimensionValue(for: expense, kind: .account),
                    dimensionValue(for: expense, kind: .vendor),
                    dimensionValue(for: expense, kind: .client),
                    dimensionValue(for: expense, kind: .project),
                    yesNo(isBillable(expense)),
                    yesNo(isReimbursable(expense)),
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

    static func exportTaxBucketSummaryCSV(expenses: [Expense], categories: [ExpenseCategory] = []) -> String {
        let header = [
            "Tax Bucket",
            "Expense Count",
            "Amount"
        ]
        let grouped = Dictionary(grouping: expenses) { expense in
            taxBucket(for: expense.categoryName, categories: categories)
        }
        let summaries: [(bucket: String, count: Int, total: Decimal)] = grouped
            .map { element in
                let total = element.value.reduce(Decimal(0)) { $0 + $1.amount }
                return (bucket: element.key, count: element.value.count, total: total)
            }

        let rows = summaries
            .sorted { lhs, rhs in
                lhs.bucket.localizedCaseInsensitiveCompare(rhs.bucket) == .orderedAscending
            }
            .map { row in
                [
                    row.bucket,
                    "\(row.count)",
                    "\(row.total)"
                ].map(csvCell).joined(separator: ",")
            }

        return ([header.map(csvCell).joined(separator: ",")] + rows).joined(separator: "\n")
    }

    static func taxBucket(for categoryName: String?, categories: [ExpenseCategory]) -> String {
        guard let normalizedCategory = normalizedOptional(categoryName) else {
            return "Needs review"
        }

        if let category = categories.first(where: { normalized($0.name) == normalizedCategory }),
           let taxBucket = normalizedDisplayValue(category.taxBucket) {
            return taxBucket
        }

        if normalizedCategory == normalized("Uncategorized") {
            return "Needs review"
        }

        return categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func dimensionValue(for expense: Expense, kind: BusinessDimensionKind) -> String {
        switch kind {
        case .account:
            normalizedDisplayValue(expense.paymentAccount) ?? ""
        case .vendor:
            normalizedDisplayValue(expense.vendorName) ?? normalizedDisplayValue(expense.merchant) ?? ""
        case .client:
            normalizedDisplayValue(expense.clientName) ?? ""
        case .project:
            normalizedDisplayValue(expense.projectName) ?? ""
        }
    }

    static func expenses(
        _ expenses: [Expense],
        matching kind: BusinessDimensionKind,
        value: String
    ) -> [Expense] {
        let normalizedValue = normalized(value)
        guard !normalizedValue.isEmpty else { return expenses }

        return expenses.filter { expense in
            normalized(dimensionValue(for: expense, kind: kind)) == normalizedValue
        }
    }

    static func isBillable(_ expense: Expense) -> Bool {
        expense.isBillable
    }

    static func isReimbursable(_ expense: Expense) -> Bool {
        expense.isReimbursable || expense.status == .reimbursable
    }

    static func outstandingBillableExpenses(in expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.status != .ignored && isBillable($0) }
    }

    static func outstandingReimbursableExpenses(in expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.status != .ignored && isReimbursable($0) }
    }

    static func outstandingFollowUpExpenses(in expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.status != .ignored && (isBillable($0) || isReimbursable($0)) }
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

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
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

    private static func normalizedDisplayValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
