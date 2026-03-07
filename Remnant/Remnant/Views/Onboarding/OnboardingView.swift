import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var hasCompletedOnboarding: Bool

    @State private var step = 0
    @State private var accountName = ""
    @State private var accountBalance: Decimal = 0
    @State private var accountType: AccountType = .checking
    @State private var iconBounce = false
    @State private var pulsing = false
    @State private var accountCreated = false
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"

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
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: CornerRadius.medium))
                .tint(Color.Theme.accent)
                .shadow(color: Color.Theme.accent.opacity(0.25), radius: 10, y: 4)
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
                    .fill(Color.Theme.accent.opacity(0.05))
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulsing ? 1.15 : 0.95)
                    .opacity(pulsing ? 0.0 : 0.4)

                Circle()
                    .fill(Color.Theme.accent.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulsing ? 1.1 : 0.97)
                    .opacity(pulsing ? 0.1 : 0.6)

                Circle()
                    .fill(Color.Theme.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsing ? 1.05 : 1.0)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.Theme.accent)
                    .symbolEffect(.bounce, value: iconBounce)
            }
            .onAppear {
                iconBounce.toggle()
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }

            VStack(spacing: Spacing.sm) {
                Text("Remnant")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text("Know What Remains.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.Theme.accent)
            }

            // Feature pills
            VStack(spacing: Spacing.sm) {
                featurePill(icon: "lock.shield.fill", text: "Your data stays on your device")
                featurePill(icon: "list.bullet.rectangle", text: "Track every bill & subscription")
                featurePill(icon: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90", text: "Record payments, track your balance")
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
        }
        .padding(.vertical, Spacing.sm)
    }

    private var accountStep: some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.Theme.accent.opacity(0.05))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulsing ? 1.15 : 0.95)
                    .opacity(pulsing ? 0.0 : 0.4)

                Circle()
                    .fill(Color.Theme.accent.opacity(0.08))
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulsing ? 1.1 : 0.97)
                    .opacity(pulsing ? 0.1 : 0.6)

                Circle()
                    .fill(Color.Theme.accent.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulsing ? 1.05 : 1.0)

                Image(systemName: "building.columns.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.Theme.accent)
            }

            VStack(spacing: Spacing.sm) {
                Text("Add Your Account")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.Theme.textPrimary)

                Text("Start with your primary account.\nYou can add more later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.md) {
                Picker("Currency", selection: $currencyCode) {
                    ForEach(CurrencyOption.popular) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, Spacing.xl)

                TextField("Account Name (e.g. Chase Checking)", text: $accountName)
                    .multilineTextAlignment(.center)
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
                    .fill(Color.Theme.accent.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.Theme.accent)
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

            // Balance confirmation
            VStack(spacing: Spacing.xs) {
                Text(accountBalance.currencyFormatted)
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.Theme.accent)
                Text(accountName)
                    .font(.subheadline)
                    .foregroundStyle(Color.Theme.textPrimary)
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xl)
            .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.medium))

            // iCloud sync note
            HStack(spacing: Spacing.xs) {
                Image(systemName: "icloud.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.Theme.accent)
                Text("Your data syncs automatically via ")
                    .font(.caption)
                    .foregroundStyle(Color.Theme.textPrimary)
                + Text("iCloud")
                    .font(.caption)
                    .foregroundStyle(Color.Theme.accent)
            }
            .padding(.top, Spacing.md)
        }
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
                // Check if account already exists (crash recovery — prevents duplicates)
                let existingAccounts = (try? environment.accountService.fetchAll()) ?? []
                if existingAccounts.isEmpty {
                    _ = environment.accountService.create(
                        name: accountName,
                        type: accountType,
                        balance: accountBalance
                    )
                    try? environment.accountService.save()
                }
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
