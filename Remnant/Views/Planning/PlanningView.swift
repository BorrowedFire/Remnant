import SwiftUI
import SwiftData

struct PlanningView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var bills: [Bill] = []
    @State private var selectedBillIDs: Set<UUID> = []
    @State private var customAmounts: [UUID: Decimal] = [:]
    @State private var showingConfirmation = false

    private var selectedAccount: Account? { accounts.first }

    private var currentBalance: Decimal {
        selectedAccount?.currentBalance ?? 0
    }

    private var totalPlanned: Decimal {
        bills
            .filter { selectedBillIDs.contains($0.id) }
            .reduce(0) { total, bill in
                total + (customAmounts[bill.id] ?? bill.expectedAmount ?? 0)
            }
    }

    private var projectedRemaining: Decimal {
        currentBalance - totalPlanned
    }

    var body: some View {
        NavigationStack {
            if !environment.subscriptionService.isPremium {
                PremiumGateView(
                    icon: "target",
                    title: "Planning Mode",
                    description: "Simulate payments before you commit. See your projected balance in real time."
                )
                .navigationTitle("Plan")
            } else {
                planningContent
            }
        }
    }

    private var planningContent: some View {
        VStack(spacing: 0) {
            // Balance header
            planningHeader

            // Bill list
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(bills) { bill in
                        PlanningBillRow(
                            bill: bill,
                            isSelected: selectedBillIDs.contains(bill.id),
                            customAmount: Binding(
                                get: { customAmounts[bill.id] ?? bill.expectedAmount ?? 0 },
                                set: { customAmounts[bill.id] = $0 }
                            ),
                            onToggle: { toggleBill(bill) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }

            // Confirm button
            if !selectedBillIDs.isEmpty {
                confirmButton
            }
        }
        .background(Color.Theme.background)
        .navigationTitle("Plan")
        .task {
            bills = (try? environment.billService.fetchAll()) ?? []
        }
        .alert("Confirm Payments", isPresented: $showingConfirmation) {
            Button("Confirm All", role: .destructive) { confirmPayments() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Record \(selectedBillIDs.count) payments totaling \(totalPlanned.currencyFormatted)?")
        }
    }

    // MARK: - Header

    private var planningHeader: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Balance")
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                    Text(currentBalance.currencyFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("After Payments")
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                    Text(projectedRemaining.currencyFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(projectedRemaining >= 0 ? Color.Theme.positive : Color.Theme.negative)
                        .contentTransition(.numericText())
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.Theme.surfaceElevated)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(projectedRemaining >= 0 ? Color.Theme.positive : Color.Theme.negative)
                        .frame(width: max(0, geo.size.width * spentRatio))
                        .animation(.spring(duration: 0.3), value: totalPlanned)
                }
            }
            .frame(height: 6)
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    private var spentRatio: CGFloat {
        guard currentBalance > 0 else { return 0 }
        return min(1, CGFloat(truncating: totalPlanned / currentBalance as NSDecimalNumber))
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack {
                Text("Confirm \(selectedBillIDs.count) Payment\(selectedBillIDs.count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
                Spacer()
                Text(totalPlanned.currencyFormatted)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .padding(Spacing.lg)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: CornerRadius.medium))
        .tint(Color.Theme.accent)
        .padding(Spacing.lg)
    }

    // MARK: - Actions

    private func toggleBill(_ bill: Bill) {
        if selectedBillIDs.contains(bill.id) {
            selectedBillIDs.remove(bill.id)
        } else {
            selectedBillIDs.insert(bill.id)
        }
    }

    private func confirmPayments() {
        guard let account = selectedAccount else { return }
        for bill in bills where selectedBillIDs.contains(bill.id) {
            let amount = customAmounts[bill.id] ?? bill.expectedAmount ?? 0
            _ = environment.paymentService.recordPayment(
                bill: bill,
                amount: amount,
                account: account
            )
        }
        try? environment.paymentService.save()
        selectedBillIDs.removeAll()
        customAmounts.removeAll()
    }
}
