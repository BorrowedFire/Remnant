import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExpenseDashboardView: View {
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    @Binding var selectedSection: ExpenseSection
    @Binding var reviewInboxFilter: ExpenseReviewInboxFilter
    @Binding var expenseReviewFilter: ExpenseReviewFilter
    @Binding var expenseSearchText: String
    @Binding var expenseCategoryFilter: String?
    @Binding var reportTaxYear: Int
    @Binding var reportDateRange: ReportDateRange
    @Binding var reportCustomStartDate: Date
    @Binding var reportCustomEndDate: Date

    @State private var editingExpense: Expense?
    @State private var selectedMonthBreakdown: MonthlySpendPoint?

    private var monthInterval: DateInterval {
        ExpenseLedger.monthInterval(containing: Date())
    }

    private var activeExpenses: [Expense] {
        expenses.filter { $0.status != .ignored }
    }

    private var reviewInboxExpenses: [Expense] {
        ExpenseLedger.reviewInboxExpenses(in: activeExpenses)
    }

    private var monthTotal: Decimal {
        ExpenseLedger.totalSpent(in: activeExpenses, for: monthInterval)
    }

    private var currentYearToDateInterval: DateInterval {
        let interval = ExpenseLedger.yearInterval(Calendar.current.component(.year, from: Date()))
        let now = Date()
        let end = now > interval.start ? now : interval.start.addingTimeInterval(1)
        return DateInterval(start: interval.start, end: end)
    }

    private var yearToDateTotal: Decimal {
        ExpenseLedger.totalSpent(in: activeExpenses, for: currentYearToDateInterval)
    }

    private var unmatchedReceiptCount: Int {
        receiptAttachments.filter { $0.expenseID == nil }.count
    }

    private var matchedReceiptCount: Int {
        receiptAttachments.count - unmatchedReceiptCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                dashboardHeader

                overviewMetrics

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        priorityColumn
                            .frame(width: 340)
                        insightsColumn
                            .frame(minWidth: 420)
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        priorityColumn
                        insightsColumn
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
                .frame(width: 660)
        }
        .sheet(item: $selectedMonthBreakdown) { point in
            MonthlySpendBreakdownView(point: point, expenses: activeExpenses)
                .frame(width: 640, height: 560)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            header("Dashboard", subtitle: "Local expense tracking for tax review and receipt evidence.")
            Spacer()
            Text("Local-only ledger")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
        }
    }

    private var overviewMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: Spacing.md)],
            alignment: .leading,
            spacing: Spacing.md
        ) {
            DashboardMetric(
                title: "This Month",
                value: monthTotal.currencyFormatted,
                subtitle: "Cash expenses",
                systemImage: "calendar",
                tint: .blue,
                action: openCurrentMonthReport
            )
            DashboardMetric(
                title: "Year to Date",
                value: yearToDateTotal.currencyFormatted,
                subtitle: "\(activeExpenses.count) local entries",
                systemImage: "sum",
                tint: .green,
                action: openCurrentTaxYearReport
            )
            DashboardMetric(
                title: "Needs Review",
                value: "\(reviewInboxExpenses.count)",
                subtitle: "Drafts and exceptions",
                systemImage: "checklist",
                tint: .orange,
                action: { openReview(.all) }
            )
            DashboardMetric(
                title: "Receipts",
                value: "\(matchedReceiptCount)/\(receiptAttachments.count)",
                subtitle: unmatchedReceiptCount == 0 ? "All matched" : "\(unmatchedReceiptCount) unmatched",
                systemImage: "doc.text.magnifyingglass",
                tint: unmatchedReceiptCount == 0 ? .green : .orange,
                action: openImports
            )
        }
    }

    private var priorityColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            DashboardPanel(title: "Review Work", actionTitle: "\(reviewInboxExpenses.count) open", action: { openReview(.all) }) {
                DashboardQueueRow(
                    title: "Imported drafts",
                    subtitle: "Classify and mark reviewed",
                    value: "\(reviewIssueCount(.importedDraft))",
                    systemImage: "tray.and.arrow.down",
                    tint: .blue,
                    action: { openReview(.importedDraft) }
                )
                DashboardQueueRow(
                    title: "Duplicate candidates",
                    subtitle: "Confirm same-charge matches",
                    value: "\(reviewIssueCount(.duplicateCandidate))",
                    systemImage: "doc.on.doc",
                    tint: .orange,
                    action: { openReview(.duplicateCandidate) }
                )
                DashboardQueueRow(
                    title: "Missing receipts",
                    subtitle: "Needs evidence before export",
                    value: "\(reviewIssueCount(.missingReceipt))",
                    systemImage: "doc.badge.clock",
                    tint: .red,
                    action: { openReview(.missingReceipt) }
                )
                DashboardQueueRow(
                    title: "Uncategorized",
                    subtitle: "Missing tax bucket",
                    value: "\(reviewIssueCount(.uncategorized))",
                    systemImage: "questionmark.folder",
                    tint: .purple,
                    action: { openReview(.uncategorized) }
                )
            }

            DashboardPanel(title: "Receipt Vault", actionTitle: "\(receiptAttachments.count) stored", action: openImports) {
                if receiptAttachments.isEmpty {
                    Text("Imported receipt files appear here after local import.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(receiptAttachments.prefix(5)) { receipt in
                        ReceiptInboxRow(receipt: receipt, action: receiptFileExists(receipt) ? {
                            openReceiptFile(receipt)
                        } : nil)
                    }
                }
            }
        }
    }

    private var insightsColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            DashboardPanel(title: "Expense Flow", actionTitle: "Open reports", action: openCurrentTaxYearReport) {
                MonthlySpendChart(points: monthlySpend) { point in
                    selectedMonthBreakdown = point
                }
                    .frame(height: 220)
            }

            DashboardPanel(title: "Category Spend", actionTitle: "Open expenses", action: { openExpenses(search: "") }) {
                if categorySpend.isEmpty {
                    Text("Categorized expenses will appear after import or manual entry.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categorySpend.prefix(6)) { item in
                        CategorySpendRow(item: item, maxAmount: categorySpend.first?.amount ?? 0) {
                            openExpenses(category: item.name)
                        }
                    }
                }
            }

            DashboardPanel(title: "Recent Expenses", actionTitle: "Open all", action: { openExpenses(search: "") }) {
                if activeExpenses.isEmpty {
                    Text("Add an expense or import a local CSV to start replacing Wave.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeExpenses.prefix(6)) { expense in
                        ExpenseSummaryRow(expense: expense) {
                            editingExpense = expense
                        }
                    }
                }
            }
        }
    }

    private var monthlySpend: [MonthlySpendPoint] {
        let calendar = Calendar.current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()

        return (-11...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: offset, to: currentMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }

            let interval = DateInterval(start: start, end: end)
            let total = ExpenseLedger.totalSpent(in: activeExpenses, for: interval)
            return MonthlySpendPoint(
                id: "\(start.timeIntervalSince1970)",
                label: start.formatted(.dateTime.month(.abbreviated)),
                interval: interval,
                amount: total
            )
        }
    }

    private func reviewIssueCount(_ issue: ExpenseReviewIssue) -> Int {
        ExpenseLedger.expenses(reviewInboxExpenses, matchingReviewIssue: issue, allExpenses: activeExpenses).count
    }

    private func openReview(_ filter: ExpenseReviewInboxFilter) {
        reviewInboxFilter = filter
        selectedSection = .review
    }

    private func openExpenses(search: String) {
        expenseReviewFilter = .all
        expenseSearchText = search
        expenseCategoryFilter = nil
        selectedSection = .expenses
    }

    private func openExpenses(category: String) {
        expenseReviewFilter = .all
        expenseSearchText = ""
        expenseCategoryFilter = category
        selectedSection = .expenses
    }

    private func openImports() {
        selectedSection = .imports
    }

    private func openCurrentTaxYearReport() {
        reportTaxYear = Calendar.current.component(.year, from: Date())
        reportDateRange = .taxYear
        selectedSection = .reports
    }

    private func openCurrentMonthReport() {
        let interval = monthInterval
        reportDateRange = .custom
        reportCustomStartDate = interval.start
        reportCustomEndDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        selectedSection = .reports
    }

    private var categorySpend: [CategorySpendItem] {
        let grouped = Dictionary(grouping: activeExpenses.filter { currentYearToDateInterval.contains($0.date) }) { expense in
            expense.categoryName ?? "Uncategorized"
        }

        return grouped.map { key, values in
            CategorySpendItem(
                id: key,
                name: key,
                amount: values.reduce(Decimal(0)) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.body.weight(.semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(minHeight: 104, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(.quaternary)
        }
    }
}

private struct ActionMetric: View {
    let title: String
    let value: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(14)
            .frame(minWidth: 132, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let action, let actionTitle {
                    Button(action: action) {
                        Label(actionTitle, systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                } else if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(.quaternary)
        }
    }
}

private struct DashboardQueueRow: View {
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.body.weight(.semibold))
                .frame(width: 22, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(minWidth: 34, alignment: .trailing)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct MonthlySpendPoint: Identifiable {
    let id: String
    let label: String
    let interval: DateInterval
    let amount: Decimal
}

private struct MonthlySpendChart: View {
    let points: [MonthlySpendPoint]
    var onSelectMonth: ((MonthlySpendPoint) -> Void)?

    private var maxAmount: Decimal {
        points.map(\.amount).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GeometryReader { proxy in
                let legendHeight: CGFloat = 22
                let labelHeight: CGFloat = 16
                let barHeight = max(120, proxy.size.height - legendHeight - labelHeight - Spacing.lg)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(points.indices, id: \.self) { index in
                            let point = points[index]
                            Button {
                                if point.amount > 0 {
                                    onSelectMonth?(point)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.secondary.opacity(0.10))
                                        if point.amount > 0 {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.green)
                                                .frame(height: renderedBarHeight(for: point.amount, in: barHeight))
                                        }
                                    }
                                    .frame(height: barHeight)
                                    .frame(maxWidth: .infinity)

                                    Text(label(for: index, point: point))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(height: labelHeight)
                                        .frame(maxWidth: .infinity)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .help(point.amount > 0 ? "\(point.label): \(point.amount.currencyFormatted)" : "\(point.label): no expenses")
                        }
                    }

                    HStack(spacing: Spacing.md) {
                        Label("Expense", systemImage: "square.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Peak \(maxAmount.currencyFormatted)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .frame(height: legendHeight)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private func label(for index: Int, point: MonthlySpendPoint) -> String {
        if index == points.count - 1 || index % 2 == 0 {
            return point.label
        }
        return ""
    }

    private func renderedBarHeight(for amount: Decimal, in availableHeight: CGFloat) -> CGFloat {
        guard amount > 0 else { return 0 }
        return max(3, availableHeight * heightRatio(for: amount))
    }

    private func heightRatio(for amount: Decimal) -> CGFloat {
        let maxDouble = NSDecimalNumber(decimal: maxAmount).doubleValue
        guard maxDouble > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount).doubleValue / maxDouble)
    }
}

private struct MonthlySpendBreakdownView: View {
    let point: MonthlySpendPoint
    let expenses: [Expense]

    private var monthExpenses: [Expense] {
        expenses
            .filter { point.interval.contains($0.date) && $0.status != .ignored }
            .sorted { lhs, rhs in
                if lhs.amount == rhs.amount {
                    return lhs.date > rhs.date
                }
                return lhs.amount > rhs.amount
            }
    }

    private var categoryRows: [CategorySpendItem] {
        Dictionary(grouping: monthExpenses) { expense in
            expense.categoryName ?? "Uncategorized"
        }
        .map { name, expenses in
            CategorySpendItem(
                id: name,
                name: name,
                amount: expenses.reduce(Decimal(0)) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(monthTitle) Spend")
                    .font(.title2.weight(.semibold))
                Text("\(monthExpenses.count) expenses · \(point.amount.currencyFormatted)")
                    .foregroundStyle(.secondary)
            }

            if categoryRows.isEmpty {
                emptyState("No expenses", "This month does not have expenses in the local ledger.")
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Category Breakdown")
                        .font(.headline)
                    ForEach(categoryRows) { item in
                        CategorySpendRow(item: item, maxAmount: categoryRows.first?.amount ?? 0)
                    }
                }

                Divider()

                Text("Expenses")
                    .font(.headline)
                List(monthExpenses) { expense in
                    ExpenseSummaryRow(expense: expense)
                }
                .frame(minHeight: 220)
            }
        }
        .padding(24)
    }

    private var monthTitle: String {
        point.interval.start.formatted(.dateTime.month(.wide).year())
    }
}

private struct CategorySpendItem: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
}

private struct CategorySpendRow: View {
    let item: CategorySpendItem
    let maxAmount: Decimal
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                Text(item.amount.currencyFormatted)
                    .monospacedDigit()
                    .lineLimit(1)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: max(4, proxy.size.width * widthRatio))
                    }
            }
            .frame(height: 6)
        }
        .font(.caption)
        .contentShape(Rectangle())
    }

    private var widthRatio: CGFloat {
        let maxDouble = NSDecimalNumber(decimal: maxAmount).doubleValue
        guard maxDouble > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: item.amount).doubleValue / maxDouble)
    }
}

private struct ReceiptInboxRow: View {
    let receipt: ReceiptAttachment
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: receipt.expenseID == nil ? "tray" : "checkmark.circle")
                .foregroundStyle(receipt.expenseID == nil ? .orange : .green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.extractedMerchant ?? receipt.originalFilename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let amount = receipt.extractedAmount {
                Text(amount.currencyFormatted)
                    .font(.caption.monospacedDigit())
            }
            if action != nil {
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var detailText: String {
        let status = receipt.expenseID == nil ? "Unmatched" : "Matched"
        if let date = receipt.extractedDate {
            return "\(status) · \(date.mediumFormatted)"
        }
        return "\(status) · \(receipt.importedAt.mediumFormatted)"
    }
}

private struct ExpenseSummaryRow: View {
    let expense: Expense
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(expense.date.mediumFormatted) · \(expense.categoryName ?? "Uncategorized")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(expense.amount.currencyFormatted)
                .monospacedDigit()
            if action != nil {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ExpenseReviewInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]

    @Binding var issueFilter: ExpenseReviewInboxFilter
    @State private var selectedCategory = "Uncategorized"
    @State private var selectedExpenseIDs = Set<UUID>()
    @State private var editingExpense: Expense?

    init(issueFilter: Binding<ExpenseReviewInboxFilter>) {
        _issueFilter = issueFilter
    }

    private var inboxExpenses: [Expense] {
        ExpenseLedger.reviewInboxExpenses(in: expenses)
    }

    private var filteredExpenses: [Expense] {
        issueFilter.expenses(in: inboxExpenses, allExpenses: expenses)
    }

    private var selectedExpenses: [Expense] {
        expenses.filter { selectedExpenseIDs.contains($0.id) }
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("Review Inbox", subtitle: "Imported cleanup and ledger exceptions.")

            HStack(spacing: Spacing.md) {
                ActionMetric(title: "Inbox", value: "\(inboxExpenses.count)", isSelected: issueFilter == .all) {
                    issueFilter = .all
                }
                ActionMetric(title: "Imported Drafts", value: "\(count(.importedDraft))", isSelected: issueFilter == .importedDraft) {
                    issueFilter = .importedDraft
                }
                ActionMetric(title: "Missing Receipts", value: "\(count(.missingReceipt))", isSelected: issueFilter == .missingReceipt) {
                    issueFilter = .missingReceipt
                }
                ActionMetric(title: "Duplicates", value: "\(count(.duplicateCandidate))", isSelected: issueFilter == .duplicateCandidate) {
                    issueFilter = .duplicateCandidate
                }
                ActionMetric(title: "Uncategorized", value: "\(count(.uncategorized))", isSelected: issueFilter == .uncategorized) {
                    issueFilter = .uncategorized
                }
            }

            HStack(spacing: Spacing.md) {
                Picker("Issue", selection: $issueFilter) {
                    ForEach(ExpenseReviewInboxFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)
                .onChange(of: issueFilter) { _, _ in
                    selectedExpenseIDs.removeAll()
                }

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categoryNames, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)

                Button {
                    updateCategory(selectedCategory, for: selectedExpenses)
                    selectedExpenseIDs.removeAll()
                } label: {
                    Label("Apply Category", systemImage: "tag")
                }
                .disabled(selectedExpenseIDs.isEmpty)

                Button {
                    updateSelectedStatus(.reviewed)
                } label: {
                    Label("Mark Reviewed", systemImage: "checkmark.circle")
                }
                .disabled(selectedExpenseIDs.isEmpty)

                Button(role: .destructive) {
                    updateSelectedStatus(.ignored)
                } label: {
                    Label("Ignore", systemImage: "eye.slash")
                }
                .disabled(selectedExpenseIDs.isEmpty)
            }

            if filteredExpenses.isEmpty {
                emptyState("Review inbox is clear", "Imported drafts and cleanup issues will appear here.")
            } else {
                List(selection: $selectedExpenseIDs) {
                    ForEach(filteredExpenses) { expense in
                        ExpenseReviewInboxRow(
                            expense: expense,
                            issues: ExpenseLedger.reviewIssues(for: expense, allExpenses: expenses),
                            onEdit: {
                                editingExpense = expense
                            },
                            onAttachReceipt: {
                                editingExpense = expense
                            }
                        )
                        .tag(expense.id)
                        .onTapGesture(count: 2) {
                            editingExpense = expense
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                editingExpense = expense
                            }
                            Button("Attach Receipt", systemImage: "doc.badge.plus") {
                                editingExpense = expense
                            }
                            Divider()
                            Menu("Set Category") {
                                ForEach(categoryNames, id: \.self) { category in
                                    Button(category) {
                                        updateCategory(category, for: [expense])
                                    }
                                }
                            }
                            Divider()
                            Button("Mark Reviewed", systemImage: "checkmark.circle") {
                                updateStatus(.reviewed, for: [expense])
                            }
                            Button("Ignore", systemImage: "eye.slash", role: .destructive) {
                                updateStatus(.ignored, for: [expense])
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
                .frame(width: 660)
        }
    }

    private func count(_ issue: ExpenseReviewIssue) -> Int {
        ExpenseLedger.expenses(inboxExpenses, matchingReviewIssue: issue, allExpenses: expenses).count
    }

    private func updateSelectedStatus(_ status: ExpenseStatus) {
        updateStatus(status, for: selectedExpenses)
        selectedExpenseIDs.removeAll()
    }

    private func updateStatus(_ status: ExpenseStatus, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        _ = ExpenseLedger.updateStatus(of: expenses, to: status)
        try? modelContext.save()
    }

    private func updateCategory(_ category: String, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        let now = Date()
        for expense in expenses {
            expense.categoryName = category
            expense.updatedAt = now
        }
        try? modelContext.save()
    }
}

enum ExpenseReviewInboxFilter: String, CaseIterable, Identifiable {
    case all
    case importedDraft
    case missingReceipt
    case uncategorized
    case duplicateCandidate
    case manualReview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Issues"
        case .importedDraft: "Imported Drafts"
        case .missingReceipt: "Missing Receipts"
        case .uncategorized: "Uncategorized"
        case .duplicateCandidate: "Duplicates"
        case .manualReview: "Draft Review"
        }
    }

    private var issue: ExpenseReviewIssue? {
        switch self {
        case .all: nil
        case .importedDraft: .importedDraft
        case .missingReceipt: .missingReceipt
        case .uncategorized: .uncategorized
        case .duplicateCandidate: .duplicateCandidate
        case .manualReview: .manualReview
        }
    }

    @MainActor
    func expenses(in expenses: [Expense], allExpenses: [Expense]) -> [Expense] {
        guard let issue else { return expenses }
        return ExpenseLedger.expenses(expenses, matchingReviewIssue: issue, allExpenses: allExpenses)
    }
}

private struct ExpenseReviewInboxRow: View {
    let expense: Expense
    let issues: Set<ExpenseReviewIssue>
    let onEdit: () -> Void
    let onAttachReceipt: () -> Void

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(expense.date.mediumFormatted) · \(expense.categoryName ?? "Uncategorized") · \(expense.source.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    ForEach(issueList) { issue in
                        Label(issue.label, systemImage: issue.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(expense.status.label)
                .font(.caption)
                .foregroundStyle(expense.status == .reviewed ? .green : .secondary)
            Text(expense.amount.currencyFormatted)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
            Button(action: onAttachReceipt) {
                Label("Attach Receipt", systemImage: "doc.badge.plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Attach receipt")
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Edit expense")
        }
        .padding(.vertical, 4)
    }

    private var issueList: [ExpenseReviewIssue] {
        ExpenseReviewIssue.allCases
            .filter { issues.contains($0) }
    }
}

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]
    @Query(sort: [SortDescriptor(\BusinessDimension.sortOrder), SortDescriptor(\BusinessDimension.name)])
    private var dimensions: [BusinessDimension]

    @Binding var reviewFilter: ExpenseReviewFilter
    @Binding var searchText: String
    @Binding var categoryFilter: String?
    @State private var followUpFilter = ExpenseFollowUpFilter.all
    @State private var dimensionFilterKind: BusinessDimensionKind?
    @State private var dimensionFilterValue = ""
    @State private var isShowingForm = false
    @State private var editingExpense: Expense?
    @State private var selectedExpenseIDs = Set<UUID>()

    init(
        reviewFilter: Binding<ExpenseReviewFilter>,
        searchText: Binding<String>,
        categoryFilter: Binding<String?>
    ) {
        _reviewFilter = reviewFilter
        _searchText = searchText
        _categoryFilter = categoryFilter
    }

    private var filteredExpenses: [Expense] {
        let reviewFiltered = expenses.filter { reviewFilter.includes($0, allExpenses: expenses) }
        let followUpFiltered = followUpFilter.expenses(in: reviewFiltered)
        let categoryFiltered: [Expense]
        if let category = normalizedDisplayValue(categoryFilter) {
            categoryFiltered = followUpFiltered.filter {
                ($0.categoryName ?? "Uncategorized").localizedCaseInsensitiveCompare(category) == .orderedSame
            }
        } else {
            categoryFiltered = followUpFiltered
        }

        let dimensionFiltered: [Expense]
        if let dimensionFilterKind, !dimensionFilterValue.isEmpty {
            dimensionFiltered = ExpenseLedger.expenses(
                categoryFiltered,
                matching: dimensionFilterKind,
                value: dimensionFilterValue
            )
        } else {
            dimensionFiltered = categoryFiltered
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return dimensionFiltered }
        return dimensionFiltered.filter { expense in
            expense.merchant.lowercased().contains(query)
                || expense.note.lowercased().contains(query)
                || (expense.categoryName ?? "").lowercased().contains(query)
                || BusinessDimensionKind.allCases.contains { kind in
                    ExpenseLedger.dimensionValue(for: expense, kind: kind).lowercased().contains(query)
                }
        }
    }

    private var selectedExpenses: [Expense] {
        expenses.filter { selectedExpenseIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("Expenses", subtitle: "Manual entries stay on this Mac unless you export them.")

            Picker("Review Filter", selection: $reviewFilter) {
                ForEach(ExpenseReviewFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: reviewFilter) { _, _ in
                selectedExpenseIDs.removeAll()
            }

            HStack(spacing: Spacing.md) {
                Picker("Follow-up", selection: $followUpFilter) {
                    ForEach(ExpenseFollowUpFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
                .onChange(of: followUpFilter) { _, _ in
                    selectedExpenseIDs.removeAll()
                }

                Picker("Dimension", selection: $dimensionFilterKind) {
                    Text("All Dimensions").tag(Optional<BusinessDimensionKind>.none)
                    ForEach(BusinessDimensionKind.allCases) { kind in
                        Text(kind.label).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
                .onChange(of: dimensionFilterKind) { _, _ in
                    dimensionFilterValue = ""
                    selectedExpenseIDs.removeAll()
                }

                Picker("Value", selection: $dimensionFilterValue) {
                    Text("Any").tag("")
                    ForEach(dimensionFilterValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(dimensionFilterKind == nil || dimensionFilterValues.isEmpty)
                .onChange(of: dimensionFilterValue) { _, _ in
                    selectedExpenseIDs.removeAll()
                }

                if let category = normalizedDisplayValue(categoryFilter) {
                    Button {
                        categoryFilter = nil
                        selectedExpenseIDs.removeAll()
                    } label: {
                        Label("Category: \(category)", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if filteredExpenses.isEmpty {
                emptyState("No matching expenses", "Add a manual expense or import a local CSV.")
            } else {
                List(selection: $selectedExpenseIDs) {
                    ForEach(filteredExpenses) { expense in
                        let receipt = attachment(for: expense)
                        ExpenseRow(
                            expense: expense,
                            receipt: receipt,
                            onEdit: {
                                editingExpense = expense
                            },
                            onOpenReceipt: receipt.map { attachment in
                                { openReceiptFile(attachment) }
                            }
                        )
                            .tag(expense.id)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") {
                                    editingExpense = expense
                                }
                                if let receipt {
                                    Button("Open Receipt", systemImage: "arrow.up.forward.square") {
                                        openReceiptFile(receipt)
                                    }
                                    Button("Show Receipt in Finder", systemImage: "folder") {
                                        revealReceiptFile(receipt)
                                    }
                                }
                                Divider()
                                statusButton("Mark Reviewed", systemImage: "checkmark.circle", status: .reviewed, expenses: [expense])
                                statusButton("Ignore", systemImage: "eye.slash", status: .ignored, expenses: [expense])
                                Divider()
                                followUpButton("Mark Billable", systemImage: "briefcase", expenses: [expense]) {
                                    $0.isBillable = true
                                }
                                followUpButton("Mark Reimbursable", systemImage: "arrow.uturn.left.circle", expenses: [expense]) {
                                    $0.isReimbursable = true
                                }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deleteExpense(expense)
                                }
                            }
                    }
                }
            }
        }
        .padding(24)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingForm = true
                } label: {
                    Label("Add Expense", systemImage: "plus")
                }
            }
            if !selectedExpenseIDs.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Text("\(selectedExpenseIDs.count) selected")
                        .foregroundStyle(.secondary)
                    if selectedExpenses.count == 1, let expense = selectedExpenses.first {
                        Button {
                            editingExpense = expense
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    Button {
                        updateSelectedStatus(.reviewed)
                    } label: {
                        Label("Mark Reviewed", systemImage: "checkmark.circle")
                    }
                    Button {
                        updateSelectedStatus(.ignored)
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    Menu {
                        Button("Mark Billable") {
                            updateSelectedFollowUp { $0.isBillable = true }
                        }
                        Button("Mark Reimbursable") {
                            updateSelectedFollowUp { $0.isReimbursable = true }
                        }
                        Button("Mark Draft") {
                            updateSelectedStatus(.draft)
                        }
                        Button("Clear Selection") {
                            selectedExpenseIDs.removeAll()
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingForm) {
            ExpenseFormView()
                .frame(width: 660)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
                .frame(width: 660)
        }
    }

    private var dimensionFilterValues: [String] {
        guard let dimensionFilterKind else { return [] }
        var values = Set<String>()
        for dimension in dimensions where dimension.kind == dimensionFilterKind && !dimension.isArchived {
            if let name = normalizedDisplayValue(dimension.name) {
                values.insert(name)
            }
        }
        for expense in expenses {
            if let value = normalizedDisplayValue(ExpenseLedger.dimensionValue(for: expense, kind: dimensionFilterKind)) {
                values.insert(value)
            }
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func attachment(for expense: Expense) -> ReceiptAttachment? {
        if let receiptAttachmentID = expense.receiptAttachmentID,
           let match = receiptAttachments.first(where: { $0.id == receiptAttachmentID }) {
            return match
        }
        if let receiptContentHash = expense.receiptContentHash?.trimmingCharacters(in: .whitespacesAndNewlines),
           !receiptContentHash.isEmpty,
           let match = receiptAttachments.first(where: { $0.contentHash == receiptContentHash }) {
            return match
        }
        if let match = receiptAttachments.first(where: { $0.expenseID == expense.id }) {
            return match
        }
        if let receiptFilename = expense.receiptFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !receiptFilename.isEmpty,
           let match = receiptAttachments.first(where: { $0.originalFilename == receiptFilename }) {
            return match
        }
        return nil
    }

    private func statusButton(
        _ title: String,
        systemImage: String,
        status: ExpenseStatus,
        expenses: [Expense]
    ) -> some View {
        Button(title, systemImage: systemImage) {
            updateStatus(status, for: expenses)
        }
        .disabled(expenses.allSatisfy { $0.status == status })
    }

    private func followUpButton(
        _ title: String,
        systemImage: String,
        expenses: [Expense],
        update: @escaping (Expense) -> Void
    ) -> some View {
        Button(title, systemImage: systemImage) {
            updateFollowUp(for: expenses, update: update)
        }
    }

    private func updateSelectedStatus(_ status: ExpenseStatus) {
        updateStatus(status, for: selectedExpenses)
        selectedExpenseIDs.removeAll()
    }

    private func updateSelectedFollowUp(update: @escaping (Expense) -> Void) {
        updateFollowUp(for: selectedExpenses, update: update)
        selectedExpenseIDs.removeAll()
    }

    private func updateStatus(_ status: ExpenseStatus, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        _ = ExpenseLedger.updateStatus(of: expenses, to: status)
        try? modelContext.save()
    }

    private func updateFollowUp(for expenses: [Expense], update: (Expense) -> Void) {
        guard !expenses.isEmpty else { return }
        let now = Date()
        for expense in expenses {
            update(expense)
            expense.updatedAt = now
        }
        try? modelContext.save()
    }

    private func deleteExpense(_ expense: Expense) {
        do {
            try ReceiptVault.unlinkAttachments(from: expense, context: modelContext)
            modelContext.delete(expense)
            try modelContext.save()
        } catch {
            return
        }
    }
}

enum ExpenseReviewFilter: String, CaseIterable, Identifiable {
    case all
    case needsReview
    case missingReceipts
    case uncategorized
    case reviewed
    case ignored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .needsReview: "Needs Review"
        case .missingReceipts: "Missing Receipts"
        case .uncategorized: "Uncategorized"
        case .reviewed: "Reviewed"
        case .ignored: "Ignored"
        }
    }

    @MainActor
    func includes(_ expense: Expense, allExpenses: [Expense]) -> Bool {
        switch self {
        case .all:
            true
        case .needsReview:
            expense.status == .draft
                || ExpenseLedger.expensesMissingReceipts(in: allExpenses).contains { $0.id == expense.id }
                || ExpenseLedger.uncategorizedExpenses(in: allExpenses).contains { $0.id == expense.id }
        case .missingReceipts:
            ExpenseLedger.expensesMissingReceipts(in: allExpenses).contains { $0.id == expense.id }
        case .uncategorized:
            ExpenseLedger.uncategorizedExpenses(in: allExpenses).contains { $0.id == expense.id }
        case .reviewed:
            expense.status == .reviewed
        case .ignored:
            expense.status == .ignored
        }
    }
}

private enum ExpenseFollowUpFilter: String, CaseIterable, Identifiable {
    case all
    case billableOrReimbursable
    case billable
    case reimbursable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Expenses"
        case .billableOrReimbursable: "Billable/Reimbursable"
        case .billable: "Billable"
        case .reimbursable: "Reimbursable"
        }
    }

    @MainActor
    func expenses(in expenses: [Expense]) -> [Expense] {
        switch self {
        case .all:
            expenses
        case .billableOrReimbursable:
            ExpenseLedger.outstandingFollowUpExpenses(in: expenses)
        case .billable:
            ExpenseLedger.outstandingBillableExpenses(in: expenses)
        case .reimbursable:
            ExpenseLedger.outstandingReimbursableExpenses(in: expenses)
        }
    }
}

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\BusinessDimension.sortOrder), SortDescriptor(\BusinessDimension.name)])
    private var dimensions: [BusinessDimension]
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var allExpenses: [Expense]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    private let expense: Expense?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var categoryName = "Uncategorized"
    @State private var status = ExpenseStatus.draft
    @State private var paymentAccount = ""
    @State private var paymentMethod = ""
    @State private var vendorName = ""
    @State private var clientName = ""
    @State private var projectName = ""
    @State private var isBillable = false
    @State private var isReimbursable = false
    @State private var note = ""
    @State private var receiptFilename = ""
    @State private var receiptURL: URL?
    @State private var receiptImportError: String?
    @State private var isShowingReceiptImporter = false

    init(expense: Expense? = nil) {
        self.expense = expense
        _merchant = State(initialValue: expense?.merchant ?? "")
        _amount = State(initialValue: expense.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: expense?.date ?? Date())
        _categoryName = State(initialValue: expense?.categoryName ?? "Uncategorized")
        _status = State(initialValue: expense?.status ?? .draft)
        _paymentAccount = State(initialValue: expense?.paymentAccount ?? "")
        _paymentMethod = State(initialValue: expense?.paymentMethod ?? "")
        _vendorName = State(initialValue: expense?.vendorName ?? "")
        _clientName = State(initialValue: expense?.clientName ?? "")
        _projectName = State(initialValue: ExpenseLedger.isCompanyProjectName(expense?.projectName) ? "" : expense?.projectName ?? "")
        _isBillable = State(initialValue: expense?.isBillable ?? false)
        _isReimbursable = State(initialValue: expense.map { $0.isReimbursable || $0.status == .reimbursable } ?? false)
        _note = State(initialValue: expense?.note ?? "")
        _receiptFilename = State(initialValue: expense?.receiptFilename ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header(formTitle, subtitle: "Saved locally. No receipt or expense data is uploaded.")

            Form {
                TextField("Merchant", text: $merchant)
                TextField("Amount", text: $amount)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Category", selection: $categoryName) {
                    ForEach(categoryNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(ExpenseStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Billable", isOn: $isBillable)
                Toggle("Reimbursable", isOn: $isReimbursable)
                dimensionPicker("Account", kind: .account, selection: $paymentAccount, emptyLabel: "None")
                dimensionPicker("Vendor", kind: .vendor, selection: $vendorName, emptyLabel: "Use merchant")
                dimensionPicker("Client", kind: .client, selection: $clientName, emptyLabel: "None")
                dimensionPicker("Project", kind: .project, selection: $projectName, emptyLabel: "None")
                Picker("Payment Method", selection: $paymentMethod) {
                    Text("Unknown").tag("")
                    ForEach(paymentMethodNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }

            ReceiptPreviewCard(
                title: receiptDisplayName,
                subtitle: receiptSubtitle,
                url: receiptPreviewURL,
                onChoose: {
                    isShowingReceiptImporter = true
                },
                onOpen: receiptPreviewURL.map { url in
                    { _ = NSWorkspace.shared.open(url) }
                },
                onReveal: receiptPreviewURL.map { url in
                    { revealFile(url) }
                }
            )

            if let receiptImportError {
                Text(receiptImportError)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedAmount == nil)
            }
        }
        .padding(24)
        .fileImporter(
            isPresented: $isShowingReceiptImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleReceiptSelection(result)
        }
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    private var paymentMethodNames: [String] {
        var names = Set(["Visa ending 6102"])
        for expense in allExpenses {
            if let name = normalizedDisplayValue(expense.paymentMethod) {
                names.insert(name)
            }
        }
        if let current = normalizedDisplayValue(paymentMethod) {
            names.insert(current)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func dimensionPicker(
        _ title: String,
        kind: BusinessDimensionKind,
        selection: Binding<String>,
        emptyLabel: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(emptyLabel).tag("")
            ForEach(dimensionNames(for: kind, currentValue: selection.wrappedValue), id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private func dimensionNames(for kind: BusinessDimensionKind, currentValue: String) -> [String] {
        var names = Set<String>()
        if kind == .project {
            names.formUnion(ExpenseLedger.defaultProjectNames)
        }
        for dimension in dimensions where dimension.kind == kind && !dimension.isArchived {
            if let name = normalizedDisplayValue(dimension.name) {
                names.insert(name)
            }
        }
        if let current = normalizedDisplayValue(currentValue) {
            names.insert(current)
        }
        if kind == .project {
            names = names.filter { !ExpenseLedger.isCompanyProjectName($0) }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var linkedReceipt: ReceiptAttachment? {
        if let id = expense?.receiptAttachmentID,
           let match = receiptAttachments.first(where: { $0.id == id }) {
            return match
        }
        if let hash = normalizedDisplayValue(expense?.receiptContentHash)?.lowercased(),
           let match = receiptAttachments.first(where: { $0.contentHash.lowercased() == hash }) {
            return match
        }
        if let filename = normalizedDisplayValue(receiptFilename),
           let match = receiptAttachments.first(where: { $0.originalFilename == filename }) {
            return match
        }
        return nil
    }

    private var receiptPreviewURL: URL? {
        receiptURL ?? receiptFileURL(linkedReceipt)
    }

    private var receiptDisplayName: String {
        if let receiptURL {
            return receiptURL.lastPathComponent
        }
        if let linkedReceipt {
            return linkedReceipt.originalFilename
        }
        return normalizedDisplayValue(receiptFilename) ?? "No receipt selected"
    }

    private var receiptSubtitle: String {
        if let linkedReceipt {
            var parts: [String] = ["Stored in local vault"]
            if let merchant = linkedReceipt.extractedMerchant {
                parts.append(merchant)
            }
            if let amount = linkedReceipt.extractedAmount {
                parts.append(amount.currencyFormatted)
            }
            return parts.joined(separator: " · ")
        }
        if receiptURL != nil {
            return "Selected for import when you save"
        }
        if normalizedDisplayValue(receiptFilename) != nil {
            return "No matching local receipt file found"
        }
        return "Attach the source PDF, image, or text receipt for audit evidence."
    }

    private var formTitle: String {
        expense == nil ? "Add Expense" : "Edit Expense"
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let parsedAmount else { return }
        let target = expense ?? Expense(
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: parsedAmount
        )

        do {
            let importedAttachment: ReceiptAttachment?
            if let receiptURL {
                let importResult = try ReceiptVault.importReceipt(
                    at: receiptURL,
                    context: modelContext,
                    expense: nil
                )
                if case .duplicateLinked(let expenseID) = importResult.status,
                   expenseID != target.id {
                    receiptImportError = "That receipt is already linked to another expense."
                    return
                }
                importedAttachment = importResult.attachment
            } else {
                importedAttachment = nil
            }

            applyFormFields(to: target)

            if let importedAttachment {
                ReceiptVault.link(attachment: importedAttachment, to: target)
            }
        } catch {
            receiptImportError = error.localizedDescription
            return
        }

        if expense == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }

    private func applyFormFields(to target: Expense) {
        target.date = date
        target.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        target.amount = parsedAmount ?? target.amount
        target.categoryName = categoryName
        target.status = status
        target.note = note
        target.paymentAccount = paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        target.paymentMethod = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        target.vendorName = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.clientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.projectName = ExpenseLedger.isCompanyProjectName(normalizedProjectName) ? "" : normalizedProjectName
        target.isBillable = isBillable
        target.isReimbursable = isReimbursable || status == .reimbursable
        target.taxYear = Calendar.current.component(.year, from: date)
        target.receiptFilename = receiptFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : receiptFilename
        target.updatedAt = Date()
    }

    private func handleReceiptSelection(_ result: Result<[URL], Error>) {
        receiptImportError = nil

        do {
            guard let url = try result.get().first else { return }
            receiptURL = url
            receiptFilename = url.lastPathComponent
        } catch {
            receiptImportError = error.localizedDescription
        }
    }
}

private enum ReceiptPreviewContent {
    case empty
    case missing
    case image(NSImage)
    case text(String)
    case unsupported
}

private struct ReceiptPreviewCard: View {
    let title: String
    let subtitle: String
    let url: URL?
    let onChoose: () -> Void
    let onOpen: (() -> Void)?
    let onReveal: (() -> Void)?

    private var preview: ReceiptPreviewContent {
        ReceiptPreviewRenderer.preview(for: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Label("Receipt Evidence", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button {
                    onChoose()
                } label: {
                    Label("Choose Receipt", systemImage: "doc.badge.plus")
                }
            }

            HStack(alignment: .top, spacing: Spacing.md) {
                previewBody
                    .frame(width: 220, height: 150)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .stroke(.quaternary)
                    }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Spacer(minLength: 0)

                    HStack(spacing: Spacing.sm) {
                        if let onOpen {
                            Button {
                                onOpen()
                            } label: {
                                Label("Open", systemImage: "arrow.up.forward.square")
                            }
                        }
                        if let onReveal {
                            Button {
                                onReveal()
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch preview {
        case .empty:
            receiptPreviewPlaceholder("No receipt", systemImage: "doc")
        case .missing:
            receiptPreviewPlaceholder("File missing", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(6)
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        case .unsupported:
            receiptPreviewPlaceholder("Preview unavailable", systemImage: "doc.questionmark")
        }
    }

    private func receiptPreviewPlaceholder(_ title: String, systemImage: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ReceiptPreviewRenderer {
    static func preview(for url: URL?) -> ReceiptPreviewContent {
        guard let url else { return .empty }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            return .image(page.thumbnail(of: CGSize(width: 440, height: 300), for: .mediaBox))
        }

        if let image = NSImage(contentsOf: url) {
            return .image(image)
        }

        if isTextFile(url),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
            let normalizedText = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return .text(String(normalizedText.prefix(900)))
        }

        return .unsupported
    }

    private static func isTextFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .text)
    }
}

struct ImportCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ImportBatch.importedAt, order: .reverse)])
    private var importBatches: [ImportBatch]
    @Query(sort: [SortDescriptor(\CSVImportProfile.name)])
    private var importProfiles: [CSVImportProfile]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]

    @State private var isShowingImporter = false
    @State private var isShowingReceiptImporter = false
    @State private var isShowingEmailImporter = false
    @State private var importMode = ExpenseImportMode.statementReview
    @State private var importSummary: ExpenseImportSummary?
    @State private var importError: String?
    @State private var importNotice: String?
    @State private var selectedProfileID: UUID?
    @State private var profileDraftName = ""
    @State private var editingProfile: CSVImportProfile?

    private var selectedProfile: CSVImportProfile? {
        guard let selectedProfileID else { return nil }
        return importProfiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header("Imports", subtitle: "Bring in Wave exports, local receipts, and .eml receipt attachments without connecting to a service.")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Import Mode", selection: $importMode) {
                    ForEach(ExpenseImportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text(importMode.detail)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                Picker("CSV Profile", selection: $selectedProfileID) {
                    Text("Auto Detect").tag(Optional<UUID>.none)
                    ForEach(importProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 260)
                .onChange(of: selectedProfileID) { _, _ in
                    if let selectedProfile {
                        importMode = selectedProfile.importMode
                        profileDraftName = selectedProfile.name
                    } else {
                        profileDraftName = ""
                    }
                    importSummary = nil
                    importNotice = nil
                }

                if let selectedProfile {
                    Button {
                        editingProfile = selectedProfile
                    } label: {
                        Label("Edit Profile", systemImage: "slider.horizontal.3")
                    }
                }
            }

            HStack(spacing: Spacing.md) {
                Button {
                    isShowingImporter = true
                } label: {
                    Label("Choose CSV", systemImage: "doc.badge.plus")
                }
                Button {
                    isShowingReceiptImporter = true
                } label: {
                    Label("Add Receipts", systemImage: "doc.badge.gearshape")
                }
                Button {
                    isShowingEmailImporter = true
                } label: {
                    Label("Import .eml", systemImage: "envelope.badge")
                }
                Text("CSV, receipt, and email files are parsed locally. Nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }

            if let importError {
                Text(importError)
                    .foregroundStyle(.red)
            }
            if let importNotice {
                Text(importNotice)
                    .foregroundStyle(.secondary)
            }

            if let importSummary {
                importPreview(importSummary)
            } else if importBatches.isEmpty && receiptAttachments.isEmpty {
                emptyState("No imports yet", "Choose a Wave CSV or add locally downloaded receipts from your inbox.")
            }

            if !importBatches.isEmpty {
                Text("Import History")
                    .font(.headline)
                List(importBatches) { batch in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(batch.sourceName)
                                .font(.body.weight(.medium))
                            Text("\(batch.importMode.label) · \(batch.importedAt.mediumFormatted)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(batch.acceptedCount) imported")
                        Text("\(batch.duplicateCount) duplicates")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !importProfiles.isEmpty {
                csvProfileList
            }

            if !receiptAttachments.isEmpty {
                Text("Receipt Vault")
                    .font(.headline)
                List(receiptAttachments.prefix(12)) { attachment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(attachment.originalFilename)
                                .font(.body.weight(.medium))
                            Text(attachment.importedAt.mediumFormatted)
                                .foregroundStyle(.secondary)
                            if let summary = receiptMetadataSummary(for: attachment) {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(attachment.contentHash.prefix(12)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            openReceiptFile(attachment)
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(receiptFileExists(attachment) ? "Open receipt" : "Receipt file is missing")
                        .disabled(!receiptFileExists(attachment))
                        Button {
                            revealReceiptFile(attachment)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(receiptFileExists(attachment) ? "Show receipt in Finder" : "Receipt file is missing")
                        .disabled(!receiptFileExists(attachment))
                    }
                }
                .frame(minHeight: 140)
            }

            ReceiptReconciliationPanel(
                receipts: receiptAttachments,
                expenses: expenses
            )
        }
        .padding(24)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .fileImporter(
            isPresented: $isShowingReceiptImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            handleReceiptSelection(result)
        }
        .fileImporter(
            isPresented: $isShowingEmailImporter,
            allowedContentTypes: [emlContentType],
            allowsMultipleSelection: true
        ) { result in
            handleEmailReceiptSelection(result)
        }
        .onChange(of: importMode) { _, _ in
            importSummary = nil
            importNotice = nil
        }
        .sheet(item: $editingProfile) { profile in
            CSVImportProfileFormView(profile: profile)
                .frame(width: 560)
        }
    }

    private func importPreview(_ summary: ExpenseImportSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(summary.sourceName)
                .font(.headline)
            HStack(spacing: Spacing.lg) {
                metric("Rows", "\(summary.rowCount)")
                metric("Ready", "\(summary.accepted.count)")
                metric("Duplicates", "\(summary.duplicates.count)")
                metric("Skipped", "\(summary.ignoredRows.count)")
            }

            HStack(spacing: Spacing.md) {
                Label(summary.activeProfileName ?? "Auto Detect", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Text("\(summary.columnMapping.mappedCount) mapped columns")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                TextField("Profile Name", text: $profileDraftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button {
                    saveProfile(from: summary)
                } label: {
                    Label(selectedProfile == nil ? "Save Profile" : "Update Profile", systemImage: "square.and.arrow.down")
                }
                .disabled(normalizedProfileDraftName.isEmpty || summary.columnMapping.mappedCount == 0)
            }

            if !summary.notes.isEmpty {
                ForEach(summary.notes, id: \.self) { note in
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }

            if !summary.accepted.isEmpty {
                List(summary.accepted.prefix(12)) { candidate in
                    HStack {
                        Text("#\(candidate.sourceRow)")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Text(candidate.expense.merchant)
                        Spacer()
                        Text(candidate.expense.amount.currencyFormatted)
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 140)
            }

            HStack {
                Button("Clear Preview") {
                    importSummary = nil
                }
                Spacer()
                Button("Import \(summary.accepted.count) Expenses") {
                    commitImport(summary)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(summary.accepted.isEmpty)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var csvProfileList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("CSV Profiles")
                .font(.headline)
            List(importProfiles) { profile in
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.body.weight(.medium))
                        Text("\(profile.importMode.label) · \(profile.mapping.mappedCount) mapped columns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        selectedProfileID = profile.id
                        importMode = profile.importMode
                        profileDraftName = profile.name
                        importSummary = nil
                    } label: {
                        Label("Use", systemImage: "checkmark.circle")
                    }
                    Button {
                        editingProfile = profile
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        deleteProfile(profile)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .frame(minHeight: 150)
        }
    }

    private var emlContentType: UTType {
        UTType(filenameExtension: "eml") ?? .data
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let profile = selectedProfile
            importSummary = try ExpenseImportService.previewCSV(
                at: url,
                existingExpenses: expenses,
                source: importMode.source,
                defaultStatus: importMode.defaultStatus,
                profile: profile,
                vendorRules: vendorRules
            )
            if profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileDraftName = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            importSummary = nil
            importError = error.localizedDescription
        }
    }

    private func commitImport(_ summary: ExpenseImportSummary) {
        let batch = ImportBatch(
            sourceName: summary.sourceName,
            importMode: importMode,
            rowCount: summary.rowCount,
            acceptedCount: summary.accepted.count,
            duplicateCount: summary.duplicates.count,
            ignoredCount: summary.ignoredRows.count,
            notes: ([importMode.detail, profileNote(for: summary)] + summary.notes).joined(separator: " ")
        )
        modelContext.insert(batch)

        for candidate in summary.accepted {
            candidate.expense.importBatchID = batch.id
            modelContext.insert(candidate.expense)
        }

        try? modelContext.save()
        importSummary = nil
        importNotice = "Imported \(summary.accepted.count) expenses from \(summary.sourceName)."
    }

    private var normalizedProfileDraftName: String {
        profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveProfile(from summary: ExpenseImportSummary) {
        guard !normalizedProfileDraftName.isEmpty else { return }

        if let selectedProfile {
            selectedProfile.name = normalizedProfileDraftName
            selectedProfile.importMode = importMode
            selectedProfile.apply(mapping: summary.columnMapping)
            selectedProfileID = selectedProfile.id
        } else {
            let profile = CSVImportProfile(
                name: normalizedProfileDraftName,
                importMode: importMode,
                mapping: summary.columnMapping
            )
            modelContext.insert(profile)
            selectedProfileID = profile.id
        }

        try? modelContext.save()
        importNotice = "Saved CSV profile \(normalizedProfileDraftName)."
    }

    private func deleteProfile(_ profile: CSVImportProfile) {
        if selectedProfileID == profile.id {
            selectedProfileID = nil
            profileDraftName = ""
            importSummary = nil
        }
        modelContext.delete(profile)
        try? modelContext.save()
    }

    private func profileNote(for summary: ExpenseImportSummary) -> String {
        if let activeProfileName = summary.activeProfileName {
            return "Profile: \(activeProfileName)."
        }
        return "Profile: Auto Detect."
    }

    private func handleReceiptSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            let urls = try result.get()
            let summary = ReceiptVault.importReceipts(at: urls, context: modelContext)
            try modelContext.save()

            var parts = ["Added \(summary.importedCount) receipts"]
            if summary.duplicateCount > 0 {
                parts.append("\(summary.duplicateCount) duplicates")
            }
            if !summary.failedFilenames.isEmpty {
                parts.append("\(summary.failedFilenames.count) failed")
            }
            importNotice = parts.joined(separator: ", ") + "."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleEmailReceiptSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            let urls = try result.get()
            let summary = EmailReceiptImportService.importEMLFiles(at: urls, context: modelContext)
            try modelContext.save()

            var parts = ["Imported \(summary.importedCount) email receipts"]
            if summary.duplicateCount > 0 {
                parts.append("\(summary.duplicateCount) duplicates")
            }
            if summary.skippedAttachmentCount > 0 {
                parts.append("\(summary.skippedAttachmentCount) skipped attachments")
            }
            if !summary.failedFilenames.isEmpty {
                parts.append(failedEmailImportSummary(summary.failedFilenames))
            }
            importNotice = parts.joined(separator: ", ") + "."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func failedEmailImportSummary(_ filenames: [String]) -> String {
        let visibleFilenames = filenames.prefix(3).joined(separator: ", ")
        let label = filenames.count == 1 ? "failed message" : "failed messages"
        if filenames.count > 3 {
            return "\(filenames.count) \(label): \(visibleFilenames), and \(filenames.count - 3) more"
        }
        return "\(filenames.count) \(label): \(visibleFilenames)"
    }

    private func receiptMetadataSummary(for attachment: ReceiptAttachment) -> String? {
        var parts: [String] = []
        if let merchant = attachment.extractedMerchant {
            parts.append(merchant)
        }
        if let date = attachment.extractedDate {
            parts.append(date.mediumFormatted)
        }
        if let amount = attachment.extractedAmount {
            parts.append(amount.currencyFormatted)
        }
        if let subject = attachment.sourceMessageSubject {
            parts.append("Email: \(subject)")
        } else if let filename = attachment.sourceMessageFilename {
            parts.append("Email: \(filename)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct CSVImportProfileFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: CSVImportProfile

    @State private var name: String
    @State private var importMode: ExpenseImportMode
    @State private var dateHeader: String
    @State private var merchantHeader: String
    @State private var amountHeader: String
    @State private var debitHeader: String
    @State private var creditHeader: String
    @State private var categoryHeader: String
    @State private var accountHeader: String
    @State private var paymentMethodHeader: String
    @State private var noteHeader: String
    @State private var receiptHeader: String
    @State private var transactionTypeHeader: String
    @State private var directionHeader: String
    @State private var currencyHeader: String

    init(profile: CSVImportProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _importMode = State(initialValue: profile.importMode)
        _dateHeader = State(initialValue: profile.dateHeader)
        _merchantHeader = State(initialValue: profile.merchantHeader)
        _amountHeader = State(initialValue: profile.amountHeader)
        _debitHeader = State(initialValue: profile.debitHeader)
        _creditHeader = State(initialValue: profile.creditHeader)
        _categoryHeader = State(initialValue: profile.categoryHeader)
        _accountHeader = State(initialValue: profile.accountHeader)
        _paymentMethodHeader = State(initialValue: profile.paymentMethodHeader)
        _noteHeader = State(initialValue: profile.noteHeader)
        _receiptHeader = State(initialValue: profile.receiptHeader)
        _transactionTypeHeader = State(initialValue: profile.transactionTypeHeader)
        _directionHeader = State(initialValue: profile.directionHeader)
        _currencyHeader = State(initialValue: profile.currencyHeader)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("CSV Profile", subtitle: "Saved locally for recurring imports.")

            Form {
                TextField("Name", text: $name)
                Picker("Import Mode", selection: $importMode) {
                    ForEach(ExpenseImportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Date Header", text: $dateHeader)
                TextField("Merchant Header", text: $merchantHeader)
                TextField("Amount Header", text: $amountHeader)
                TextField("Debit Header", text: $debitHeader)
                TextField("Credit Header", text: $creditHeader)
                TextField("Category Header", text: $categoryHeader)
                TextField("Account Header", text: $accountHeader)
                TextField("Payment Method Header", text: $paymentMethodHeader)
                TextField("Note Header", text: $noteHeader)
                TextField("Receipt Header", text: $receiptHeader)
                TextField("Transaction Type Header", text: $transactionTypeHeader)
                TextField("Direction Header", text: $directionHeader)
                TextField("Currency Header", text: $currencyHeader)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedName.isEmpty)
            }
        }
        .padding(24)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        profile.name = normalizedName
        profile.importMode = importMode
        profile.apply(mapping: CSVColumnMapping(
            dateHeader: dateHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            merchantHeader: merchantHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            amountHeader: amountHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            debitHeader: debitHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            creditHeader: creditHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryHeader: categoryHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            accountHeader: accountHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            paymentMethodHeader: paymentMethodHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            noteHeader: noteHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            receiptHeader: receiptHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            transactionTypeHeader: transactionTypeHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            directionHeader: directionHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyHeader: currencyHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        try? modelContext.save()
        dismiss()
    }
}

private struct ReceiptReconciliationPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]

    let receipts: [ReceiptAttachment]
    let expenses: [Expense]

    @State private var selectedReceiptID: UUID?
    @State private var selectedExpenseID: UUID?
    @State private var actionNotice: String?

    private var unmatchedReceipts: [ReceiptAttachment] {
        receipts.filter { $0.expenseID == nil }
    }

    private var missingReceiptExpenses: [Expense] {
        ExpenseLedger.expensesMissingReceipts(in: expenses)
    }

    private var selectedReceipt: ReceiptAttachment? {
        guard let selectedReceiptID else { return nil }
        return unmatchedReceipts.first { $0.id == selectedReceiptID }
    }

    private var suggestions: [ReceiptMatchSuggestion] {
        ReceiptMatcher.suggestions(receipts: receipts, expenses: expenses)
    }

    private var receiptsReadyForDrafts: [ReceiptAttachment] {
        let suggestedReceiptIDs = Set(suggestions.map { $0.receipt.id })
        return unmatchedReceipts.filter { receipt in
            receipt.extractedAmount != nil && !suggestedReceiptIDs.contains(receipt.id)
        }
    }

    var body: some View {
        Group {
            if !unmatchedReceipts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Receipt Matching")
                        .font(.headline)

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Suggested Matches")
                                .font(.subheadline.weight(.semibold))
                            ForEach(suggestions.prefix(5)) { suggestion in
                                HStack(spacing: Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.receipt.extractedMerchant ?? suggestion.receipt.originalFilename)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        Text("to \(suggestion.expense.merchant) · \(suggestion.expense.amount.currencyFormatted)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(suggestion.score)%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(suggestion.reasons.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 140, alignment: .trailing)
                                    Button {
                                        openReceiptFile(suggestion.receipt)
                                    } label: {
                                        Label("Open Receipt", systemImage: "arrow.up.forward.square")
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help(receiptFileExists(suggestion.receipt) ? "Open receipt" : "Receipt file is missing")
                                    .disabled(!receiptFileExists(suggestion.receipt))
                                    Button {
                                        attach(suggestion)
                                    } label: {
                                        Label("Attach", systemImage: "link")
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    }

                    if !receiptsReadyForDrafts.isEmpty {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Receipt Drafts")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(receiptsReadyForDrafts.count) receipt-only items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                createDraftExpensesFromReceipts()
                            } label: {
                                Label("Create Drafts", systemImage: "tray.and.arrow.down")
                            }
                        }
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    }

                    HStack(spacing: Spacing.md) {
                        Picker("Receipt", selection: $selectedReceiptID) {
                            Text("Choose Receipt").tag(nil as UUID?)
                            ForEach(unmatchedReceipts) { receipt in
                                Text(receiptPickerTitle(for: receipt)).tag(receipt.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)

                        if !missingReceiptExpenses.isEmpty {
                            Picker("Expense", selection: $selectedExpenseID) {
                                Text("Choose Expense").tag(nil as UUID?)
                                ForEach(missingReceiptExpenses) { expense in
                                    Text("\(expense.merchant) · \(expense.amount.currencyFormatted)")
                                        .tag(expense.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 320)

                            Button {
                                attachSelection()
                            } label: {
                                Label("Attach", systemImage: "link")
                            }
                            .disabled(selectedReceiptID == nil || selectedExpenseID == nil)
                        }

                        Button {
                            createExpenseFromSelection()
                        } label: {
                            Label("Create Expense", systemImage: "plus")
                        }
                        .disabled(selectedReceipt?.extractedAmount == nil)
                    }

                    if let actionNotice {
                        Text(actionNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(unmatchedReceipts.count) receipts are waiting in the local vault. \(missingReceiptExpenses.count) expenses are missing receipts.")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    private func attachSelection() {
        guard let selectedReceiptID,
              let selectedExpenseID,
              let receipt = unmatchedReceipts.first(where: { $0.id == selectedReceiptID }),
              let expense = missingReceiptExpenses.first(where: { $0.id == selectedExpenseID }) else {
            return
        }

        ReceiptVault.link(attachment: receipt, to: expense)
        try? modelContext.save()
        actionNotice = nil
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func attach(_ suggestion: ReceiptMatchSuggestion) {
        ReceiptVault.link(attachment: suggestion.receipt, to: suggestion.expense)
        try? modelContext.save()
        actionNotice = nil
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func createExpenseFromSelection() {
        guard let receipt = selectedReceipt else { return }
        guard ReceiptVault.createDraftExpense(from: receipt, context: modelContext, vendorRules: vendorRules) != nil else { return }
        try? modelContext.save()
        actionNotice = "Created 1 draft expense."
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func createDraftExpensesFromReceipts() {
        let createdCount = ReceiptVault.createDraftExpenses(
            from: receiptsReadyForDrafts,
            context: modelContext,
            vendorRules: vendorRules
        )
        guard createdCount > 0 else { return }
        try? modelContext.save()
        actionNotice = "Created \(createdCount) draft expenses."
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func receiptPickerTitle(for receipt: ReceiptAttachment) -> String {
        var title = receipt.extractedMerchant ?? receipt.originalFilename
        if let amount = receipt.extractedAmount {
            title += " · \(amount.currencyFormatted)"
        }
        return title
    }
}

private enum ReportExportScope: String, CaseIterable, Identifiable {
    case all
    case billableOrReimbursable
    case billable
    case reimbursable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Expenses"
        case .billableOrReimbursable: "Billable/Reimbursable"
        case .billable: "Billable"
        case .reimbursable: "Reimbursable"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .all: "all"
        case .billableOrReimbursable: "follow-up-expenses"
        case .billable: "billable-expenses"
        case .reimbursable: "reimbursable-expenses"
        }
    }

    @MainActor
    func expenses(in expenses: [Expense]) -> [Expense] {
        switch self {
        case .all:
            expenses
        case .billableOrReimbursable:
            ExpenseLedger.outstandingFollowUpExpenses(in: expenses)
        case .billable:
            ExpenseLedger.outstandingBillableExpenses(in: expenses)
        case .reimbursable:
            ExpenseLedger.outstandingReimbursableExpenses(in: expenses)
        }
    }
}

private enum ReportExportKind: String, CaseIterable, Identifiable {
    case rawExpenses
    case taxBucketSummary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rawExpenses: "Raw Expenses"
        case .taxBucketSummary: "Tax Summary"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .rawExpenses: "expenses"
        case .taxBucketSummary: "tax-bucket-summary"
        }
    }
}

enum ReportDateRange: String, CaseIterable, Identifiable {
    case taxYear
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taxYear: "Tax Year"
        case .custom: "Custom Dates"
        }
    }
}

struct ReportsView: View {
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    @Binding var taxYear: Int
    @Binding var dateRange: ReportDateRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var exportKind = ReportExportKind.rawExpenses
    @State private var exportScope = ReportExportScope.all
    @State private var isExportingCSV = false
    @State private var lastCSVExportURL: URL?
    @State private var lastAuditPackageURL: URL?
    @State private var exportNotice: String?
    @State private var auditPackageNotice: String?
    @State private var exportError: String?

    init(
        taxYear: Binding<Int>,
        dateRange: Binding<ReportDateRange>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>
    ) {
        _taxYear = taxYear
        _dateRange = dateRange
        _customStartDate = customStartDate
        _customEndDate = customEndDate
    }

    private var selectedInterval: DateInterval {
        switch dateRange {
        case .taxYear:
            return ExpenseLedger.yearInterval(taxYear)
        case .custom:
            let range = normalizedCustomRange
            return DateInterval(
                start: range.start,
                end: Calendar.current.date(byAdding: .day, value: 1, to: range.end) ?? range.end.addingTimeInterval(86_400)
            )
        }
    }

    private var normalizedCustomRange: (start: Date, end: Date) {
        let orderedStart = min(customStartDate, customEndDate)
        let orderedEnd = max(customStartDate, customEndDate)
        return (
            start: Calendar.current.startOfDay(for: orderedStart),
            end: Calendar.current.startOfDay(for: orderedEnd)
        )
    }

    private var expensesForRange: [Expense] {
        let interval = selectedInterval
        return expenses.filter { interval.contains($0.date) && $0.status != .ignored }
    }

    private var expensesForExport: [Expense] {
        exportScope.expenses(in: expensesForRange)
    }

    private var exportCSV: String {
        switch exportKind {
        case .rawExpenses:
            ExpenseLedger.exportCSV(expenses: expensesForExport, categories: categories)
        case .taxBucketSummary:
            ExpenseLedger.exportTaxBucketSummaryCSV(expenses: expensesForExport, categories: categories)
        }
    }

    private var exportFilename: String {
        "remnant-\(rangeFilenameSuffix)-\(exportScope.filenameSuffix)-\(exportKind.filenameSuffix).csv"
    }

    private var auditPackageFilename: String {
        "remnant-\(rangeFilenameSuffix)-\(exportScope.filenameSuffix)-audit.\(AuditPackageService.packageExtension)"
    }

    private var rangeFilenameSuffix: String {
        switch dateRange {
        case .taxYear:
            return "\(taxYear)"
        case .custom:
            let range = normalizedCustomRange
            return "\(filenameDateFormatter.string(from: range.start))-\(filenameDateFormatter.string(from: range.end))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("Reports", subtitle: "Exportable summaries for accountant and tax review.")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(ReportDateRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    Picker("Tax Year", selection: $taxYear) {
                        ForEach((2023...Calendar.current.component(.year, from: Date()) + 1), id: \.self) { year in
                            Text("\(year)").tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .disabled(dateRange != .taxYear)

                    if dateRange == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                            .frame(width: 180)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                            .frame(width: 180)
                    }
                }

                HStack(spacing: Spacing.md) {
                    Picker("Export", selection: $exportKind) {
                        ForEach(ReportExportKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    Picker("Export Scope", selection: $exportScope) {
                        ForEach(ReportExportScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
            }

            HStack(spacing: Spacing.lg) {
                metric("Range Total", ExpenseLedger.totalSpent(in: expenses, for: selectedInterval).currencyFormatted)
                metric("Export Rows", "\(expensesForExport.count)")
            }

            HStack {
                Button {
                    isExportingCSV = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(expensesForExport.isEmpty)

                Button {
                    exportAuditPackage()
                } label: {
                    Label("Export Audit Package", systemImage: "archivebox")
                }
                .disabled(expensesForExport.isEmpty)

                if let lastCSVExportURL {
                    Button {
                        revealFile(lastCSVExportURL)
                    } label: {
                        Label("Show CSV", systemImage: "folder")
                    }
                }

                if let lastAuditPackageURL {
                    Button {
                        revealFile(lastAuditPackageURL)
                    } label: {
                        Label("Show Audit Package", systemImage: "folder")
                    }
                }
            }

            HStack {
                if let exportNotice {
                    Text(exportNotice)
                        .foregroundStyle(.secondary)
                }

                if let auditPackageNotice {
                    Text(auditPackageNotice)
                        .foregroundStyle(.secondary)
                }

                if let exportError {
                    Text(exportError)
                        .foregroundStyle(.red)
                }
            }

            Text("CSV Preview")
                .font(.headline)
            Text(exportCSV)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .padding(24)
        .fileExporter(
            isPresented: $isExportingCSV,
            document: ExpenseCSVDocument(csv: exportCSV),
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
                exportNotice = nil
            } else {
                if case .success(let url) = result {
                    lastCSVExportURL = url
                    exportNotice = "Exported \(url.lastPathComponent)."
                }
                exportError = nil
            }
        }
    }

    private var filenameDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func exportAuditPackage() {
        exportError = nil
        auditPackageNotice = nil
        exportNotice = nil

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = auditPackageFilename

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                do {
                    let summary = try AuditPackageService.createPackage(
                        at: url,
                        expenses: expensesForExport,
                        categories: categories,
                        attachments: receiptAttachments,
                        allowOverwrite: true
                    )
                    var parts = [
                        "Exported \(summary.expenseCount) expenses",
                        "\(summary.copiedReceiptCount) receipts"
                    ]
                    if summary.missingReceiptCount > 0 {
                        parts.append("\(summary.missingReceiptCount) missing receipts")
                    }
                    auditPackageNotice = parts.joined(separator: ", ") + "."
                    lastAuditPackageURL = url
                    exportError = nil
                } catch {
                    exportError = error.localizedDescription
                    auditPackageNotice = nil
                }
            }
        }
    }
}

struct ExpenseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]
    @Query(sort: [SortDescriptor(\BusinessDimension.sortOrder), SortDescriptor(\BusinessDimension.name)])
    private var dimensions: [BusinessDimension]

    @AppStorage("remnant.automaticBackup.enabled")
    private var isAutomaticBackupEnabled = false
    @AppStorage("remnant.automaticBackup.lastRun")
    private var automaticBackupLastRun = 0.0

    @State private var merchantPattern = ""
    @State private var selectedCategory = "Uncategorized"
    @State private var newDimensionKind = BusinessDimensionKind.account
    @State private var newDimensionName = ""
    @State private var newDimensionNote = ""
    @State private var backupNotice: String?
    @State private var backupError: String?
    @State private var lastBackupURL: URL?
    @State private var integrityReport: RemnantBackupIntegrityReport?
    @State private var restoreCandidateURL: URL?
    @State private var isConfirmingRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header("Settings", subtitle: "Local rules and privacy controls for expense tracking.")

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Categories")
                        .font(.headline)

                    if categories.isEmpty {
                        Text("No categories yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(categories) { category in
                            HStack(spacing: Spacing.md) {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.body.weight(.medium))
                                    Text(category.taxBucket)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Reporting Dimensions")
                        .font(.headline)

                    HStack(spacing: Spacing.md) {
                        Picker("Type", selection: $newDimensionKind) {
                            ForEach(BusinessDimensionKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        TextField("Name", text: $newDimensionName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)

                        TextField("Note", text: $newDimensionNote)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)

                        Button {
                            addDimension()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .disabled(normalizedDimensionName.isEmpty)
                    }

                    if dimensions.isEmpty {
                        Text("No reporting dimensions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(BusinessDimensionKind.allCases) { kind in
                                let rows = dimensionsForKind(kind)
                                if !rows.isEmpty {
                                    Section(kind.pluralLabel) {
                                        ForEach(rows) { dimension in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(dimension.name)
                                                        .font(.body.weight(.medium))
                                                    if !dimension.note.isEmpty {
                                                        Text(dimension.note)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer()
                                                Button(role: .destructive) {
                                                    deleteDimension(dimension)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                                .labelStyle(.iconOnly)
                                                .buttonStyle(.borderless)
                                                .help("Delete dimension")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 190)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Vendor Rules")
                        .font(.headline)
                    Text("Use rules to categorize imported expenses and receipt-created drafts when the source file has no category.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.md) {
                        TextField("Merchant contains", text: $merchantPattern)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)

                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categoryNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190)

                        Button {
                            addRule()
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                        }
                        .disabled(normalizedPattern.isEmpty)
                    }

                    if vendorRules.isEmpty {
                        Text("No vendor rules yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(vendorRules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.merchantPattern)
                                        .font(.body.weight(.medium))
                                    Text(rule.defaultCategoryName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    deleteRule(rule)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Delete rule")
                            }
                        }
                        .frame(minHeight: 120)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                backupSection

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Privacy")
                        .font(.headline)

                    Label("No analytics or tracking SDKs", systemImage: "eye.slash")
                    Label("No bank linking or FinanceKit access", systemImage: "building.columns")
                    Label("No StoreKit subscription gates", systemImage: "creditcard.trianglebadge.exclamationmark")
                    Label("Receipts stay in the local vault until you export them", systemImage: "doc.badge.lock")

                    Text("Exports are explicit user actions. Import parsing, duplicate checks, receipt extraction, and vendor rules all run locally.")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .padding(24)
            .onAppear {
                if !categoryNames.contains(selectedCategory) {
                    selectedCategory = categoryNames.first ?? "Uncategorized"
                }
            }
            .confirmationDialog(
                "Restore Backup",
                isPresented: $isConfirmingRestore,
                presenting: restoreCandidateURL
            ) { url in
                Button("Stage Restore", role: .destructive) {
                    stageRestore(from: url)
                }
            } message: { url in
                Text("The selected backup will replace current local data the next time Remnant opens: \(url.lastPathComponent)")
            }
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Backup & Integrity")
                .font(.headline)

            HStack(spacing: Spacing.md) {
                Button {
                    checkIntegrity()
                } label: {
                    Label("Check Integrity", systemImage: "checkmark.shield")
                }

                Button {
                    createBackup()
                } label: {
                    Label("Create Backup", systemImage: "archivebox")
                }

                Button {
                    testAutomaticBackup()
                } label: {
                    Label("Test Auto Backup", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    chooseRestoreBackup()
                } label: {
                    Label("Restore Backup", systemImage: "arrow.counterclockwise")
                }

                if let lastBackupURL {
                    Button {
                        revealFile(lastBackupURL)
                    } label: {
                        Label("Show Backup", systemImage: "folder")
                    }
                }
            }

            Toggle("Automatic daily backup", isOn: $isAutomaticBackupEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                Text("Automatic backups are local packages in Remnant's Application Support folder.")
                    .foregroundStyle(.secondary)
                if automaticBackupLastRun > 0 {
                    Text("Last auto backup: \(Date(timeIntervalSince1970: automaticBackupLastRun).mediumFormatted)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let integrityReport {
                HStack(spacing: Spacing.lg) {
                    metric("Expenses", "\(integrityReport.expenseCount)")
                    metric("Receipts", "\(integrityReport.attachmentCount)")
                    metric("Issues", "\(integrityReport.issues.count)")
                }

                if integrityReport.issues.isEmpty {
                    Label("Integrity check passed", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(integrityReport.issues.prefix(5)) { issue in
                            Label(issue.detail, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if integrityReport.issues.count > 5 {
                            Text("\(integrityReport.issues.count - 5) more issue(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let backupNotice {
                Text(backupNotice)
                    .foregroundStyle(.secondary)
            }
            if let backupError {
                Text(backupError)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    private var normalizedPattern: String {
        merchantPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDimensionName: String {
        newDimensionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkIntegrity() {
        do {
            integrityReport = try RemnantBackupService.integrityReport(context: modelContext)
            backupError = nil
            backupNotice = nil
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func testAutomaticBackup() {
        do {
            let result = try RemnantBackupService.createAutomaticBackup(context: modelContext)
            integrityReport = result.report
            backupNotice = "Auto backup created at \(result.backupURL.lastPathComponent)."
            backupError = nil
            lastBackupURL = result.backupURL
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func createBackup() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "remnant-backup-\(backupDateFormatter.string(from: Date())).\(RemnantBackupService.backupExtension)"
        panel.title = "Create Remnant Backup"

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        do {
            let report = try RemnantBackupService.createBackup(
                at: url,
                context: modelContext,
                allowOverwrite: true
            )
            integrityReport = report
            backupNotice = "Backup created at \(url.lastPathComponent)."
            backupError = nil
            lastBackupURL = url
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func chooseRestoreBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Remnant Backup"

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        restoreCandidateURL = url
        isConfirmingRestore = true
    }

    private func stageRestore(from url: URL) {
        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let report = try RemnantBackupService.stageRestore(from: url, allowOverwrite: true)
            integrityReport = report
            backupNotice = "Restore staged. Restart Remnant to load \(url.lastPathComponent)."
            backupError = nil
        } catch {
            backupError = error.localizedDescription
        }
    }

    private var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }

    private func dimensionsForKind(_ kind: BusinessDimensionKind) -> [BusinessDimension] {
        dimensions.filter { $0.kind == kind && !$0.isArchived }
    }

    private func addDimension() {
        guard !normalizedDimensionName.isEmpty else { return }
        let existing = dimensions.first {
            $0.kind == newDimensionKind
                && $0.name.compare(normalizedDimensionName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if let existing {
            existing.note = newDimensionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.isArchived = false
        } else {
            let nextSortOrder = ((dimensions.map(\.sortOrder).max() ?? -1) + 1)
            modelContext.insert(
                BusinessDimension(
                    kind: newDimensionKind,
                    name: normalizedDimensionName,
                    note: newDimensionNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    sortOrder: nextSortOrder
                )
            )
        }

        newDimensionName = ""
        newDimensionNote = ""
        try? modelContext.save()
    }

    private func deleteDimension(_ dimension: BusinessDimension) {
        modelContext.delete(dimension)
        try? modelContext.save()
    }

    private func addRule() {
        guard !normalizedPattern.isEmpty else { return }
        let category = selectedCategory.isEmpty ? "Uncategorized" : selectedCategory
        let taxBucket = categories.first { $0.name == category }?.taxBucket ?? category
        let existingRule = vendorRules.first {
            $0.merchantPattern.compare(normalizedPattern, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if let existingRule {
            existingRule.defaultCategoryName = category
            existingRule.defaultTaxBucket = taxBucket
        } else {
            modelContext.insert(
                VendorRule(
                    merchantPattern: normalizedPattern,
                    defaultCategoryName: category,
                    defaultTaxBucket: taxBucket
                )
            )
        }

        merchantPattern = ""
        try? modelContext.save()
    }

    private func deleteRule(_ rule: VendorRule) {
        modelContext.delete(rule)
        try? modelContext.save()
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    let receipt: ReceiptAttachment?
    let onEdit: () -> Void
    let onOpenReceipt: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.merchant)
                    .font(.body.weight(.medium))
                Text("\(expense.date.mediumFormatted) · \(expense.categoryName ?? "Uncategorized")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.status.label)
                .font(.caption)
                .foregroundStyle(expense.status == .reviewed ? .green : .secondary)
            if expense.isBillable {
                Image(systemName: "briefcase")
                    .foregroundStyle(.secondary)
                    .help("Billable")
            }
            if ExpenseLedger.isReimbursable(expense) {
                Image(systemName: "arrow.uturn.left.circle")
                    .foregroundStyle(.secondary)
                    .help("Reimbursable")
            }
            if isMissingReceipt {
                Image(systemName: "doc.badge.clock")
                    .foregroundStyle(.secondary)
                    .help("Missing receipt")
            }
            Text(expense.amount.currencyFormatted)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
            if let onOpenReceipt {
                Button(action: onOpenReceipt) {
                    Label("Open Receipt", systemImage: "arrow.up.forward.square")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(receiptFileExists(receipt) ? "Open receipt" : "Receipt file is missing")
                .disabled(!receiptFileExists(receipt))
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Edit expense")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit()
        }
    }

    private var isMissingReceipt: Bool {
        expense.receiptFilename == nil
            && expense.receiptAttachmentID == nil
            && expense.receiptContentHash == nil
    }
}

private extension ExpenseStatus {
    var label: String {
        switch self {
        case .draft: "Draft"
        case .reviewed: "Reviewed"
        case .reimbursable: "Reimbursable"
        case .ignored: "Ignored"
        }
    }
}

private extension ExpenseSource {
    var label: String {
        switch self {
        case .manual: "Manual"
        case .csvImport: "CSV Import"
        case .waveImport: "Wave Import"
        case .receiptDraft: "Receipt Draft"
        }
    }
}

private extension ExpenseReviewIssue {
    var label: String {
        switch self {
        case .importedDraft: "Imported Draft"
        case .missingReceipt: "Missing Receipt"
        case .uncategorized: "Uncategorized"
        case .duplicateCandidate: "Duplicate"
        case .manualReview: "Draft Review"
        }
    }

    var systemImage: String {
        switch self {
        case .importedDraft: "tray.and.arrow.down"
        case .missingReceipt: "doc.badge.clock"
        case .uncategorized: "questionmark.folder"
        case .duplicateCandidate: "doc.on.doc"
        case .manualReview: "checklist"
        }
    }
}

private func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title)
            .font(.largeTitle.weight(.semibold))
        Text(subtitle)
            .foregroundStyle(.secondary)
    }
}

private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.title2.monospacedDigit().weight(.semibold))
    }
    .padding(14)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
}

private func emptyState(_ title: String, _ subtitle: String) -> some View {
    ContentUnavailableView(title, systemImage: "tray", description: Text(subtitle))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func receiptFileURL(_ attachment: ReceiptAttachment?) -> URL? {
    guard let attachment else { return nil }
    let url = URL(fileURLWithPath: attachment.localPath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

private func receiptFileExists(_ attachment: ReceiptAttachment?) -> Bool {
    receiptFileURL(attachment) != nil
}

private func openReceiptFile(_ attachment: ReceiptAttachment) {
    guard let url = receiptFileURL(attachment) else { return }
    NSWorkspace.shared.open(url)
}

private func revealReceiptFile(_ attachment: ReceiptAttachment) {
    guard let url = receiptFileURL(attachment) else { return }
    revealFile(url)
}

private func revealFile(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

private func normalizedDisplayValue(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}
