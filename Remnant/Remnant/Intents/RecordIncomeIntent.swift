import AppIntents
import SwiftData

struct RecordIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Income"
    static var description = IntentDescription("Record income in Remnant.")
    static var openAppWhenRun = false

    @Parameter(title: "Source Name")
    var sourceName: String

    @Parameter(title: "Amount", controlStyle: .field)
    var amount: Double?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try ModelContext(sharedModelContainer())

        let descriptor = FetchDescriptor<IncomeSource>(predicate: #Predicate { $0.isActive })
        let sources = try context.fetch(descriptor)
        guard let source = sources.first(where: { $0.name.localizedStandardContains(sourceName) }) else {
            return .result(dialog: "Income source '\(sourceName)' not found.")
        }

        let incomeAmount: Decimal
        if let provided = amount {
            incomeAmount = Decimal(provided)
        } else if let expected = source.expectedAmount {
            incomeAmount = expected
        } else {
            return .result(dialog: "No amount specified and source has no expected amount.")
        }

        let accountDescriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])
        let account = try context.fetch(accountDescriptor).first

        let entry = IncomeEntry(amount: incomeAmount, source: source, account: account)
        context.insert(entry)

        if let account {
            account.currentBalance += incomeAmount
            account.updatedAt = Date()
        }

        try context.save()

        return .result(dialog: "Recorded \(incomeAmount.currencyFormatted) income from \(source.name).")
    }
}
