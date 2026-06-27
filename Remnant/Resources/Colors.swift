import SwiftUI

// MARK: - Color Theme
// Palette: Soft Pistachio #DEF4C6, Mint Bloom #73E2A7,
//          Forest Jade #1C7C54, Deep Evergreen #1B512D

extension Color {
    enum Theme {
        // Primary brand
        static let accent = Color("AccentColor")
        static let premium = Color(hex: "FFD60A")

        // Palette
        static let softPistachio = Color(hex: "DEF4C6")
        static let mintBloom = Color(hex: "73E2A7")
        static let forestJade = Color(hex: "1C7C54")
        static let deepEvergreen = Color(hex: "1B512D")

        // Surfaces — dark first, green-tinted
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceElevated = Color(nsColor: .underPageBackgroundColor)

        // Text
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        // Semantic
        static let positive = Color(hex: "73E2A7")  // Mint Bloom
        static let negative = Color(hex: "FF453A")
        static let warning = Color(hex: "FFD60A")
        static let info = Color(hex: "73E2A7")       // Mint Bloom (was blue)

        // Category colors
        static let creditCards = Color(hex: "5E5CE6")
        static let loans = Color(hex: "FF6B6B")
        static let bills = Color(hex: "1C7C54")       // Forest Jade
        static let subscriptionsMonthly = Color(hex: "73E2A7")  // Mint Bloom
        static let subscriptionsAnnual = Color(hex: "FFD60A")
        static let savings = Color(hex: "DEF4C6")     // Soft Pistachio
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
