import AppIntents
import SwiftData

struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Balance"
    static var description = IntentDescription("Check your account balance in Remnant.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try ModelContext(sharedModelContainer())
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])
        let accounts = try context.fetch(descriptor)

        guard let primary = accounts.first else {
            return .result(dialog: "No accounts set up in Remnant.")
        }

        return .result(dialog: "Your \(primary.name) balance is \(primary.currentBalance.currencyFormatted).")
    }
}
