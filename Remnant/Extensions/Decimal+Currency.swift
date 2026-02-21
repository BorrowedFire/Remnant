import Foundation

// MARK: - Currency Options

struct CurrencyOption: Identifiable, Hashable {
    let id: String // currency code (e.g., "USD")
    let country: String
    let flag: String

    var symbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = id
        formatter.locale = Locale.current
        return formatter.currencySymbol
    }

    var displayName: String {
        "\(flag) \(country) (\(symbol))"
    }

    static let popular: [CurrencyOption] = [
        CurrencyOption(id: "USD", country: "United States", flag: "🇺🇸"),
        CurrencyOption(id: "EUR", country: "Eurozone", flag: "🇪🇺"),
        CurrencyOption(id: "GBP", country: "United Kingdom", flag: "🇬🇧"),
        CurrencyOption(id: "CAD", country: "Canada", flag: "🇨🇦"),
        CurrencyOption(id: "AUD", country: "Australia", flag: "🇦🇺"),
        CurrencyOption(id: "JPY", country: "Japan", flag: "🇯🇵"),
        CurrencyOption(id: "CHF", country: "Switzerland", flag: "🇨🇭"),
        CurrencyOption(id: "INR", country: "India", flag: "🇮🇳"),
        CurrencyOption(id: "MXN", country: "Mexico", flag: "🇲🇽"),
        CurrencyOption(id: "BRL", country: "Brazil", flag: "🇧🇷"),
        CurrencyOption(id: "KRW", country: "South Korea", flag: "🇰🇷"),
        CurrencyOption(id: "CNY", country: "China", flag: "🇨🇳"),
        CurrencyOption(id: "SEK", country: "Sweden", flag: "🇸🇪"),
        CurrencyOption(id: "NZD", country: "New Zealand", flag: "🇳🇿"),
        CurrencyOption(id: "SGD", country: "Singapore", flag: "🇸🇬"),
        CurrencyOption(id: "NGN", country: "Nigeria", flag: "🇳🇬"),
        CurrencyOption(id: "ZAR", country: "South Africa", flag: "🇿🇦"),
        CurrencyOption(id: "AED", country: "UAE", flag: "🇦🇪"),
        CurrencyOption(id: "PHP", country: "Philippines", flag: "🇵🇭"),
        CurrencyOption(id: "PLN", country: "Poland", flag: "🇵🇱"),
        CurrencyOption(id: "THB", country: "Thailand", flag: "🇹🇭"),
        CurrencyOption(id: "TRY", country: "Türkiye", flag: "🇹🇷"),
        CurrencyOption(id: "SAR", country: "Saudi Arabia", flag: "🇸🇦"),
        CurrencyOption(id: "COP", country: "Colombia", flag: "🇨🇴"),
        CurrencyOption(id: "EGP", country: "Egypt", flag: "🇪🇬"),
    ]
}

// MARK: - Currency Formatting

extension Decimal {
    static var userCurrencyCode: String {
        UserDefaults.standard.string(forKey: "currencyCode")
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    static var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = userCurrencyCode
        formatter.locale = Locale.current
        return formatter.currencySymbol
    }

    static var currencyDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Self.userCurrencyCode
        formatter.locale = Locale.current
        return formatter.string(from: self as NSDecimalNumber) ?? "\(Self.currencySymbol)0.00"
    }

    var compactCurrencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Self.userCurrencyCode
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "\(Self.currencySymbol)0"
    }
}
