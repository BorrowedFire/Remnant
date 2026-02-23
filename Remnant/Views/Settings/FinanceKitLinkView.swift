import SwiftUI
import SwiftData

struct FinanceKitLinkView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let service = environment.financeKitService {
                    if !service.isAvailable {
                        Section {
                            Text("FinanceKit is not available on this device.")
                                .foregroundStyle(Color.Theme.textSecondary)
                        }
                    } else if !service.isAuthorized {
                        Section {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Connect your Apple Wallet accounts to automatically sync balances.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.Theme.textSecondary)
                                Text("Your data stays on this device. It never passes through our servers — or anyone else's.")
                                    .font(.caption)
                                    .foregroundStyle(Color.Theme.textTertiary)
                            }
                            Button("Connect Apple Wallet") {
                                Task {
                                    await service.requestAuthorization()
                                }
                            }
                            .foregroundStyle(Color.Theme.info)
                        }
                    } else {
                        Section("Linked Accounts") {
                            let linkedAccounts = accounts.filter { $0.financeKitAccountID != nil }
                            if linkedAccounts.isEmpty {
                                Text("No accounts linked yet.")
                                    .foregroundStyle(Color.Theme.textTertiary)
                            } else {
                                ForEach(linkedAccounts) { account in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(account.name)
                                                .font(.body.weight(.medium))
                                            Text("Auto-syncing balance")
                                                .font(.caption)
                                                .foregroundStyle(Color.Theme.positive)
                                        }
                                        Spacer()
                                        Text(account.currentBalance.currencyFormatted)
                                            .font(.body.weight(.semibold).monospacedDigit())
                                    }
                                }
                            }
                        }

                        Section {
                            Button("Sync Now") {
                                isLoading = true
                                Task {
                                    await service.syncLinkedBalances()
                                    isLoading = false
                                }
                            }
                            .disabled(isLoading)
                        }
                    }
                } else {
                    Section {
                        Text("FinanceKit is not available in this build.")
                            .foregroundStyle(Color.Theme.textSecondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(Color.Theme.negative)
                    }
                }
            }
            .background(Color.Theme.background)
            .navigationTitle("Connected Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
