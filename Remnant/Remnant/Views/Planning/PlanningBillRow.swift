import SwiftUI

struct PlanningBillRow: View {
    let bill: Bill
    let isSelected: Bool
    @Binding var customAmount: Decimal
    let onToggle: () -> Void

    @State private var isEditingAmount = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.Theme.accent : Color.Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.Theme.textPrimary)
                    .strikethrough(isSelected, color: Color.Theme.textTertiary)

                if let category = bill.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                }
            }

            Spacer()

            if isSelected && isEditingAmount {
                CurrencyField(title: "", amount: $customAmount)
                    .frame(width: 120)
            } else {
                Button {
                    if isSelected { isEditingAmount = true }
                } label: {
                    Text(customAmount.currencyFormatted)
                        .font(.body.weight(.medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.Theme.textPrimary : Color.Theme.textTertiary)
                }
                .disabled(!isSelected)
            }
        }
        .padding(Spacing.md)
        .glassEffect(
            isSelected
                ? .regular.tint(Color.Theme.accent.opacity(0.15)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: CornerRadius.medium)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bill.name), \(customAmount.currencyFormatted), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") this bill for payment")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
