import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum ExpenseListSheet: Identifiable {
    case newExpense
    case editExpense(Expense)

    var id: String {
        switch self {
        case .newExpense:
            "newExpense"
        case .editExpense(let expense):
            "editExpense-\(expense.id.uuidString)"
        }
    }
}

struct ExpenseListView: View {
    @EnvironmentObject private var appState: RemnantAppState
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
    @FocusState private var isSearchFocused: Bool
    @State private var followUpFilter = ExpenseFollowUpFilter.all
    @State private var dimensionFilterKind: BusinessDimensionKind?
    @State private var dimensionFilterValue = ""
    @State private var activeSheet: ExpenseListSheet?
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
                Table(filteredExpenses, selection: $selectedExpenseIDs) {
                    TableColumn("Merchant") { expense in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.merchant)
                                .font(.body.weight(.medium))
                            if !expense.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(expense.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    TableColumn("Date") { expense in
                        Text(expense.date.mediumFormatted)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Category") { expense in
                        Text(expense.categoryName ?? "Uncategorized")
                    }
                    TableColumn("Status") { expense in
                        Text(expense.status.label)
                            .foregroundStyle(expense.status == .reviewed ? .green : .secondary)
                    }
                    TableColumn("Payment") { expense in
                        Text(normalizedDisplayValue(expense.paymentMethod) ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Amount") { expense in
                        Text(expense.amount.currencyFormatted)
                            .monospacedDigit()
                    }
                    TableColumn("Receipt") { expense in
                        if let receipt = attachment(for: expense) {
                            Button {
                                openReceiptFile(receipt)
                            } label: {
                                Label("Open Receipt", systemImage: "arrow.up.forward.square")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help(receiptFileExists(receipt) ? "Open receipt" : "Receipt file is missing")
                            .disabled(!receiptFileExists(receipt))
                        } else {
                            Text("Missing")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    TableColumn("Actions") { expense in
                        Button {
                            activeSheet = .editExpense(expense)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit expense")
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { selection in
                    let selected = expenses(for: selection)
                    if selected.count == 1, let expense = selected.first {
                        Button("Edit", systemImage: "pencil") {
                            activeSheet = .editExpense(expense)
                        }
                        if let receipt = attachment(for: expense) {
                            Button("Open Receipt", systemImage: "arrow.up.forward.square") {
                                openReceiptFile(receipt)
                            }
                            Button("Show Receipt in Finder", systemImage: "folder") {
                                revealReceiptFile(receipt)
                            }
                        }
                    }
                    Divider()
                    Button("Copy Rows", systemImage: "doc.on.doc") {
                        copyExpenses(selected)
                    }
                    .disabled(selected.isEmpty)
                    statusButton("Mark Reviewed", systemImage: "checkmark.circle", status: .reviewed, expenses: selected)
                    statusButton("Ignore", systemImage: "eye.slash", status: .ignored, expenses: selected)
                    Divider()
                    followUpButton("Mark Billable", systemImage: "briefcase", expenses: selected) {
                        $0.isBillable = true
                    }
                    followUpButton("Mark Reimbursable", systemImage: "arrow.uturn.left.circle", expenses: selected) {
                        $0.isReimbursable = true
                    }
                } primaryAction: { selection in
                    guard let expense = expenses(for: selection).first else { return }
                    activeSheet = .editExpense(expense)
                }
            }
        }
        .padding(24)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search expenses")
        .searchFocused($isSearchFocused)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .newExpense
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
                            activeSheet = .editExpense(expense)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newExpense:
                ExpenseFormView()
                    .frame(width: 660)
            case .editExpense(let expense):
                ExpenseFormView(expense: expense)
                    .frame(width: 660)
            }
        }
        .focusedSceneValue(\.remnantActions, expenseFocusedActions)
        .onChange(of: appState.commandRequest) { _, request in
            guard let request else { return }
            guard appState.selectedSection == .expenses else { return }
            switch request.kind {
            case .focusSearch:
                isSearchFocused = true
            case .importFiles:
                appState.selectedSection = .imports
            case .exportReport:
                appState.selectedSection = .reports
            }
        }
    }

    private var expenseFocusedActions: RemnantFocusedActions {
        RemnantFocusedActions(
            newExpense: {
                activeSheet = .newExpense
            },
            editSelection: selectedExpenses.count == 1 ? {
                editSelectedExpense()
            } : nil,
            openSelection: selectedExpenses.count == 1 ? {
                editSelectedExpense()
            } : nil,
            openReceipt: selectedReceipt == nil ? nil : {
                openSelectedReceipt()
            },
            markReviewed: selectedExpenses.isEmpty ? nil : {
                updateSelectedStatus(.reviewed)
            },
            ignoreSelection: selectedExpenses.isEmpty ? nil : {
                updateSelectedStatus(.ignored)
            },
            copySelection: selectedExpenses.isEmpty ? nil : {
                copySelectedExpenses()
            },
            focusSearch: {
                isSearchFocused = true
            },
            importFiles: {
                appState.selectedSection = .imports
            },
            exportReport: {
                appState.selectedSection = .reports
            }
        )
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

    private func expenses(for ids: Set<UUID>) -> [Expense] {
        filteredExpenses.filter { ids.contains($0.id) }
    }

    private var selectedReceipt: ReceiptAttachment? {
        guard selectedExpenses.count == 1, let expense = selectedExpenses.first else { return nil }
        return attachment(for: expense)
    }

    private func editSelectedExpense() {
        guard selectedExpenses.count == 1, let expense = selectedExpenses.first else { return }
        activeSheet = .editExpense(expense)
    }

    private func openSelectedReceipt() {
        guard let selectedReceipt else { return }
        openReceiptFile(selectedReceipt)
    }

    private func copySelectedExpenses() {
        copyExpenses(selectedExpenses)
    }

    private func copyExpenses(_ expenses: [Expense]) {
        let rows = expenses
            .sorted { $0.date > $1.date }
            .map { expense in
                [
                    expense.date.mediumFormatted,
                    expense.merchant,
                    expense.categoryName ?? "Uncategorized",
                    expense.status.label,
                    expense.amount.currencyFormatted,
                    expense.paymentMethod,
                    expense.projectName
                ]
                .map { $0.replacingOccurrences(of: "\t", with: " ") }
                .joined(separator: "\t")
            }
        guard !rows.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "Date\tMerchant\tCategory\tStatus\tAmount\tPayment Method\tProject\n" + rows.joined(separator: "\n"),
            forType: .string
        )
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
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func updateFollowUp(for expenses: [Expense], update: (Expense) -> Void) {
        guard !expenses.isEmpty else { return }
        let now = Date()
        for expense in expenses {
            update(expense)
            expense.updatedAt = now
        }
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func ignoreExpense(_ expense: Expense) {
        _ = ExpenseLedger.updateStatus(of: [expense], to: .ignored)
        try? RemnantStore.saveLedgerMutation(context: modelContext)
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
