import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var showingAddAccount = false
    @State private var showingSubscription = false
    @State private var showingIncome = false
    @State private var showingCategories = false
    @State private var showingAccountLimitAlert = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var exportYear: Int = Calendar.current.component(.year, from: Date())

    private var isPremium: Bool { environment.subscriptionService.isPremium }

    var body: some View {
        NavigationStack {
            List {
                Section("Accounts") {
                    ForEach(accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                    .font(.body.weight(.medium))
                                Text(account.type.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(Color.Theme.textTertiary)
                            }
                            Spacer()
                            Text(account.currentBalance.currencyFormatted)
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.Theme.textPrimary)
                        }
                    }

                    Button("Add Account", systemImage: "plus.circle") {
                        if environment.subscriptionService.canAddAccount(currentCount: accounts.count) {
                            showingAddAccount = true
                        } else {
                            showingAccountLimitAlert = true
                        }
                    }
                }

                Section("Manage") {
                    Button("Income Sources", systemImage: "building.2") {
                        showingIncome = true
                    }

                    if isPremium {
                        Button("Categories", systemImage: "tag") {
                            showingCategories = true
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Label("Custom Categories", systemImage: "tag")
                                Spacer()
                                Label("Remnant+", systemImage: "star.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.Theme.premium)
                            }
                        }
                    }
                }

                Section("Export") {
                    if isPremium {
                        Picker("Year", selection: $exportYear) {
                            let currentYear = Calendar.current.component(.year, from: Date())
                            ForEach((currentYear - 5)...currentYear, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }

                        Button("Export CSV", systemImage: "square.and.arrow.up") {
                            exportCSV()
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                                Spacer()
                                Label("Remnant+", systemImage: "star.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.Theme.premium)
                            }
                        }
                    }
                }

                Section("Subscription") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(environment.subscriptionService.isPremium ? "Remnant+" : "Free")
                            .foregroundStyle(
                                environment.subscriptionService.isPremium
                                    ? Color.Theme.premium
                                    : Color.Theme.textTertiary
                            )
                    }

                    if !environment.subscriptionService.isPremium {
                        Button("Upgrade to Remnant+", systemImage: "star.fill") {
                            showingSubscription = true
                        }
                        .foregroundStyle(Color.Theme.premium)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Color.Theme.textTertiary)
                    }
                    Link("Privacy Policy", destination: URL(string: "https://borrowedfire.com/remnant/privacy")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .sheet(isPresented: $showingIncome) {
                IncomeListView()
            }
            .sheet(isPresented: $showingCategories) {
                CategoriesView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Account Limit Reached", isPresented: $showingAccountLimitAlert) {
                Button("Upgrade") { showingSubscription = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Free accounts are limited to \(SubscriptionService.freeAccountLimit) account. Upgrade to Remnant+ for unlimited accounts.")
            }
        }
    }
    private func exportCSV() {
        do {
            exportURL = try environment.exportService.exportToCSV(year: exportYear)
            showingExportSheet = true
        } catch {
            // Silently fail — could add error state if needed
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Add Account

struct AddAccountView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var balance: Decimal = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    CurrencyField(title: "Current Balance", amount: $balance)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = environment.accountService.create(
                            name: name, type: type, balance: balance
                        )
                        try? environment.accountService.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
