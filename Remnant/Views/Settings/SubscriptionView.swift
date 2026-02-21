import SwiftUI

struct SubscriptionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Header
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.Theme.premium)

                        Text("Remnant+")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.Theme.textPrimary)

                        Text("Unlock the full power of Remnant")
                            .font(.subheadline)
                            .foregroundStyle(Color.Theme.textSecondary)
                    }
                    .padding(.top, Spacing.xl)

                    // Features
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        featureRow(icon: "target", text: "Planning Mode — simulate before you pay")
                        featureRow(icon: "calendar", text: "Year View — 12-month grid like your spreadsheet")
                        featureRow(icon: "chart.pie", text: "Analytics — category breakdowns & trends")
                        featureRow(icon: "bell", text: "Bill Reminders — never miss a due date")
                        featureRow(icon: "square.and.arrow.up", text: "CSV Export — back up your data anytime")
                        featureRow(icon: "infinity", text: "Unlimited bills & accounts")
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Products
                    VStack(spacing: Spacing.md) {
                        ForEach(environment.subscriptionService.products) { product in
                            Button {
                                Task {
                                    await environment.subscriptionService.purchase(product)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(Color.Theme.textTertiary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.headline.weight(.bold))
                                }
                                .padding(Spacing.lg)
                                .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: CornerRadius.large))
                                .foregroundStyle(Color.Theme.textPrimary)
                            }
                        }

                        Button("Restore Purchases") {
                            Task { await environment.subscriptionService.restorePurchases() }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.Theme.textSecondary)
                        .padding(.top, Spacing.sm)
                    }
                    .padding(.horizontal, Spacing.lg)

                    if let error = environment.subscriptionService.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.negative)
                    }
                }
            }
            .background(Color.Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.Theme.premium)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.Theme.textPrimary)
        }
    }
}
