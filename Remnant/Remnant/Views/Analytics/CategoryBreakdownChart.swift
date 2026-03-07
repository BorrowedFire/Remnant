import SwiftUI
import Charts

struct CategoryBreakdownChart: View {
    let data: [(category: String, colorHex: String, total: Decimal)]

    private var grandTotal: Decimal {
        data.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("By Category")
                .font(.headline)
                .foregroundStyle(Color.Theme.textPrimary)

            if data.isEmpty {
                Text("No spending data")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
            } else {
                Chart(data, id: \.category) { item in
                    SectorMark(
                        angle: .value("Amount", Double(truncating: item.total as NSDecimalNumber)),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                    .cornerRadius(4)
                }
                .frame(height: 180)

                // Legend
                VStack(spacing: Spacing.sm) {
                    ForEach(data, id: \.category) { item in
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 10, height: 10)
                            Text(item.category)
                                .font(.caption)
                                .foregroundStyle(Color.Theme.textPrimary)
                            Spacer()
                            Text(item.total.compactCurrencyFormatted)
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Color.Theme.textSecondary)
                            if grandTotal > 0 {
                                let pct = Double(truncating: (item.total / grandTotal * 100) as NSDecimalNumber)
                                Text("\(Int(pct))%")
                                    .font(.caption2)
                                    .foregroundStyle(Color.Theme.textTertiary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }
}
