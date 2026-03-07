import SwiftUI
import SwiftData

enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case payments = "Payments"
    case income = "Income"
}

struct MonthlyView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var selectedMonth: Int
    @State private var selectedYear: Int
    @State private var payments: [Payment] = []
    @State private var incomeEntries: [IncomeEntry] = []
    @State private var categoryData: [(category: String, colorHex: String, total: Decimal)] = []
    @State private var trendData: [(month: Int, total: Decimal)] = []
    @State private var showingYearView = false
    @State private var showingSubscription = false
    @State private var selectedFilter: HistoryFilter = .all

    init() {
        let now = Date()
        _selectedMonth = State(initialValue: Calendar.current.component(.month, from: now))
        _selectedYear = State(initialValue: Calendar.current.component(.year, from: now))
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "" }
        return formatter.string(from: date)
    }

    private var isPremium: Bool { environment.subscriptionService.isPremium }

    private var totalPaid: Decimal {
        payments.reduce(0) { $0 + $1.amount }
    }

    private var totalEarned: Decimal {
        incomeEntries.reduce(0) { $0 + $1.amount }
    }

    private var groupedByCategory: [(category: String, payments: [Payment], total: Decimal)] {
        let grouped = Dictionary(grouping: payments) { $0.bill?.category?.name ?? "Other" }
        return grouped
            .map { (category: $0.key, payments: $0.value, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var groupedIncome: [(source: String, entries: [IncomeEntry], total: Decimal)] {
        let grouped = Dictionary(grouping: incomeEntries) { $0.source?.name ?? "Other" }
        return grouped
            .map { (source: $0.key, entries: $0.value, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var showPayments: Bool {
        selectedFilter == .all || selectedFilter == .payments
    }

    private var showIncome: Bool {
        selectedFilter == .all || selectedFilter == .income
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    monthSelector

                    // Filter picker
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(HistoryFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Summary cards
                    summaryCards

                    // Charts (premium, payments only)
                    if isPremium && !payments.isEmpty && showPayments {
                        CategoryBreakdownChart(data: categoryData)
                        SpendingTrendChart(data: trendData, year: selectedYear)
                    }

                    // Income section
                    if showIncome && !incomeEntries.isEmpty {
                        ForEach(groupedIncome, id: \.source) { group in
                            incomeGroup(group)
                        }
                    }

                    // Payments section
                    if showPayments && !payments.isEmpty {
                        ForEach(groupedByCategory, id: \.category) { group in
                            categoryGroup(group)
                        }
                    }

                    // Empty state
                    if isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "doc.text",
                            description: Text("Nothing recorded for \(monthName).")
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
            .background(Color.Theme.background)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Year View", systemImage: "calendar") {
                        if isPremium {
                            showingYearView = true
                        } else {
                            showingSubscription = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingYearView) {
                YearView()
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .task { await loadData() }
            .onChange(of: selectedMonth) { _, _ in Task { await loadData() } }
            .onChange(of: selectedYear) { _, _ in Task { await loadData() } }
        }
    }

    // MARK: - Empty State

    private var isEmpty: Bool {
        switch selectedFilter {
        case .all: payments.isEmpty && incomeEntries.isEmpty
        case .payments: payments.isEmpty
        case .income: incomeEntries.isEmpty
        }
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .all: "No Activity"
        case .payments: "No Payments"
        case .income: "No Income"
        }
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack {
            Button {
                if isPremium {
                    navigateMonth(by: -1)
                } else {
                    showingSubscription = true
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .disabled(!isPremium)

            Spacer()

            VStack(spacing: 2) {
                Text(monthName)
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                if !isPremium {
                    Text("Upgrade for full history")
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.premium)
                }
            }

            Spacer()

            Button {
                if isPremium {
                    navigateMonth(by: 1)
                } else {
                    showingSubscription = true
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(!isPremium)
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        VStack(spacing: Spacing.md) {
            if showIncome && showPayments {
                // All filter — show both + net
                HStack(spacing: Spacing.md) {
                    summaryCard(
                        title: "Earned",
                        amount: totalEarned,
                        count: incomeEntries.count,
                        label: "deposit",
                        color: Color.Theme.positive
                    )
                    summaryCard(
                        title: "Spent",
                        amount: totalPaid,
                        count: payments.count,
                        label: "payment",
                        color: Color.Theme.negative
                    )
                }

                // Net card
                let net = totalEarned - totalPaid
                VStack(spacing: Spacing.xs) {
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                    Text(net.currencyFormatted)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(net >= 0 ? Color.Theme.positive : Color.Theme.negative)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
            } else if showIncome {
                summaryCard(
                    title: "Total Earned",
                    amount: totalEarned,
                    count: incomeEntries.count,
                    label: "deposit",
                    color: Color.Theme.positive
                )
            } else {
                summaryCard(
                    title: "Total Paid",
                    amount: totalPaid,
                    count: payments.count,
                    label: "payment",
                    color: Color.Theme.textPrimary
                )
            }
        }
    }

    private func summaryCard(
        title: String,
        amount: Decimal,
        count: Int,
        label: String,
        color: Color
    ) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.Theme.textTertiary)
            Text(amount.currencyFormatted)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Color.Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Income Group

    private func incomeGroup(_ group: (source: String, entries: [IncomeEntry], total: Decimal)) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label(group.source, systemImage: "building.2.fill")
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                Spacer()
                Text(group.total.currencyFormatted)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.Theme.positive)
            }

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    incomeRow(entry)
                    if entry.id != group.entries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    private func incomeRow(_ entry: IncomeEntry) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source?.name ?? "Income")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.Theme.textPrimary)
                Text(entry.date.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textTertiary)
            }
            Spacer()
            Text("+" + entry.amount.currencyFormatted)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.Theme.positive)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Category Group (Payments)

    private func categoryGroup(_ group: (category: String, payments: [Payment], total: Decimal)) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(group.category)
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                Spacer()
                Text(group.total.currencyFormatted)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.Theme.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(group.payments ?? []) { payment in
                    PaymentRow(payment: payment)
                    if payment.id != (group.payments ?? []).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Helpers

    private func navigateMonth(by offset: Int) {
        var month = selectedMonth + offset
        var year = selectedYear
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
        selectedMonth = month
        selectedYear = year
    }

    private func loadData() async {
        payments = (try? environment.paymentService.paymentsForMonth(
            month: selectedMonth, year: selectedYear
        )) ?? []
        incomeEntries = (try? environment.incomeService.entriesForMonth(
            month: selectedMonth, year: selectedYear
        )) ?? []
        categoryData = (try? environment.paymentService.categoryTotals(
            month: selectedMonth, year: selectedYear
        )) ?? []
        trendData = (try? environment.paymentService.monthlyTotals(for: selectedYear)) ?? []
    }
}
