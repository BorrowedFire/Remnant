import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let accountService: AccountService
    let billService: BillService
    let paymentService: PaymentService
    let incomeService: IncomeService
    let categoryService: CategoryService
    let reminderService: ReminderService
    let subscriptionService: SubscriptionService
    let exportService: ExportService

    private static var _shared: AppEnvironment?

    static func production(modelContext: ModelContext) -> AppEnvironment {
        if let shared = _shared { return shared }
        let env = AppEnvironment(modelContext: modelContext)
        _shared = env
        return env
    }

    static func preview() -> AppEnvironment {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self,
            configurations: config
        )
        return AppEnvironment(modelContext: container.mainContext)
    }

    init(modelContext: ModelContext) {
        let accountService = AccountService(modelContext: modelContext)
        self.accountService = accountService
        self.billService = BillService(modelContext: modelContext)
        self.paymentService = PaymentService(modelContext: modelContext, accountService: accountService)
        self.incomeService = IncomeService(modelContext: modelContext, accountService: accountService)
        self.categoryService = CategoryService(modelContext: modelContext)
        self.reminderService = ReminderService()
        self.subscriptionService = SubscriptionService()
        self.exportService = ExportService(modelContext: modelContext)
    }
}
