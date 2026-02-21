import Foundation
import SwiftData

@Model
final class Payment {
    var id: UUID
    var amount: Decimal
    var date: Date
    var note: String?
    var isPlanned: Bool

    var bill: Bill?
    var account: Account?

    init(
        amount: Decimal,
        date: Date = Date(),
        note: String? = nil,
        isPlanned: Bool = false,
        bill: Bill? = nil,
        account: Account? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
        self.isPlanned = isPlanned
        self.bill = bill
        self.account = account
    }
}
