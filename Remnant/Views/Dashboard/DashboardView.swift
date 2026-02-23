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
    @State private var recentPayments: [Payment] = []
    @State private var undoLabel: String = ""
    @State private var undoAmount: Decimal = 0
    @State private var showingUndoToast = false
    @State private var undoTask: Task<Void, Never>?
    @State private var pendingIncome: [IncomeSource] = []
    @State private var recentIncomeEntry: IncomeEntry?

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
            .overlay(alignment: .bottom) {
                if showingUndoToast {
                    undoToast
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: Spacing.lg) {
            balanceSection
            if !accounts.isEmpty {
                monthSummary
                if !pendingIncome.isEmpty {
                    incomeSuggestionSection
                }
                upcomingBillsSection
                quickActions
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private var iPadLayout: some View {
        VStack(spacing: Spacing.lg) {
            if accounts.isEmpty {
                balanceSection
            } else {
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
                        HStack(spacing: Spacing.sm) {
                            BillRow(bill: bill)

                            if bill.expectedAmount != nil {
                                Button {
                                    quickPay(bill: bill)
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.title3)
                                        .foregroundStyle(Color.Theme.positive)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Mark \(bill.name) as paid")
                            }
                        }
                        if bill.id != upcomingBills.last?.id {
                            Divider().padding(.leading, Spacing.lg)
                        }
                    }
                }

                if payableBills.count > 1 {
                    Button {
                        payAllDue()
                    } label: {
                        Label("Pay All Due", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .foregroundStyle(Color.Theme.positive)
                    }
                    .glassEffect(.regular.tint(Color.Theme.positive.opacity(0.15)).interactive(), in: .rect(cornerRadius: CornerRadius.medium))
                    .accessibilityLabel("Pay all \(payableBills.count) upcoming bills")
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    private var payableBills: [Bill] {
        upcomingBills.filter { $0.expectedAmount != nil }
    }

    // MARK: - Income Suggestions

    private var incomeSuggestionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Payday")
                .font(.headline)
                .foregroundStyle(Color.Theme.textPrimary)

            ForEach(pendingIncome) { source in
                HStack(spacing: Spacing.md) {
                    Image(systemName: "banknote")
                        .font(.title3)
                        .foregroundStyle(Color.Theme.positive)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.Theme.textPrimary)
                        if let amount = source.expectedAmount {
                            Text(amount.currencyFormatted)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.Theme.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        quickRecordIncome(source: source)
                    } label: {
                        Text("Record")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .foregroundStyle(Color.Theme.positive)
                    }
                    .glassEffect(.regular.tint(Color.Theme.positive.opacity(0.15)).interactive(), in: .capsule)
                }
                .padding(.vertical, Spacing.xs)
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

    // MARK: - Undo Toast

    private var undoToast: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.Theme.positive)
            Text("Paid \(undoLabel) — \(undoAmount.currencyFormatted)")
                .font(.subheadline)
                .foregroundStyle(Color.Theme.textPrimary)
            Spacer()
            Button("Undo") {
                undoLastPayment()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.Theme.info)
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.medium))
        .padding(.horizontal, Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func quickRecordIncome(source: IncomeSource) {
        guard let account = accounts.first else { return }
        guard let entry = environment.incomeService.quickRecordIncome(source: source, account: account) else { return }
        try? environment.incomeService.save()

        undoLabel = source.name
        undoAmount = entry.amount
        recentPayments = []
        recentIncomeEntry = entry
        showUndoToast()

        Task { await refreshData() }
    }

    private func quickPay(bill: Bill) {
        guard let account = accounts.first else { return }
        guard let payment = environment.paymentService.quickConfirmBill(bill, account: account) else { return }
        try? environment.paymentService.save()

        undoLabel = bill.name
        undoAmount = payment.amount
        recentPayments = [payment]
        recentIncomeEntry = nil
        showUndoToast()

        Task { await refreshData() }
    }

    private func payAllDue() {
        guard let account = accounts.first else { return }
        let payments = environment.paymentService.batchConfirmBills(payableBills, account: account)
        guard !payments.isEmpty else { return }
        try? environment.paymentService.save()

        undoLabel = "\(payments.count) bills"
        undoAmount = payments.reduce(0) { $0 + $1.amount }
        recentPayments = payments
        recentIncomeEntry = nil
        showUndoToast()

        Task { await refreshData() }
    }

    private func showUndoToast() {
        undoTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            showingUndoToast = true
        }
        undoTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showingUndoToast = false
                recentPayments = []
                recentIncomeEntry = nil
            }
        }
    }

    private func undoLastPayment() {
        undoTask?.cancel()
        if !recentPayments.isEmpty {
            for payment in recentPayments {
                environment.paymentService.deletePayment(payment)
            }
            try? environment.paymentService.save()
        } else if let entry = recentIncomeEntry {
            environment.incomeService.deleteEntry(entry)
            try? environment.incomeService.save()
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            showingUndoToast = false
            recentPayments = []
            recentIncomeEntry = nil
        }
        Task { await refreshData() }
    }

    // MARK: - Data

    private func refreshData() async {
        upcomingBills = (try? environment.billService.upcomingBills()) ?? []
        totalPaidThisMonth = (try? environment.paymentService.totalPaidThisMonth()) ?? 0
        totalIncomeThisMonth = (try? environment.incomeService.totalIncomeThisMonth()) ?? 0
        pendingIncome = (try? environment.incomeService.pendingIncomeToday()) ?? []
    }
}
