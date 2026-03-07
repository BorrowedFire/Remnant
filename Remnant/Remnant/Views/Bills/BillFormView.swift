import SwiftUI
import SwiftData

struct BillFormView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var existingBill: Bill?

    @State private var name: String = ""
    @State private var expectedAmount: Decimal = 0
    @State private var dueDay: Int = 1
    @State private var dueDate: Date = Date()
    @State private var frequency: BillFrequency = .monthly
    @State private var selectedCategory: Category?
    @State private var reminderEnabled: Bool = false
    @State private var reminderDaysBefore: Int = 1
    @State private var showingSubscription = false
    @State private var showingBillLimitAlert = false
    @State private var showingAddCategory = false

    private var isEditing: Bool { existingBill != nil }
    private var isPremium: Bool { environment.subscriptionService.isPremium }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill Info") {
                    TextField("Name", text: $name)
                    CurrencyField(title: "Expected Amount", amount: $expectedAmount)

                    Picker("Frequency", selection: $frequency) {
                        ForEach(BillFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    if frequency != .annual && frequency != .oneTime {
                        Picker("Due Day", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text(ordinal(day)).tag(day)
                            }
                        }
                    }

                    if frequency == .annual || frequency == .oneTime {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.icon)
                                .tag(category as Category?)
                        }
                    }

                    if isPremium {
                        Button("Add Custom Category", systemImage: "plus.circle.fill") {
                            showingAddCategory = true
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Label("Custom Categories", systemImage: "plus.circle.fill")
                                Spacer()
                                Label("Remnant+", systemImage: "star.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.Theme.premium)
                            }
                        }
                    }
                }

                Section("Reminders") {
                    if isPremium {
                        Toggle("Remind Me", isOn: $reminderEnabled)
                        if reminderEnabled {
                            Picker("When", selection: $reminderDaysBefore) {
                                Text("Day of").tag(0)
                                Text("1 day before").tag(1)
                                Text("3 days before").tag(3)
                                Text("7 days before").tag(7)
                            }
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Label("Remind Me", systemImage: "bell")
                                Spacer()
                                Label("Remnant+", systemImage: "star.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.Theme.premium)
                            }
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button("Archive Bill", role: .destructive) {
                            if let bill = existingBill {
                                environment.billService.archive(bill)
                                try? environment.billService.save()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle(isEditing ? "Edit Bill" : "Add Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveBill() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
            .sheet(isPresented: $showingAddCategory) {
                AddCategoryView()
            }
            .onChange(of: showingAddCategory) { _, isShowing in
                if !isShowing {
                    // Auto-select the newest custom category
                    if let newest = categories.last(where: { !$0.isDefault }) {
                        selectedCategory = newest
                    }
                }
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .alert("Bill Limit Reached", isPresented: $showingBillLimitAlert) {
                Button("Upgrade") { showingSubscription = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Free accounts can have up to \(SubscriptionService.freeBillLimit) bills. Upgrade to Remnant+ for unlimited bills.")
            }
        }
    }

    private func loadExisting() {
        guard let bill = existingBill else { return }
        name = bill.name
        expectedAmount = bill.expectedAmount ?? 0
        dueDay = bill.dueDay ?? 1
        dueDate = bill.dueDate ?? Date()
        frequency = bill.frequency
        selectedCategory = bill.category
        reminderEnabled = bill.reminderEnabled
        reminderDaysBefore = bill.reminderDaysBefore
    }

    private func saveBill() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Check free tier bill limit for new bills
        if !isEditing {
            let currentCount = (try? environment.billService.fetchAll().count) ?? 0
            if !environment.subscriptionService.canAddBill(currentCount: currentCount) {
                showingBillLimitAlert = true
                return
            }
        }

        let useDueDate = (frequency == .annual || frequency == .oneTime)

        if let bill = existingBill {
            bill.name = trimmedName
            bill.expectedAmount = expectedAmount > 0 ? expectedAmount : nil
            bill.dueDay = useDueDate ? nil : dueDay
            bill.dueDate = useDueDate ? dueDate : nil
            bill.frequency = frequency
            bill.category = selectedCategory
            bill.reminderEnabled = reminderEnabled
            bill.reminderDaysBefore = reminderDaysBefore
            try? environment.billService.save()

            if reminderEnabled {
                environment.reminderService.scheduleReminder(for: bill)
            } else {
                environment.reminderService.removeReminder(for: bill)
            }
        } else {
            let bill = environment.billService.create(
                name: trimmedName,
                expectedAmount: expectedAmount > 0 ? expectedAmount : nil,
                dueDay: useDueDate ? nil : dueDay,
                dueDate: useDueDate ? dueDate : nil,
                frequency: frequency,
                category: selectedCategory
            )
            // Set reminder properties BEFORE saving
            bill.reminderEnabled = reminderEnabled
            bill.reminderDaysBefore = reminderDaysBefore
            try? environment.billService.save()

            if reminderEnabled {
                environment.reminderService.scheduleReminder(for: bill)
            }
        }
        dismiss()
    }

    private func ordinal(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
