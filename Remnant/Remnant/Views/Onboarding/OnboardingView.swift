import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var hasCompletedOnboarding: Bool

    @State private var step = 0
    @State private var accountName = ""
    @State private var accountBalance: Decimal = 0
    @State private var accountType: AccountType = .checking
    @State private var iconBounce = false
    @State private var accountCreated = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: Spacing.sm) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.Theme.accent : Color.Theme.surfaceElevated)
                        .frame(width: i == step ? 24 : 8, height: 8)
                        .animation(.spring(duration: 0.4), value: step)
                }
            }
            .padding(.top, Spacing.xl)

            Spacer()

            // Step content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: accountStep
                case 2: readyStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Navigation
            VStack(spacing: Spacing.md) {
                Button {
                    advanceStep()
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .disabled(step == 1 && accountName.isEmpty)

                if step > 0 {
                    Button("Back") {
                        withAnimation(.spring(duration: 0.4)) { step -= 1 }
                    }
                    .foregroundStyle(Color.Theme.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.Theme.background)
        .animation(.spring(duration: 0.4), value: step)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Spacing.xl) {
            // Animated icon cluster
            ZStack {
                Circle()
                    .fill(Color.Theme.accent.opacity(0.1))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(Color.Theme.accent.opacity(0.05))
                    .frame(width: 180, height: 180)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.Theme.accent)
                    .symbolEffect(.bounce, value: iconBounce)
            }
            .onAppear { iconBounce.toggle() }

            VStack(spacing: Spacing.sm) {
                Text("Remnant")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text("Know what remains.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.Theme.accent)
            }

            // Feature pills
            VStack(spacing: Spacing.sm) {
                featurePill(icon: "list.bullet.rectangle", text: "Track every bill & subscription")
                featurePill(icon: "target", text: "Plan payments before committing")
                featurePill(icon: "chart.bar.fill", text: "See where your money goes")
            }
            .padding(.top, Spacing.md)
        }
    }

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.Theme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: 320)
    }

    private var accountStep: some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.Theme.info.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "building.columns.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.Theme.info)
            }

            VStack(spacing: Spacing.sm) {
                Text("Add Your Account")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text("Start with your primary checking account.\nYou can add more later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.md) {
                TextField("Account Name (e.g. Chase Checking)", text: $accountName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, Spacing.xl)

                Picker("Type", selection: $accountType) {
                    ForEach(AccountType.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.xl)

                CurrencyField(title: "Current Balance", amount: $accountBalance)
                    .padding(.horizontal, Spacing.xl)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.Theme.positive.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.Theme.positive)
                    .symbolEffect(.bounce, value: step == 2)
            }

            VStack(spacing: Spacing.sm) {
                Text("You're All Set")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text("Start adding bills and tracking payments.\nRemnant will handle the math.")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            // Quick stats preview
            HStack(spacing: Spacing.lg) {
                miniStat(title: "Balance", value: accountBalance.compactCurrencyFormatted, color: Color.Theme.info)
                miniStat(title: "Bills", value: "0", color: Color.Theme.accent)
                miniStat(title: "Paid", value: "$0", color: Color.Theme.positive)
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func miniStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.Theme.textTertiary)
        }
        .frame(width: 80)
        .padding(.vertical, Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Actions

    private var buttonTitle: String {
        switch step {
        case 0: "Get Started"
        case 1: "Continue"
        case 2: "Start Tracking"
        default: "Continue"
        }
    }

    private func advanceStep() {
        switch step {
        case 0:
            withAnimation(.spring(duration: 0.4)) { step = 1 }
        case 1:
            if !accountCreated {
                _ = environment.accountService.create(
                    name: accountName,
                    type: accountType,
                    balance: accountBalance
                )
                try? environment.accountService.save()
                accountCreated = true
            }
            withAnimation(.spring(duration: 0.4)) { step = 2 }
        case 2:
            hasCompletedOnboarding = true
        default:
            break
        }
    }
}
