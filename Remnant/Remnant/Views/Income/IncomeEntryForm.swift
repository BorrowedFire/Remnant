import SwiftUI
import SwiftData

struct IncomeEntryForm: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var sources: [IncomeSource] = []
    @State private var selectedSource: IncomeSource?
    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    if sources.isEmpty {
                        Text("No income sources. Add one first.")
                            .foregroundStyle(Color.Theme.textTertiary)
                    } else {
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
                }

                Section("Details") {
                    CurrencyField(title: "Amount", amount: $amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
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
            }
        }
    }

    private func saveEntry() {
        guard let source = selectedSource else { return }
        _ = environment.incomeService.recordIncome(
            source: source,
            amount: amount,
            date: date,
            account: accounts.first,
            note: note.isEmpty ? nil : note
        )
        try? environment.incomeService.save()
        dismiss()
    }
}
