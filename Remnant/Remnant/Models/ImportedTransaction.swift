import Foundation

/// A parsed transaction from an imported file. Not persisted — used only during the import flow.
struct ImportedTransaction: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let date: Date
    let type: TransactionType

    var matchedBill: Bill?
    var matchConfidence: Double = 0

    enum TransactionType {
        case debit
        case credit
    }
}
