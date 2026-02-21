import SwiftUI

struct BillRow: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Category color indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.Theme.textPrimary)

                HStack(spacing: Spacing.xs) {
                    if let category = bill.category {
                        Text(category.name)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.textTertiary)
                    }
                    if let nextDue = bill.nextDueDate {
                        let days = nextDue.daysUntil()
                        Text(dueDateLabel(days: days))
                            .font(.caption)
                            .foregroundStyle(days <= 3 ? Color.Theme.warning : Color.Theme.textTertiary)
                    }
                }
            }

            Spacer()

            if let expected = bill.expectedAmount {
                Text(expected.currencyFormatted)
                    .font(.body.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.Theme.textPrimary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(billAccessibilityLabel)
    }

    private var billAccessibilityLabel: String {
        var parts = [bill.name]
        if let expected = bill.expectedAmount {
            parts.append(expected.currencyFormatted)
        }
        if let category = bill.category {
            parts.append(category.name)
        }
        if let nextDue = bill.nextDueDate {
            parts.append(dueDateLabel(days: nextDue.daysUntil()))
        }
        return parts.joined(separator: ", ")
    }

    private var categoryColor: Color {
        guard let hex = bill.category?.colorHex else { return Color.Theme.textTertiary }
        return Color(hex: hex)
    }

    private func dueDateLabel(days: Int) -> String {
        switch days {
        case ..<0: return "Overdue"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(days)d"
        }
    }
}
