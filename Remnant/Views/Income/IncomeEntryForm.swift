import SwiftUI
import SwiftData

struct IncomeEntryForm: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var sources: [IncomeSource] = []
    @State private var selectedSource: IncomeSource?
    @State private var selectedAccount: Account?
    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var note: String = ""
    @State private var showingAddSource = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    if !sources.isEmpty {
                        Picker("Income Source", selection: $selectedSource) {
                            Text("Select source").tag(nil as IncomeSource?)
                            ForEach(sources) { source in
                                Text(source.name).tag(source as IncomeSource?)
                            }
                        }
                        .onChange(of: selectedSource) { _, source in
                            if let expected = source?.expectedAmount, amount == 0 {
                                amount = expected
                            }
                        }
                    }

                    Button {
                        showingAddSource = true
                    } label: {
                        Label("Add Income Source", systemImage: "plus.circle.fill")
                    }
                }

                Section("Details") {
                    CurrencyField(title: "Amount", amount: $amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }

                if accounts.count > 1 {
                    Section("Account") {
                        Picker("Account", selection: $selectedAccount) {
                            ForEach(accounts) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Record Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(selectedSource == nil || amount <= 0)
                        .fontWeight(.semibold)
                }
            }
            .task {
                sources = (try? environment.incomeService.fetchSources()) ?? []
                selectedAccount = accounts.first
            }
            .sheet(isPresented: $showingAddSource) {
                IncomeSourceForm()
            }
            .onChange(of: showingAddSource) { _, isShowing in
                if !isShowing {
                    sources = (try? environment.incomeService.fetchSources()) ?? []
                    if selectedSource == nil, let newest = sources.last {
                        selectedSource = newest
                    }
                }
            }
        }
    }

    private func saveEntry() {
        guard let source = selectedSource else { return }
        _ = environment.incomeService.recordIncome(
            source: source,
            amount: amount,
            date: date,
            account: selectedAccount ?? accounts.first,
            note: note.isEmpty ? nil : note
        )
        try? environment.incomeService.save()
        dismiss()
    }
}
