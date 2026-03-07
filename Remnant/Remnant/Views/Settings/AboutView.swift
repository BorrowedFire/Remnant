import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Hero
                VStack(spacing: Spacing.md) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.Theme.accent)
                        .padding(.top, Spacing.xxl)

                    Text("Remnant")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.Theme.textPrimary)

                    Text("Know What Remains.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.Theme.accent)

                    Text("v\(appVersion) (\(buildNumber))")
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.Theme.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.Theme.surfaceElevated, in: Capsule())
                }

                // Links
                VStack(spacing: 0) {
                    if let privacyURL = URL(string: "https://borrowedfire.com/privacy-policy/") {
                        Link(destination: privacyURL) {
                            HStack {
                                Label("Privacy Policy", systemImage: "hand.raised.fill")
                                    .foregroundStyle(Color.Theme.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.Theme.accent)
                            }
                            .padding(Spacing.lg)
                        }
                    }

                    Divider()
                        .padding(.leading, Spacing.lg)

                    if let termsURL = URL(string: "https://borrowedfire.com/terms-of-service/") {
                        Link(destination: termsURL) {
                            HStack {
                                Label("Terms of Service", systemImage: "doc.text.fill")
                                    .foregroundStyle(Color.Theme.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.Theme.accent)
                            }
                            .padding(Spacing.lg)
                        }
                    }
                }
                .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: CornerRadius.large))
                .padding(.horizontal, Spacing.lg)

                // Footer
                VStack(spacing: Spacing.xs) {
                    Text("Borrowed Fire LLC")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.Theme.textSecondary)
                }
                .padding(.top, Spacing.lg)
            }
        }
        .background(Color.Theme.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
