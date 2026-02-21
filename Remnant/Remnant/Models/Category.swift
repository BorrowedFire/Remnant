import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var isDefault: Bool
    var sortOrder: Int

    @Relationship(deleteRule: .deny, inverse: \Bill.category)
    var bills: [Bill]

    init(
        name: String,
        icon: String,
        colorHex: String,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.bills = []
    }

    static let defaults: [(name: String, icon: String, colorHex: String)] = [
        ("Credit Cards", "creditcard.fill", "5E5CE6"),
        ("Loans", "building.columns.fill", "FF6B6B"),
        ("Monthly Bills", "doc.text.fill", "30D158"),
        ("Subscriptions (Monthly)", "arrow.clockwise", "0A84FF"),
        ("Subscriptions (Annual)", "calendar.badge.clock", "FFD60A"),
        ("Savings", "banknote.fill", "64D2FF"),
        ("Other", "ellipsis.circle.fill", "AC8E68"),
    ]
}
