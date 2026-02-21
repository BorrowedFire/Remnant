import SwiftUI
import SwiftData

struct IncomeListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var sources: [IncomeSource] = []
    @State private var showingAddSource = false
    @State private var showingAddEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    ForEach(sources) { source in
                        incomeSourceCard(source)
                    }

                    if sources.isEmpty {
                        ContentUnavailableView(
                            "No Income Sources",
                            systemImage: "banknote",
                            description: Text("Add your first income source to start tracking paychecks.")
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
            .background(Color.Theme.background)
            .navigationTitle("Income")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Income Source", systemImage: "building.2") {
                            showingAddSource = true
                        }
                        Button("Record Paycheck", systemImage: "dollarsign.circle") {
                            showingAddEntry = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSource) {
                IncomeSourceForm()
            }
            .sheet(isPresented: $showingAddEntry) {
                IncomeEntryForm()
            }
            .task {
                sources = (try? environment.incomeService.fetchSources()) ?? []
            }
        }
    }

    private func incomeSourceCard(_ source: IncomeSource) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.textPrimary)
                    Text(source.frequency.displayName)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.textTertiary)
                }
                Spacer()
                if let expected = source.expectedAmount {
                    Text(expected.currencyFormatted)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.Theme.positive)
                }
            }

            if !source.entries.isEmpty {
                Divider()
                ForEach(source.entries.sorted(by: { $0.date > $1.date }).prefix(3)) { entry in
                    HStack {
                        Text(entry.date.shortFormatted)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.textTertiary)
                        Spacer()
                        Text(entry.amount.currencyFormatted)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.Theme.positive)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }
}

// MARK: - Income Source Form

struct IncomeSourceForm: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var frequency: PayFrequency = .biweekly
    @State private var expectedAmount: Decimal = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Income Source") {
                    TextField("Employer Name", text: $name)
                    Picker("Pay Frequency", selection: $frequency) {
                        ForEach(PayFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    CurrencyField(title: "Expected Amount (optional)", amount: $expectedAmount)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Add Income Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = environment.incomeService.createSource(
                            name: name,
                            frequency: frequency,
                            expectedAmount: expectedAmount > 0 ? expectedAmount : nil
                        )
                        try? environment.incomeService.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
