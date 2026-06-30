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

struct ActionMetric: View {
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
