import SwiftUI
import SwiftData

struct BillListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var searchText = ""
    @State private var showingAddBill = false
    @State private var selectedCategory: Category?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Category filter chips
                    categoryFilter

                    // Bills grouped by category
                    ForEach(filteredCategories) { category in
                        if !billsInCategory(category).isEmpty {
                            categorySection(category)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
            .background(Color.Theme.background)
            .navigationTitle("Bills")
            .searchable(text: $searchText, prompt: "Search bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddBill = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                BillFormView()
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                FilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories) { category in
                    FilterChip(
                        title: category.name,
                        isSelected: selectedCategory?.id == category.id
                    ) {
                        selectedCategory = selectedCategory?.id == category.id ? nil : category
                    }
                }
            }
        }
    }

    // MARK: - Category Section

    private func categorySection(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color(hex: category.colorHex))
                    .font(.subheadline)
                Text(category.name)
                    .font(.headline)
                    .foregroundStyle(Color.Theme.textPrimary)
                Spacer()
                Text("\(billsInCategory(category).count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.Theme.textTertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: .capsule)
            }

            VStack(spacing: 0) {
                let bills = billsInCategory(category)
                ForEach(bills) { bill in
                    NavigationLink(destination: BillDetailView(bill: bill)) {
                        BillRow(bill: bill)
                    }
                    .buttonStyle(.plain)
                    if bill.id != bills.last?.id {
                        Divider().padding(.leading, Spacing.lg)
                    }
                }
            }
            .padding(Spacing.md)
            .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
        }
    }

    // MARK: - Helpers

    private var filteredCategories: [Category] {
        if let selected = selectedCategory {
            return categories.filter { $0.id == selected.id }
        }
        return categories
    }

    private func billsInCategory(_ category: Category) -> [Bill] {
        category.bills
            .filter { $0.isActive }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .foregroundStyle(isSelected ? .white : Color.Theme.textSecondary)
        }
        .glassEffect(
            isSelected
                ? .regular.tint(Color.Theme.accent).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .accessibilityLabel("\(title) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
