import SwiftUI
import SwiftData

struct YearView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var bills: [Bill] = []

    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // Header row
                        headerRow

                        // Bill rows
                        ForEach(bills) { bill in
                            billRow(bill)
                            Divider()
                        }

                        // Total row
                        totalRow
                    }
                    .padding(Spacing.md)
                }
            }
            .background(Color.Theme.background)
            .navigationTitle("\(String(year)) Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Spacing.sm) {
                        Button { year -= 1 } label: {
                            Image(systemName: "chevron.left")
                        }
                        Button { year += 1 } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .task { await loadBills() }
            .onChange(of: year) { _, _ in Task { await loadBills() } }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Bill")
                .frame(width: 140, alignment: .leading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.Theme.textSecondary)

            ForEach(months, id: \.self) { month in
                Text(month)
                    .frame(width: 70)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.Theme.textSecondary)
            }

            Text("Total")
                .frame(width: 80)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.Theme.textPrimary)
        }
        .padding(.vertical, Spacing.sm)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    // MARK: - Bill Row

    private func billRow(_ bill: Bill) -> some View {
        HStack(spacing: 0) {
            Text(bill.name)
                .frame(width: 140, alignment: .leading)
                .font(.caption)
                .foregroundStyle(Color.Theme.textPrimary)
                .lineLimit(1)

            ForEach(1...12, id: \.self) { month in
                let amount = bill.totalPaid(month: month, year: year)
                Text(amount > 0 ? amount.compactCurrencyFormatted : "—")
                    .frame(width: 70)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(amount > 0 ? Color.Theme.textPrimary : Color.Theme.textTertiary)
            }

            let yearTotal = bill.totalPaidThisYear(in: year)
            Text(yearTotal > 0 ? yearTotal.compactCurrencyFormatted : "—")
                .frame(width: 80)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(yearTotal > 0 ? Color.Theme.textPrimary : Color.Theme.textTertiary)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Total Row

    private var totalRow: some View {
        HStack(spacing: 0) {
            Text("TOTAL")
                .frame(width: 140, alignment: .leading)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.Theme.accent)

            ForEach(1...12, id: \.self) { month in
                let total = bills.reduce(0 as Decimal) { $0 + $1.totalPaid(month: month, year: year) }
                Text(total > 0 ? total.compactCurrencyFormatted : "—")
                    .frame(width: 70)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(total > 0 ? Color.Theme.accent : Color.Theme.textTertiary)
            }

            let grandTotal = bills.reduce(0 as Decimal) { $0 + $1.totalPaidThisYear(in: year) }
            Text(grandTotal > 0 ? grandTotal.compactCurrencyFormatted : "—")
                .frame(width: 80)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.Theme.accent)
        }
        .padding(.vertical, Spacing.sm)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    // MARK: - Data

    private func loadBills() async {
        bills = (try? environment.billService.fetchAll()) ?? []
    }
}
