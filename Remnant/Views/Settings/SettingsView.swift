import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingSubscription = false
    @State private var showingIncome = false
    @State private var showingCategories = false
    @State private var showingAccountLimitAlert = false
    @State private var showingExportSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var accountToDelete: Account?
    @State private var showingCurrencyWarning = false
    @State private var pendingCurrencyCode: String?
    @State private var exportURL: URL?
    @State private var exportYear: Int = Calendar.current.component(.year, from: Date())
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"

    private var isPremium: Bool { environment.subscriptionService.isPremium }

    var body: some View {
        NavigationStack {
            List {
                Section("Accounts") {
                    ForEach(accounts) { account in
                        Button {
                            editingAccount = account
                        } label: {
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
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            accountToDelete = accounts[index]
                            showingDeleteConfirmation = true
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
                    Picker(selection: Binding(
                        get: { currencyCode },
                        set: { newValue in
                            if newValue != currencyCode {
                                pendingCurrencyCode = newValue
                                showingCurrencyWarning = true
                            }
                        }
                    )) {
                        ForEach(CurrencyOption.popular) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    } label: {
                        Label("Currency", systemImage: "banknote")
                    }

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

                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud.fill")
                        Spacer()
                        if FileManager.default.ubiquityIdentityToken != nil {
                            Text("Active")
                                .foregroundStyle(Color.Theme.positive)
                        } else {
                            Text("Off")
                                .foregroundStyle(Color.Theme.textTertiary)
                        }
                    }
                } header: {
                    Text("Data & Sync")
                } footer: {
                    if FileManager.default.ubiquityIdentityToken != nil {
                        Text("Your data syncs automatically across all devices signed into your iCloud account.")
                    } else {
                        Text("Sign in to iCloud in Settings to sync data across devices.")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Remnant", systemImage: "info.circle")
                    }
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
            .sheet(item: $editingAccount) { account in
                EditAccountView(account: account)
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
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let account = accountToDelete {
                        environment.accountService.delete(account)
                        try? environment.accountService.save()
                    }
                    accountToDelete = nil
                }
                Button("Cancel", role: .cancel) { accountToDelete = nil }
            } message: {
                Text("This will permanently delete \"\(accountToDelete?.name ?? "")\" and all its payment history. This cannot be undone.")
            }
            .alert("Change Currency?", isPresented: $showingCurrencyWarning) {
                Button("Change") {
                    if let code = pendingCurrencyCode {
                        currencyCode = code
                    }
                    pendingCurrencyCode = nil
                }
                Button("Cancel", role: .cancel) { pendingCurrencyCode = nil }
            } message: {
                Text("This changes the display currency only. Existing amounts will not be converted.")
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

struct EditAccountView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let account: Account
    @State private var name: String = ""
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
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        account.name = trimmed
                        account.type = type
                        account.currentBalance = balance
                        account.updatedAt = Date()
                        try? environment.accountService.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = account.name
                type = account.type
                balance = account.currentBalance
            }
        }
    }
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
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        _ = environment.accountService.create(
                            name: trimmed, type: type, balance: balance
                        )
                        try? environment.accountService.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
