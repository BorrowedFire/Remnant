import SwiftUI

struct CurrencyField: View {
    let title: String
    @Binding var amount: Decimal

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"

    private var symbol: String { Decimal.currencySymbol }
    private var decSep: String { Locale.current.decimalSeparator ?? "." }
    private var groupSep: String { Locale.current.groupingSeparator ?? "," }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.Theme.textSecondary)

            HStack(spacing: Spacing.xs) {
                Text(symbol)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.Theme.textSecondary)

                TextField("0", text: $text)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        formatInput(newValue)
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
            syncTextFromAmount()
        }
        .onChange(of: currencyCode) {
            syncTextFromAmount()
        }
    }

    private func syncTextFromAmount() {
        if amount != 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale.current
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            text = formatter.string(from: amount as NSDecimalNumber) ?? ""
        }
    }

    private func formatInput(_ newValue: String) {
        let sepChar = Character(decSep)

        // Strip grouping separators to get raw input
        let stripped = newValue.replacingOccurrences(of: groupSep, with: "")

        // Filter to only digits and one decimal separator
        var hasDecimal = false
        let filtered = stripped.filter { ch in
            if ch.isNumber { return true }
            if ch == sepChar && !hasDecimal {
                hasDecimal = true
                return true
            }
            return false
        }

        // Limit fraction digits to 2
        let parts = filtered.split(separator: sepChar, maxSplits: 1, omittingEmptySubsequences: false)
        let integerStr = String(parts.first ?? "")
        let fractionStr = parts.count > 1 ? String(parts[1].prefix(2)) : nil

        // Parse amount
        var normalized = integerStr
        if let frac = fractionStr {
            normalized += "." + frac
        }
        amount = Decimal(string: normalized) ?? 0

        // Format integer part with grouping separators
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0

        let intValue = Int(integerStr) ?? 0
        let formattedInt = integerStr.isEmpty ? "" : (formatter.string(from: NSNumber(value: intValue)) ?? integerStr)

        // Rebuild display text
        var result = formattedInt
        if filtered.contains(sepChar) {
            result += decSep + (fractionStr ?? "")
        }

        if result != newValue {
            text = result
        }
    }
}
