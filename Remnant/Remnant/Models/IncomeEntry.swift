import Foundation
import SwiftData

@Model
final class IncomeEntry {
    var id: UUID = UUID()
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String?

    var source: IncomeSource?
    var account: Account?

    init(
        amount: Decimal,
        date: Date = Date(),
        note: String? = nil,
        source: IncomeSource? = nil,
        account: Account? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
        self.source = source
        self.account = account
    }
}
