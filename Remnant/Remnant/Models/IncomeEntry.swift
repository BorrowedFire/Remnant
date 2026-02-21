import Foundation
import SwiftData

@Model
final class IncomeEntry {
    var id: UUID
    var amount: Decimal
    var date: Date
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
