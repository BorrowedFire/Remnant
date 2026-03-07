import SwiftUI

struct PremiumGateView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingSubscription = false

    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.Theme.premium)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(description). Premium feature.")

            Button {
                showingSubscription = true
            } label: {
                Label("Upgrade to Remnant+", systemImage: "star.fill")
                    .font(.headline)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: CornerRadius.medium))
            .tint(Color.Theme.accent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.background)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }
}
