import SwiftData
import SwiftUI

enum ExpenseSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard = "Dashboard"
    case review = "Review Inbox"
    case expenses = "Expenses"
    case imports = "Imports"
    case reports = "Reports"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.xaxis"
        case .review: "tray.full"
        case .expenses: "list.bullet.rectangle"
        case .imports: "square.and.arrow.down"
        case .reports: "doc.text.magnifyingglass"
        case .settings: "lock.shield"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: ExpenseSection = .dashboard
    @State private var reviewInboxFilter = ExpenseReviewInboxFilter.all
    @State private var expenseReviewFilter = ExpenseReviewFilter.needsReview
    @State private var expenseSearchText = ""
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

                List(ExpenseSection.allCases, selection: $selectedSection) { section in
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
                }
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            detailView
        }
        .task {
            _ = try? RemnantBackupService.repairReceiptPaths(context: modelContext)
            try? ExpenseLedger.seedDefaultCategoriesIfNeeded(context: modelContext)
            _ = try? ExpenseLedger.clearCompanyProjectAssignmentsIfNeeded(context: modelContext)
            _ = try? RemnantBackupService.runAutomaticBackupIfNeeded(context: modelContext)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            ExpenseDashboardView(
                selectedSection: $selectedSection,
                reviewInboxFilter: $reviewInboxFilter,
                expenseReviewFilter: $expenseReviewFilter,
                expenseSearchText: $expenseSearchText,
                reportTaxYear: $reportTaxYear,
                reportDateRange: $reportDateRange,
                reportCustomStartDate: $reportCustomStartDate,
                reportCustomEndDate: $reportCustomEndDate
            )
        case .review:
            ExpenseReviewInboxView(issueFilter: $reviewInboxFilter)
        case .expenses:
            ExpenseListView(reviewFilter: $expenseReviewFilter, searchText: $expenseSearchText)
        case .imports:
            ImportCenterView()
        case .reports:
            ReportsView(
                taxYear: $reportTaxYear,
                dateRange: $reportDateRange,
                customStartDate: $reportCustomStartDate,
                customEndDate: $reportCustomEndDate
            )
        case .settings:
            ExpenseSettingsView()
        }
    }
}
