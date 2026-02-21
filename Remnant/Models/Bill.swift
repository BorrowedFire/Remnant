import Foundation
import SwiftData

enum BillFrequency: String, Codable, CaseIterable {
    case monthly
    case annual
    case biweekly
    case weekly
    case quarterly
    case oneTime

    var displayName: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        case .biweekly: "Biweekly"
        case .weekly: "Weekly"
        case .quarterly: "Quarterly"
        case .oneTime: "One Time"
        }
    }
}

@Model
final class Bill {
    var id: UUID = UUID()
    var name: String = ""
    var expectedAmount: Decimal?
    var dueDay: Int?
    var dueDate: Date?
    var frequency: BillFrequency = BillFrequency.monthly
    var isActive: Bool = true
    var reminderEnabled: Bool = false
    var reminderDaysBefore: Int = 1
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \Payment.bill)
    var payments: [Payment]?

    init(
        name: String,
        expectedAmount: Decimal? = nil,
        dueDay: Int? = nil,
        dueDate: Date? = nil,
        frequency: BillFrequency = .monthly,
        category: Category? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.expectedAmount = expectedAmount
        self.dueDay = dueDay
        self.dueDate = dueDate
        self.frequency = frequency
        self.isActive = true
        self.reminderEnabled = false
        self.reminderDaysBefore = 1
        self.sortOrder = 0
        self.createdAt = Date()
        self.category = category
        self.payments = []
    }

    /// Next due date from today
    var nextDueDate: Date? {
        let calendar = Calendar.current
        let today = Date()

        switch frequency {
        case .annual:
            guard let dueDate else { return nil }
            let components = calendar.dateComponents([.month, .day], from: dueDate)
            var next = calendar.nextDate(after: today, matching: components, matchingPolicy: .nextTime)
            if let n = next, n < today {
                next = calendar.date(byAdding: .year, value: 1, to: n)
            }
            return next

        case .monthly, .biweekly, .weekly, .quarterly:
            guard let dueDay else { return nil }
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = min(dueDay, calendar.range(of: .day, in: .month, for: today)?.count ?? 28)
            guard let candidate = calendar.date(from: components) else { return nil }
            return candidate >= today
                ? candidate
                : calendar.date(byAdding: .month, value: 1, to: candidate)

        case .oneTime:
            return dueDate
        }
    }

    /// Total paid this calendar year
    func totalPaidThisYear(in year: Int? = nil) -> Decimal {
        let calendar = Calendar.current
        let targetYear = year ?? calendar.component(.year, from: Date())
        return (payments ?? [])
            .filter { !$0.isPlanned && calendar.component(.year, from: $0.date) == targetYear }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total paid in a specific month
    func totalPaid(month: Int, year: Int) -> Decimal {
        let calendar = Calendar.current
        return (payments ?? [])
            .filter {
                !$0.isPlanned
                && calendar.component(.year, from: $0.date) == year
                && calendar.component(.month, from: $0.date) == month
            }
            .reduce(0) { $0 + $1.amount }
    }
}
