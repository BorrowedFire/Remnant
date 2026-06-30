import Foundation

@MainActor
final class RemnantAppState: ObservableObject {
    @Published var selectedSection: ExpenseSection = .dashboard
    @Published var presentedSheet: RemnantSheetDestination?
    @Published var commandRequest: RemnantCommandRequest?

    func showNewExpense() {
        selectedSection = .expenses
        presentedSheet = .newExpense
    }

    func select(_ section: ExpenseSection) {
        selectedSection = section
    }

    func request(_ kind: RemnantCommandRequest.Kind) {
        commandRequest = RemnantCommandRequest(kind: kind)
    }
}

enum RemnantSheetDestination: Identifiable {
    case newExpense

    var id: String {
        switch self {
        case .newExpense: "newExpense"
        }
    }
}

struct RemnantCommandRequest: Equatable, Identifiable {
    enum Kind: Equatable {
        case focusSearch
        case importFiles
        case exportReport
    }

    let id = UUID()
    let kind: Kind
}
