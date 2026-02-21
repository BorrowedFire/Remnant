import SwiftUI
import SwiftData

struct BillDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let bill: Bill

    @State private var showingRecordPayment = false
    @State private var showingEdit = false

    private var recentPayments: [Payment] {
        (bill.payments ?? [])
            .filter { !$0.isPlanned }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                headerCard

                // Year totals
                yearTotalCard

                // Recent payments
                recentPaymentsSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(Color.Theme.background)
        .navigationTitle(bill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Record Payment", systemImage: "dollarsign.circle") {
                        showingRecordPayment = true
                    }
                    Button("Edit Bill", systemImage: "pencil") {
                        showingEdit = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingRecordPayment) {
            QuickPayView(bill: bill)
        }
        .sheet(isPresented: $showingEdit) {
            BillFormView(existingBill: bill)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                if let category = bill.category {
                    Label(category.name, systemImage: category.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(hex: category.colorHex))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color(hex: category.colorHex).opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(bill.frequency.displayName)
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textTertiary)
            }

            if let expected = bill.expectedAmount {
                VStack(spacing: 2) {
                    Text("Expected Amount")
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                    Text(expected.currencyFormatted)
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.Theme.textPrimary)
                }
            }

            if let nextDue = bill.nextDueDate {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.Theme.textTertiary)
                    Text("Next due: \(nextDue.mediumFormatted)")
                        .font(.subheadline)
                        .foregroundStyle(Color.Theme.textSecondary)
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Year Total

    private var yearTotalCard: some View {
        let year = Calendar.current.component(.year, from: Date())
        let total = bill.totalPaidThisYear()

        return HStack {
            Text("Total Paid in \(String(year))")
                .font(.subheadline)
                .foregroundStyle(Color.Theme.textSecondary)
            Spacer()
            Text(total.currencyFormatted)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.Theme.textPrimary)
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    // MARK: - Recent Payments

    private var recentPaymentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Payments")
                .font(.headline)
                .foregroundStyle(Color.Theme.textPrimary)

            if recentPayments.isEmpty {
                Text("No payments recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentPayments.prefix(10)) { payment in
                        PaymentRow(payment: payment)
                        if payment.id != recentPayments.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }
}

// MARK: - Quick Pay

struct QuickPayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    let bill: Bill
    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    CurrencyField(title: "Amount", amount: $amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Pay \(bill.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = environment.paymentService.recordPayment(
                            bill: bill,
                            amount: amount,
                            date: date,
                            account: accounts.first,
                            note: note.isEmpty ? nil : note
                        )
                        try? environment.paymentService.save()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let expected = bill.expectedAmount {
                    amount = expected
                }
            }
        }
    }
}
