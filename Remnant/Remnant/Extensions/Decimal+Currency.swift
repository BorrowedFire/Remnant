import Foundation

extension Decimal {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    var compactCurrencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "$0"
    }
}
