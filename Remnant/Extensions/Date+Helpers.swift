import Foundation

extension Date {
    var shortFormatted: String {
        formatted(.dateTime.month(.abbreviated).day())
    }

    var mediumFormatted: String {
        formatted(.dateTime.month(.abbreviated).day().year())
    }

    var dayOfMonth: Int {
        Calendar.current.component(.day, from: self)
    }

    var month: Int {
        Calendar.current.component(.month, from: self)
    }

    var year: Int {
        Calendar.current.component(.year, from: self)
    }

    static var startOfCurrentMonth: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
    }

    func daysUntil() -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: self)).day ?? 0
    }
}
