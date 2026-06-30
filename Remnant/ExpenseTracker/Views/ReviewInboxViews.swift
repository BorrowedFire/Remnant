import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExpenseReviewInboxView: View {
    @EnvironmentObject private var appState: RemnantAppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\AgentProposal.createdAt, order: .reverse)])
    private var proposals: [AgentProposal]

    @Binding var issueFilter: ExpenseReviewInboxFilter
    @State private var selectedCategory = "Uncategorized"
    @State private var selectedExpenseIDs = Set<UUID>()
    @State private var editingExpense: Expense?
    @State private var selectedProposal: AgentProposal?
    @State private var proposalNotice: String?
    @State private var proposalError: String?
    private let proposalSyncTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(issueFilter: Binding<ExpenseReviewInboxFilter>) {
        _issueFilter = issueFilter
    }

    private var inboxExpenses: [Expense] {
        ExpenseLedger.reviewInboxExpenses(in: expenses)
    }

    private var filteredExpenses: [Expense] {
        issueFilter.expenses(in: inboxExpenses, allExpenses: expenses)
    }

    private var pendingProposals: [AgentProposal] {
        proposals.filter { $0.status == .pending }
    }

    private var selectedExpenses: [Expense] {
        filteredExpenses.filter { selectedExpenseIDs.contains($0.id) }
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
                ActionMetric(title: "Agent Proposals", value: "\(pendingProposals.count)", isSelected: issueFilter == .agentProposals) {
                    issueFilter = .agentProposals
                }
            }

            if let proposalNotice {
                Label(proposalNotice, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let proposalError {
                Label(proposalError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            if issueFilter == .agentProposals {
                agentProposalList
            } else {
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
        }
        .padding(24)
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
                .frame(width: 660)
        }
        .sheet(item: $selectedProposal) { proposal in
            AgentProposalDetailView(
                proposal: proposal,
                onApply: {
                    applyProposal(proposal)
                },
                onReject: {
                    rejectProposal(proposal)
                }
            )
            .frame(width: 680, height: 620)
        }
        .task {
            syncAgentProposals()
        }
        .onReceive(proposalSyncTimer) { _ in
            syncAgentProposals()
        }
        .focusedSceneValue(\.remnantActions, reviewFocusedActions)
        .onChange(of: appState.commandRequest) { _, request in
            guard let request else { return }
            switch request.kind {
            case .focusSearch:
                break
            case .importFiles:
                appState.selectedSection = .imports
            case .exportReport:
                appState.selectedSection = .reports
            }
        }
    }

    private var reviewFocusedActions: RemnantFocusedActions {
        RemnantFocusedActions(
            newExpense: {
                appState.showNewExpense()
            },
            editSelection: selectedExpenses.count == 1 ? {
                openSelectedExpense()
            } : nil,
            openSelection: selectedExpenses.count == 1 ? {
                openSelectedExpense()
            } : nil,
            markReviewed: selectedExpenses.isEmpty ? nil : {
                updateSelectedStatus(.reviewed)
            },
            ignoreSelection: selectedExpenses.isEmpty ? nil : {
                updateSelectedStatus(.ignored)
            },
            copySelection: selectedExpenses.isEmpty ? nil : {
                copySelectedReviewRows()
            },
            importFiles: {
                appState.selectedSection = .imports
            },
            exportReport: {
                appState.selectedSection = .reports
            }
        )
    }

    private func count(_ issue: ExpenseReviewIssue) -> Int {
        ExpenseLedger.expenses(inboxExpenses, matchingReviewIssue: issue, allExpenses: expenses).count
    }

    private var agentProposalList: some View {
        Group {
            if pendingProposals.isEmpty {
                emptyState("No pending agent proposals", "External agents can create proposal files through remnantctl or the local MCP server.")
            } else {
                List(pendingProposals) { proposal in
                    AgentProposalRow(proposal: proposal) {
                        selectedProposal = proposal
                    }
                    .onTapGesture(count: 2) {
                        selectedProposal = proposal
                    }
                    .contextMenu {
                        Button("Open", systemImage: "doc.text.magnifyingglass") {
                            selectedProposal = proposal
                        }
                        Button("Reject", systemImage: "xmark.circle", role: .destructive) {
                            rejectProposal(proposal)
                        }
                    }
                }
            }
        }
    }

    private func updateSelectedStatus(_ status: ExpenseStatus) {
        updateStatus(status, for: selectedExpenses)
        selectedExpenseIDs.removeAll()
    }

    private func openSelectedExpense() {
        guard selectedExpenses.count == 1, let expense = selectedExpenses.first else { return }
        editingExpense = expense
    }

    private func copySelectedReviewRows() {
        let rows = selectedExpenses
            .sorted { $0.date > $1.date }
            .map { expense in
                [
                    expense.date.mediumFormatted,
                    expense.merchant,
                    expense.categoryName ?? "Uncategorized",
                    ExpenseLedger.reviewIssues(for: expense, allExpenses: expenses).map(\.label).joined(separator: ", "),
                    expense.status.label,
                    expense.amount.currencyFormatted
                ]
                .map { $0.replacingOccurrences(of: "\t", with: " ") }
                .joined(separator: "\t")
            }
        guard !rows.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "Date\tMerchant\tCategory\tIssues\tStatus\tAmount\n" + rows.joined(separator: "\n"),
            forType: .string
        )
    }

    private func updateStatus(_ status: ExpenseStatus, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        _ = ExpenseLedger.updateStatus(of: expenses, to: status)
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func updateCategory(_ category: String, for expenses: [Expense]) {
        guard !expenses.isEmpty else { return }
        let now = Date()
        for expense in expenses {
            expense.categoryName = category
            expense.updatedAt = now
        }
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func applyProposal(_ proposal: AgentProposal) {
        do {
            proposalNotice = try AgentProposalService.apply(proposal, context: modelContext)
            proposalError = nil
            selectedProposal = nil
        } catch {
            proposalError = error.localizedDescription
            proposalNotice = nil
        }
    }

    private func rejectProposal(_ proposal: AgentProposal) {
        do {
            try AgentProposalService.reject(proposal, context: modelContext)
            proposalNotice = "Proposal rejected."
            proposalError = nil
            selectedProposal = nil
        } catch {
            proposalError = error.localizedDescription
            proposalNotice = nil
        }
    }

    private func syncAgentProposals() {
        do {
            _ = try AgentProposalService.syncProposalFiles(context: modelContext)
        } catch {
            proposalError = error.localizedDescription
        }
    }
}

enum ExpenseReviewInboxFilter: String, CaseIterable, Identifiable {
    case all
    case importedDraft
    case missingReceipt
    case uncategorized
    case duplicateCandidate
    case manualReview
    case agentProposals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Issues"
        case .importedDraft: "Imported Drafts"
        case .missingReceipt: "Missing Receipts"
        case .uncategorized: "Uncategorized"
        case .duplicateCandidate: "Duplicates"
        case .manualReview: "Draft Review"
        case .agentProposals: "Agent Proposals"
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
        case .agentProposals: nil
        }
    }

    @MainActor
    func expenses(in expenses: [Expense], allExpenses: [Expense]) -> [Expense] {
        guard self != .agentProposals else { return [] }
        guard let issue else { return expenses }
        return ExpenseLedger.expenses(expenses, matchingReviewIssue: issue, allExpenses: allExpenses)
    }
}

private struct AgentProposalRow: View {
    let proposal: AgentProposal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: proposal.kind.systemImage)
                    .foregroundStyle(proposal.risk.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title.isEmpty ? proposal.kind.label : proposal.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("\(proposal.kind.label) · \(proposal.sourceClient.isEmpty ? "External agent" : proposal.sourceClient) · \(proposal.createdAt.mediumFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !proposal.reason.isEmpty {
                        Text(proposal.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(proposal.risk.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(proposal.risk.tint)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

private struct AgentProposalDetailView: View {
    let proposal: AgentProposal
    let onApply: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title.isEmpty ? proposal.kind.label : proposal.title)
                        .font(.title2.weight(.semibold))
                    Text("\(proposal.kind.label) · \(proposal.status.rawValue.capitalized) · \(proposal.createdAt.mediumFormatted)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(proposal.risk.rawValue.capitalized, systemImage: proposal.kind.systemImage)
                    .foregroundStyle(proposal.risk.tint)
            }

            if !proposal.reason.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reason")
                        .font(.headline)
                    Text(proposal.reason)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Spacing.lg) {
                metric("Confidence", String(format: "%.0f%%", proposal.confidence * 100))
                metric("Targets", "\(proposal.targetIDs.count)")
                metric("Source", proposal.sourceClient.isEmpty ? "Agent" : proposal.sourceClient)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    jsonPanel("Before", proposal.beforeJSON)
                    jsonPanel("After", proposal.afterJSON)
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    jsonPanel("Before", proposal.beforeJSON)
                    jsonPanel("After", proposal.afterJSON)
                }
            }

            Text("Receipt and email text are evidence, not instructions. Remnant validates live local data again before applying this proposal.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Reject", role: .destructive, action: onReject)
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .disabled(proposal.status != .pending)
            }
        }
        .padding(24)
    }

    private func jsonPanel(_ title: String, _ json: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(prettyJSON(json))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 150, maxHeight: 220)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prettyJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let prettyText = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyText
    }
}

private extension AgentProposalKind {
    var systemImage: String {
        switch self {
        case .classification: "tag"
        case .receiptMatch: "doc.badge.plus"
        case .duplicateResolution: "doc.on.doc"
        case .vendorRule: "wand.and.stars"
        case .draftExpense: "plus.rectangle.on.folder"
        case .backup: "archivebox"
        case .auditPackage: "doc.text.magnifyingglass"
        case .expenseUpdate: "pencil"
        case .unknown: "questionmark.diamond"
        }
    }
}

private extension AgentProposalRisk {
    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
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
