import SwiftUI
import Charts

struct SpendingTrendChart: View {
    let data: [(month: Int, total: Decimal)]
    let year: Int

    private static let monthAbbrevs = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Monthly Spending")
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                Spacer()
                Text(String(year))
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textTertiary)
            }

            Chart(data, id: \.month) { item in
                BarMark(
                    x: .value("Month", Self.monthAbbrevs[item.month - 1]),
                    y: .value("Amount", Double(truncating: item.total as NSDecimalNumber))
                )
                .foregroundStyle(
                    item.total > 0
                        ? Color.Theme.accent.gradient
                        : Color.Theme.surfaceElevated.gradient
                )
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Decimal(amount).compactCurrencyFormatted)
                                .font(.caption2)
                                .foregroundStyle(Color.Theme.textTertiary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.Theme.surfaceElevated)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.textTertiary)
                }
            }
            .frame(height: 200)
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }
}
