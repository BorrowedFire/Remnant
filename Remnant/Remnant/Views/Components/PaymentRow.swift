import SwiftUI

struct PaymentRow: View {
    let payment: Payment

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.bill?.name ?? "Payment")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text(payment.date.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textTertiary)
            }

            Spacer()

            Text(payment.amount.currencyFormatted)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.Theme.negative)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(payment.bill?.name ?? "Payment"), \(payment.amount.currencyFormatted), \(payment.date.shortFormatted)")
    }
}
