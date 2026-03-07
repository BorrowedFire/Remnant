import AppIntents
import SwiftData

struct RecordPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Payment"
    static var description = IntentDescription("Record a bill payment in Remnant.")
    static var openAppWhenRun = false

    @Parameter(title: "Bill")
    var bill: BillEntity

    @Parameter(title: "Amount", controlStyle: .field)
    var amount: Double?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try ModelContext(sharedModelContainer())

        let billID = bill.id
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.id == billID })
        guard let billModel = try context.fetch(descriptor).first else {
            return .result(dialog: "Bill not found.")
        }

        let paymentAmount: Decimal
        if let provided = amount {
            paymentAmount = Decimal(provided)
        } else if let expected = billModel.expectedAmount {
            paymentAmount = expected
        } else {
            return .result(dialog: "No amount specified and bill has no expected amount.")
        }

        // Get primary account
        let accountDescriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])
        let account = try context.fetch(accountDescriptor).first

        let payment = Payment(amount: paymentAmount, bill: billModel, account: account)
        context.insert(payment)

        if let account {
            account.currentBalance -= paymentAmount
            account.updatedAt = Date()
        }

        try context.save()

        return .result(dialog: "Recorded \(paymentAmount.currencyFormatted) payment for \(billModel.name).")
    }
}
