import SwiftUI
import SwiftData

struct RecordPaymentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var selectedBill: Bill?
    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var note: String = ""
    @State private var bills: [Bill] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    Picker("Select Bill", selection: $selectedBill) {
                        Text("Select a bill").tag(nil as Bill?)
                        ForEach(bills) { bill in
                            Text(bill.name).tag(bill as Bill?)
                        }
                    }
                    .onChange(of: selectedBill) { _, bill in
                        if let expected = bill?.expectedAmount, amount == 0 {
                            amount = expected
                        }
                    }
                }

                Section("Payment Details") {
                    CurrencyField(title: "Amount", amount: $amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }

                if accounts.count > 1 {
                    Section("Account") {
                        Text(accounts.first?.name ?? "")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePayment() }
                        .disabled(selectedBill == nil || amount <= 0)
                        .fontWeight(.semibold)
                }
            }
            .task {
                bills = (try? environment.billService.fetchAll()) ?? []
            }
        }
    }

    private func savePayment() {
        guard let bill = selectedBill else { return }
        _ = environment.paymentService.recordPayment(
            bill: bill,
            amount: amount,
            date: date,
            account: accounts.first,
            note: note.isEmpty ? nil : note
        )
        try? environment.paymentService.save()
        dismiss()
    }
}
