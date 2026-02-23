import AppIntents

struct RemnantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordPaymentIntent(),
            phrases: [
                "Record a payment in \(.applicationName)",
                "Pay a bill in \(.applicationName)"
            ],
            shortTitle: "Record Payment",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: RecordIncomeIntent(),
            phrases: [
                "Record income in \(.applicationName)",
                "Add income to \(.applicationName)"
            ],
            shortTitle: "Record Income",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "Check my balance in \(.applicationName)",
                "What's my balance in \(.applicationName)"
            ],
            shortTitle: "Check Balance",
            systemImageName: "banknote"
        )
    }
}
