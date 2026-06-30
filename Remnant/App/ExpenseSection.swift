import SwiftUI

enum ExpenseSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard = "Dashboard"
    case review = "Review Inbox"
    case expenses = "Expenses"
    case imports = "Imports"
    case reports = "Reports"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.xaxis"
        case .review: "tray.full"
        case .expenses: "list.bullet.rectangle"
        case .imports: "square.and.arrow.down"
        case .reports: "doc.text.magnifyingglass"
        }
    }

    var commandKey: KeyEquivalent {
        switch self {
        case .dashboard: "1"
        case .review: "2"
        case .expenses: "3"
        case .imports: "4"
        case .reports: "5"
        }
    }
}
