import SwiftUI

struct CurrencyField: View {
    let title: String
    @Binding var amount: Decimal

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.Theme.textSecondary)

            HStack(spacing: Spacing.xs) {
                Text("$")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.Theme.textSecondary)

                TextField("0.00", text: $text)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        if filtered != newValue { text = filtered }
                        amount = Decimal(string: filtered) ?? 0
                    }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(isFocused ? Color.Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(amount.currencyFormatted)")
        .accessibilityHint("Double tap to edit amount")
        .onAppear {
            if amount != 0 {
                text = "\(amount)"
            }
        }
    }
}
