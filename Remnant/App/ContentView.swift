import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appState: RemnantAppState
    @SceneStorage("Remnant.selectedSection") private var selectedSectionRawValue = ExpenseSection.dashboard.rawValue
    @State private var reviewInboxFilter = ExpenseReviewInboxFilter.all
    @State private var expenseReviewFilter = ExpenseReviewFilter.needsReview
    @State private var expenseSearchText = ""
    @State private var expenseCategoryFilter: String?
    @State private var reportTaxYear = Calendar.current.component(.year, from: Date())
    @State private var reportDateRange = ReportDateRange.taxYear
    @State private var reportCustomStartDate = Calendar.current.date(
        from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1)
    ) ?? Date()
    @State private var reportCustomEndDate = Date()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 6))
                    Text("Remnant")
                        .font(.headline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                List(ExpenseSection.allCases, selection: $appState.selectedSection) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Local ledger", systemImage: "lock")
                        .font(.caption.weight(.medium))
                    Text("Data stays on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            detailView
        }
        .sheet(item: $appState.presentedSheet) { destination in
            switch destination {
            case .newExpense:
                ExpenseFormView()
                    .frame(width: 660)
            }
        }
        .onAppear {
            appState.selectedSection = ExpenseSection(rawValue: selectedSectionRawValue) ?? .dashboard
        }
        .onChange(of: appState.selectedSection) { _, section in
            selectedSectionRawValue = section.rawValue
        }
        .task {
            _ = try? RemnantBackupService.repairReceiptPaths(context: modelContext)
            try? ExpenseLedger.seedDefaultCategoriesIfNeeded(context: modelContext)
            _ = try? ExpenseLedger.clearCompanyProjectAssignmentsIfNeeded(context: modelContext)
            _ = try? RemnantBackupService.runAutomaticBackupIfNeeded(context: modelContext)
            _ = try? AgentProposalService.syncProposalFiles(context: modelContext)
            _ = try? AgentSnapshotService.writeSnapshot(context: modelContext)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            ExpenseDashboardView(
                selectedSection: $appState.selectedSection,
                reviewInboxFilter: $reviewInboxFilter,
                expenseReviewFilter: $expenseReviewFilter,
                expenseSearchText: $expenseSearchText,
                expenseCategoryFilter: $expenseCategoryFilter,
                reportTaxYear: $reportTaxYear,
                reportDateRange: $reportDateRange,
                reportCustomStartDate: $reportCustomStartDate,
                reportCustomEndDate: $reportCustomEndDate
            )
        case .review:
            ExpenseReviewInboxView(issueFilter: $reviewInboxFilter)
        case .expenses:
            ExpenseListView(
                reviewFilter: $expenseReviewFilter,
                searchText: $expenseSearchText,
                categoryFilter: $expenseCategoryFilter
            )
        case .imports:
            ImportCenterView()
        case .reports:
            ReportsView(
                taxYear: $reportTaxYear,
                dateRange: $reportDateRange,
                customStartDate: $reportCustomStartDate,
                customEndDate: $reportCustomEndDate
            )
        }
    }

    private var selectedSection: ExpenseSection {
        appState.selectedSection
    }
}
