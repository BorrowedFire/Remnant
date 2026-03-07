import SwiftUI
import SwiftData
import UserNotifications

@main
struct RemnantApp: App {
    let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let schema = Schema([
            Account.self, Category.self, IncomeSource.self,
            IncomeEntry.self, Bill.self, Payment.self
        ])

        let container: ModelContainer
        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.borrowedfire.remnant")
            )
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback to local-only store (simulator or missing CloudKit entitlement)
            do {
                let localConfig = ModelConfiguration(schema: schema)
                container = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

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
                    environment.reminderService.registerCategories()
                    UNUserNotificationCenter.current().delegate = environment.notificationActionHandler
                }
        }
    }
}
