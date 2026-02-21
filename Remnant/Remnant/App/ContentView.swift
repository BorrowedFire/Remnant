import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
    }
}

// MARK: - Adaptive Navigation

enum AppTab: Hashable {
    case dashboard, bills, plan, history
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.fill", value: .dashboard) {
                DashboardView()
            }

            Tab("Bills", systemImage: "list.bullet.rectangle.fill", value: .bills) {
                BillListView()
            }

            Tab("Plan", systemImage: "target", value: .plan) {
                PlanningView()
            }

            Tab("History", systemImage: "calendar", value: .history) {
                MonthlyView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.Theme.accent)
    }
}
