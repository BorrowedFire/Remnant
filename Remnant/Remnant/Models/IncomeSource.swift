import Foundation
import SwiftData

enum PayFrequency: String, Codable, CaseIterable {
    case weekly
    case biweekly
    case semimonthly
    case monthly

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .semimonthly: "Semimonthly"
        case .monthly: "Monthly"
        }
    }
}

@Model
final class IncomeSource {
    var id: UUID = UUID()
    var name: String = ""
    var frequency: PayFrequency = PayFrequency.biweekly
    var expectedAmount: Decimal?
    var isActive: Bool = true
    var createdAt: Date = Date()

    /// A known paycheck date used to compute future pay dates.
    var anchorDate: Date?
    var reminderEnabled: Bool = false
    var reminderDaysBefore: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.source)
    var entries: [IncomeEntry]?

    init(
        name: String,
        frequency: PayFrequency = .biweekly,
        expectedAmount: Decimal? = nil,
        anchorDate: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.frequency = frequency
        self.expectedAmount = expectedAmount
        self.isActive = true
        self.createdAt = Date()
        self.anchorDate = anchorDate
        self.reminderEnabled = false
        self.reminderDaysBefore = 1
        self.entries = []
    }

    /// Next expected pay date from today, computed from the anchor date and frequency.
    var nextPayDate: Date? {
        guard let anchor = anchorDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let anchorDay = calendar.startOfDay(for: anchor)

        switch frequency {
        case .weekly:
            let days = calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0
            let remainder = ((days % 7) + 7) % 7
            let daysUntilNext = remainder == 0 ? 0 : 7 - remainder
            return calendar.date(byAdding: .day, value: daysUntilNext, to: today)

        case .biweekly:
            let days = calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0
            let remainder = ((days % 14) + 14) % 14
            let daysUntilNext = remainder == 0 ? 0 : 14 - remainder
            return calendar.date(byAdding: .day, value: daysUntilNext, to: today)

        case .semimonthly:
            // Pay on the 1st and 15th (or the anchor day and anchor day + 15)
            let anchorDay1 = calendar.component(.day, from: anchor)
            let anchorDay2 = anchorDay1 <= 15 ? anchorDay1 + 15 : anchorDay1 - 15
            let payDays = [anchorDay1, anchorDay2].sorted()

            var components = calendar.dateComponents([.year, .month], from: today)

            for payDay in payDays {
                components.day = payDay
                if let candidate = calendar.date(from: components), candidate >= today {
                    return candidate
                }
            }
            // Next month's first pay day
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) {
                var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                nextComponents.day = payDays[0]
                return calendar.date(from: nextComponents)
            }
            return nil

        case .monthly:
            let payDay = calendar.component(.day, from: anchor)
            var components = calendar.dateComponents([.year, .month], from: today)
            let maxDay = calendar.range(of: .day, in: .month, for: today)?.count ?? 28
            components.day = min(payDay, maxDay)
            if let candidate = calendar.date(from: components), candidate >= today {
                return candidate
            }
            return calendar.date(byAdding: .month, value: 1, to: calendar.date(from: components) ?? today)
        }
    }
}
