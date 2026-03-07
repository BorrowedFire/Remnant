import SwiftUI
import SwiftData

struct ImportReviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @Binding var transactions: [ImportedTransaction]
    @State private var selectedIndices: Set<Int> = []
    @State private var importCount = 0
    @State private var showingComplete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(transactions.count) transactions found. Select which to import as payments.")
                        .font(.subheadline)
                        .foregroundStyle(Color.Theme.textSecondary)
                }

                Section("Matched") {
                    ForEach(Array(matchedTransactions.enumerated()), id: \.element.id) { index, tx in
                        transactionRow(tx, globalIndex: globalIndex(for: tx))
                    }
                }

                if !unmatchedTransactions.isEmpty {
                    Section("Unmatched") {
                        ForEach(Array(unmatchedTransactions.enumerated()), id: \.element.id) { index, tx in
                            transactionRow(tx, globalIndex: globalIndex(for: tx))
                        }
                    }
                }
            }
            .background(Color.Theme.background)
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedIndices.count)") {
                        importSelected()
                    }
                    .disabled(selectedIndices.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Pre-select all matched transactions
                selectedIndices = Set(
                    transactions.indices.filter { transactions[$0].matchConfidence >= 0.5 }
                )
            }
            .alert("Import Complete", isPresented: $showingComplete) {
                Button("Done") {
                    transactions = []
                    dismiss()
                }
            } message: {
                Text("\(importCount) payment\(importCount == 1 ? "" : "s") recorded.")
            }
        }
    }

    // MARK: - Subviews

    private func transactionRow(_ tx: ImportedTransaction, globalIndex: Int) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: selectedIndices.contains(globalIndex) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedIndices.contains(globalIndex) ? Color.Theme.positive : Color.Theme.textTertiary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(tx.date.shortFormatted)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)

                    if let bill = tx.matchedBill {
                        Text("→ \(bill.name)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.Theme.info)
                    }
                }
            }

            Spacer()

            Text(tx.amount.currencyFormatted)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(tx.type == .debit ? Color.Theme.negative : Color.Theme.positive)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedIndices.contains(globalIndex) {
                selectedIndices.remove(globalIndex)
            } else {
                selectedIndices.insert(globalIndex)
            }
        }
    }

    // MARK: - Data

    private var matchedTransactions: [ImportedTransaction] {
        transactions.filter { $0.matchConfidence >= 0.5 }
    }

    private var unmatchedTransactions: [ImportedTransaction] {
        transactions.filter { $0.matchConfidence < 0.5 }
    }

    private func globalIndex(for tx: ImportedTransaction) -> Int {
        transactions.firstIndex(where: { $0.id == tx.id }) ?? 0
    }

    private func importSelected() {
        let account = accounts.first
        var count = 0

        for index in selectedIndices.sorted() {
            let tx = transactions[index]
            guard tx.type == .debit else { continue }

            if let bill = tx.matchedBill {
                _ = environment.paymentService.recordPayment(
                    bill: bill,
                    amount: tx.amount,
                    date: tx.date,
                    account: account,
                    note: "Imported: \(tx.name)"
                )
                count += 1
            }
        }

        try? environment.paymentService.save()
        importCount = count
        showingComplete = true
    }
}
