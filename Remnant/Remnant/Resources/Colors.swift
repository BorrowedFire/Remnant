import SwiftUI

// MARK: - Color Theme

extension Color {
    enum Theme {
        // Primary brand
        static let accent = Color("AccentColor")
        static let premium = Color(hex: "FFD60A")

        // Surfaces — dark first
        static let background = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
                : UIColor.systemBackground
        })

        static let surface = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
                : UIColor.secondarySystemBackground
        })

        static let surfaceElevated = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                : UIColor.tertiarySystemBackground
        })

        // Text
        static let textPrimary = Color(UIColor.label)
        static let textSecondary = Color(UIColor.secondaryLabel)
        static let textTertiary = Color(UIColor.tertiaryLabel)

        // Semantic
        static let positive = Color(hex: "30D158")
        static let negative = Color(hex: "FF453A")
        static let warning = Color(hex: "FFD60A")
        static let info = Color(hex: "0A84FF")

        // Category colors
        static let creditCards = Color(hex: "5E5CE6")
        static let loans = Color(hex: "FF6B6B")
        static let bills = Color(hex: "30D158")
        static let subscriptionsMonthly = Color(hex: "0A84FF")
        static let subscriptionsAnnual = Color(hex: "FFD60A")
        static let savings = Color(hex: "64D2FF")
    }
}

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
