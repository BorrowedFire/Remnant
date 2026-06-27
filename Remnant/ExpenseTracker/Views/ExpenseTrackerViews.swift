import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExpenseDashboardView: View {
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    private var monthInterval: DateInterval {
        ExpenseLedger.monthInterval(containing: Date())
    }

    private var activeExpenses: [Expense] {
        expenses.filter { $0.status != .ignored }
    }

    private var draftExpenses: [Expense] {
        activeExpenses.filter { $0.status == .draft }
    }

    private var unmatchedReceiptCount: Int {
        receiptAttachments.filter { $0.expenseID == nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                dashboardHeader

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.md)], spacing: Spacing.md) {
                    DashboardMetric(
                        title: "This Month",
                        value: ExpenseLedger.totalSpent(in: activeExpenses, for: monthInterval).currencyFormatted,
                        subtitle: "Local expenses",
                        systemImage: "calendar",
                        tint: .blue
                    )
                    DashboardMetric(
                        title: "Need Review",
                        value: "\(draftExpenses.count)",
                        subtitle: "Draft entries",
                        systemImage: "checklist",
                        tint: .orange
                    )
                    DashboardMetric(
                        title: "Missing Receipts",
                        value: "\(ExpenseLedger.expensesMissingReceipts(in: activeExpenses).count)",
                        subtitle: "Attach before tax review",
                        systemImage: "doc.badge.clock",
                        tint: .red
                    )
                    DashboardMetric(
                        title: "Receipt Inbox",
                        value: "\(unmatchedReceiptCount)",
                        subtitle: "Waiting to match",
                        systemImage: "tray.full",
                        tint: .green
                    )
                }

                HStack(alignment: .top, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        DashboardPanel(title: "Review Queue") {
                            DashboardQueueRow(
                                title: "Draft expenses",
                                value: "\(draftExpenses.count)",
                                systemImage: "pencil.and.list.clipboard"
                            )
                            DashboardQueueRow(
                                title: "Missing receipts",
                                value: "\(ExpenseLedger.expensesMissingReceipts(in: activeExpenses).count)",
                                systemImage: "doc.badge.clock"
                            )
                            DashboardQueueRow(
                                title: "Uncategorized",
                                value: "\(ExpenseLedger.uncategorizedExpenses(in: activeExpenses).count)",
                                systemImage: "questionmark.folder"
                            )
                        }

                        DashboardPanel(title: "Receipt Vault") {
                            if receiptAttachments.isEmpty {
                                Text("Downloaded receipts appear here after local import.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(receiptAttachments.prefix(4)) { receipt in
                                    ReceiptInboxRow(receipt: receipt)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        DashboardPanel(title: "Expense Flow", subtitle: "Last 12 months") {
                            MonthlySpendChart(points: monthlySpend)
                                .frame(height: 240)
                        }

                        DashboardPanel(title: "Category Spend", subtitle: "Current tax year") {
                            if categorySpend.isEmpty {
                                Text("Categorized expenses will appear after import or manual entry.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(categorySpend.prefix(6)) { item in
                                    CategorySpendRow(item: item, maxAmount: categorySpend.first?.amount ?? 0)
                                }
                            }
                        }

                        DashboardPanel(title: "Recent Expenses") {
                            if activeExpenses.isEmpty {
                                Text("Add an expense or import a Wave CSV to start replacing Wave.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(activeExpenses.prefix(6)) { expense in
                                    ExpenseSummaryRow(expense: expense)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            header("Dashboard", subtitle: "Expense tracking for your business. Data stays on this Mac.")
            Spacer()
            Text("Expense-only")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: CornerRadius.small))
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
                amount: total
            )
        }
    }

    private var categorySpend: [CategorySpendItem] {
        let interval = ExpenseLedger.yearInterval(Calendar.current.component(.year, from: Date()))
        let grouped = Dictionary(grouping: activeExpenses.filter { interval.contains($0.date) }) { expense in
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(.quaternary)
        }
    }
}

private struct DashboardPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
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
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}

private struct MonthlySpendPoint: Identifiable {
    let id: String
    let label: String
    let amount: Decimal
}

private struct MonthlySpendChart: View {
    let points: [MonthlySpendPoint]

    private var maxAmount: Decimal {
        points.map(\.amount).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.12))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.green)
                                    .frame(height: max(4, proxy.size.height * heightRatio(for: point.amount)))
                            }
                            .frame(maxWidth: .infinity)

                            Text(point.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: Spacing.md) {
                Label("Expense", systemImage: "square.fill")
                    .foregroundStyle(.green)
                Text("Highest month \(maxAmount.currencyFormatted)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func heightRatio(for amount: Decimal) -> CGFloat {
        let maxDouble = NSDecimalNumber(decimal: maxAmount).doubleValue
        guard maxDouble > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount).doubleValue / maxDouble)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.name)
                Spacer()
                Text(item.amount.currencyFormatted)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: max(4, proxy.size.width * widthRatio))
                    }
            }
            .frame(height: 6)
        }
        .font(.caption)
    }

    private var widthRatio: CGFloat {
        let maxDouble = NSDecimalNumber(decimal: maxAmount).doubleValue
        guard maxDouble > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: item.amount).doubleValue / maxDouble)
    }
}

private struct ReceiptInboxRow: View {
    let receipt: ReceiptAttachment

    var body: some View {
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
        }
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

    var body: some View {
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
        }
    }
}

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]

    @State private var searchText = ""
    @State private var reviewFilter = ExpenseReviewFilter.needsReview
    @State private var isShowingForm = false
    @State private var editingExpense: Expense?
    @State private var selectedExpenseIDs = Set<UUID>()

    private var filteredExpenses: [Expense] {
        let reviewFiltered = expenses.filter { reviewFilter.includes($0, allExpenses: expenses) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return reviewFiltered }
        return reviewFiltered.filter { expense in
            expense.merchant.lowercased().contains(query)
                || expense.note.lowercased().contains(query)
                || (expense.categoryName ?? "").lowercased().contains(query)
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

            if filteredExpenses.isEmpty {
                emptyState("No matching expenses", "Add a manual expense or import a local CSV.")
            } else {
                List(selection: $selectedExpenseIDs) {
                    ForEach(filteredExpenses) { expense in
                        ExpenseRow(expense: expense)
                            .tag(expense.id)
                            .onTapGesture(count: 2) {
                                editingExpense = expense
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") {
                                    editingExpense = expense
                                }
                                Divider()
                                statusButton("Mark Reviewed", systemImage: "checkmark.circle", status: .reviewed, expenses: [expense])
                                statusButton("Mark Reimbursable", systemImage: "arrow.uturn.left.circle", status: .reimbursable, expenses: [expense])
                                statusButton("Ignore", systemImage: "eye.slash", status: .ignored, expenses: [expense])
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
                        Button("Mark Reimbursable") {
                            updateSelectedStatus(.reimbursable)
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
                .frame(width: 520)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
                .frame(width: 560)
        }
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

    private func updateSelectedStatus(_ status: ExpenseStatus) {
        updateStatus(status, for: selectedExpenses)
        selectedExpenseIDs.removeAll()
    }

    private func updateStatus(_ status: ExpenseStatus, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        _ = ExpenseLedger.updateStatus(of: expenses, to: status)
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

private enum ExpenseReviewFilter: String, CaseIterable, Identifiable {
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

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]

    private let expense: Expense?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var categoryName = "Uncategorized"
    @State private var status = ExpenseStatus.draft
    @State private var paymentAccount = ""
    @State private var paymentMethod = ""
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
                TextField("Payment Account", text: $paymentAccount)
                TextField("Payment Method", text: $paymentMethod)
                HStack {
                    TextField("Receipt Reference", text: $receiptFilename)
                    Button {
                        isShowingReceiptImporter = true
                    } label: {
                        Label("Choose Receipt", systemImage: "doc.badge.plus")
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }

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
        target.paymentAccount = paymentAccount
        target.paymentMethod = paymentMethod
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

struct ImportCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ImportBatch.importedAt, order: .reverse)])
    private var importBatches: [ImportBatch]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]

    @State private var isShowingImporter = false
    @State private var isShowingReceiptImporter = false
    @State private var importMode = ExpenseImportMode.statementReview
    @State private var importSummary: ExpenseImportSummary?
    @State private var importError: String?
    @State private var importNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header("Imports", subtitle: "Bring in Wave exports and receipt review files without connecting to a service.")

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
                Text("CSV and receipt files are parsed locally. Nothing is uploaded.")
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
        .onChange(of: importMode) { _, _ in
            importSummary = nil
            importNotice = nil
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
            importSummary = try ExpenseImportService.previewCSV(
                at: url,
                existingExpenses: expenses,
                source: importMode.source,
                defaultStatus: importMode.defaultStatus,
                vendorRules: vendorRules
            )
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
            notes: ([importMode.detail] + summary.notes).joined(separator: " ")
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
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
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

struct ReportsView: View {
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]

    @State private var taxYear = Calendar.current.component(.year, from: Date())
    @State private var isExportingCSV = false
    @State private var exportError: String?

    private var expensesForYear: [Expense] {
        let interval = ExpenseLedger.yearInterval(taxYear)
        return expenses.filter { interval.contains($0.date) && $0.status != .ignored }
    }

    private var exportCSV: String {
        ExpenseLedger.exportCSV(expenses: expensesForYear, categories: categories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("Reports", subtitle: "Exportable summaries for accountant and tax review.")

            Picker("Tax Year", selection: $taxYear) {
                ForEach((2023...Calendar.current.component(.year, from: Date()) + 1), id: \.self) { year in
                    Text("\(year)").tag(year)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            metric("Year Total", ExpenseLedger.totalSpent(in: expenses, for: ExpenseLedger.yearInterval(taxYear)).currencyFormatted)

            HStack {
                Button {
                    isExportingCSV = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(expensesForYear.isEmpty)

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
            defaultFilename: "remnant-\(taxYear)-expenses.csv"
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            } else {
                exportError = nil
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

    @State private var merchantPattern = ""
    @State private var selectedCategory = "Uncategorized"

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
        }
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    private var normalizedPattern: String {
        merchantPattern.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if isMissingReceipt {
                Image(systemName: "doc.badge.clock")
                    .foregroundStyle(.secondary)
                    .help("Missing receipt")
            }
            Text(expense.amount.currencyFormatted)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.vertical, 4)
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
