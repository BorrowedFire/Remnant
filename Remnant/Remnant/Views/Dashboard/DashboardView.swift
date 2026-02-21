import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var upcomingBills: [Bill] = []
    @State private var totalPaidThisMonth: Decimal = 0
    @State private var totalIncomeThisMonth: Decimal = 0
    @State private var showingSettings = false
    @State private var showingAddPayment = false
    @State private var showingAddIncome = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                if sizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
            .background(Color.Theme.background)
            .navigationTitle("Remnant")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAddPayment) {
                RecordPaymentView()
            }
            .sheet(isPresented: $showingAddIncome) {
                IncomeEntryForm()
            }
            .task { await refreshData() }
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: Spacing.lg) {
            balanceSection
            monthSummary
            upcomingBillsSection
            quickActions
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private var iPadLayout: some View {
        VStack(spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                VStack(spacing: Spacing.lg) {
                    balanceSection
                    monthSummary
                    quickActions
                }
                .frame(maxWidth: .infinity)

                upcomingBillsSection
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - Balance Section

    private var balanceSection: some View {
        VStack(spacing: Spacing.sm) {
            if let primary = accounts.first {
                VStack(spacing: Spacing.xs) {
                    Text(primary.name)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textSecondary)

                    Text(primary.currentBalance.currencyFormatted)
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.Theme.textPrimary)
                        .contentTransition(.numericText())

                    Text("Current Balance")
                        .font(.subheadline)
                        .foregroundStyle(Color.Theme.textTertiary)
                }
            } else {
                VStack(spacing: Spacing.sm) {
                    Text("No Account")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.Theme.textSecondary)
                    Text("Add an account to start tracking")
                        .font(.subheadline)
                        .foregroundStyle(Color.Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Month Summary

    private var monthSummary: some View {
        GlassEffectContainer(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                summaryCard(title: "Income", amount: totalIncomeThisMonth, color: Color.Theme.positive)
                summaryCard(title: "Paid", amount: totalPaidThisMonth, color: Color.Theme.negative)
                summaryCard(
                    title: "Remaining",
                    amount: (accounts.first?.currentBalance ?? 0),
                    color: Color.Theme.info
                )
            }
        }
    }

    private func summaryCard(title: String, amount: Decimal, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.Theme.textTertiary)
            Text(amount.compactCurrencyFormatted)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(amount.currencyFormatted)")
    }

    // MARK: - Upcoming Bills

    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Upcoming Bills")
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                Spacer()
                Text("Next 7 days")
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textTertiary)
            }

            if upcomingBills.isEmpty {
                Text("No upcoming bills this week")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcomingBills) { bill in
                        BillRow(bill: bill)
                        if bill.id != upcomingBills.last?.id {
                            Divider().padding(.leading, Spacing.lg)
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        GlassEffectContainer(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Button {
                    showingAddPayment = true
                } label: {
                    Label("Record Payment", systemImage: "minus.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(Color.Theme.negative)
                }
                .glassEffect(.regular.tint(Color.Theme.negative.opacity(0.2)).interactive(), in: .rect(cornerRadius: CornerRadius.medium))

                Button {
                    showingAddIncome = true
                } label: {
                    Label("Add Income", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(Color.Theme.positive)
                }
                .glassEffect(.regular.tint(Color.Theme.positive.opacity(0.2)).interactive(), in: .rect(cornerRadius: CornerRadius.medium))
            }
        }
    }

    // MARK: - Data

    private func refreshData() async {
        upcomingBills = (try? environment.billService.upcomingBills()) ?? []
        totalPaidThisMonth = (try? environment.paymentService.totalPaidThisMonth()) ?? 0
        totalIncomeThisMonth = (try? environment.incomeService.totalIncomeThisMonth()) ?? 0
    }
}
