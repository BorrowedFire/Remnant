import SwiftUI
import SwiftData

@main
struct RemnantApp: App {
    let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let schema = Schema([
            Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.borrowedfire.remnant")
        )
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.container = container
        self.environment = AppEnvironment.production(modelContext: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .task {
                    try? environment.categoryService.seedDefaultsIfNeeded()
                    await environment.subscriptionService.loadProducts()
                    await environment.subscriptionService.refreshEntitlements()
                    await environment.reminderService.checkAuthorizationStatus()
                }
        }
    }
}
