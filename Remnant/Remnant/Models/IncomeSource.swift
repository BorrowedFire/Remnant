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
    var id: UUID
    var name: String
    var frequency: PayFrequency
    var expectedAmount: Decimal?
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.source)
    var entries: [IncomeEntry]

    init(
        name: String,
        frequency: PayFrequency = .biweekly,
        expectedAmount: Decimal? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.frequency = frequency
        self.expectedAmount = expectedAmount
        self.isActive = true
        self.createdAt = Date()
        self.entries = []
    }
}
