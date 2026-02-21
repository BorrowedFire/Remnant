import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingAddCategory = false

    var body: some View {
        NavigationStack {
            List {
                Section("Default Categories") {
                    ForEach(categories.filter(\.isDefault)) { category in
                        categoryRow(category)
                    }
                }

                Section("Custom Categories") {
                    let custom = categories.filter { !$0.isDefault }
                    if custom.isEmpty {
                        Text("No custom categories yet")
                            .font(.subheadline)
                            .foregroundStyle(Color.Theme.textTertiary)
                    } else {
                        ForEach(custom) { category in
                            categoryRow(category)
                        }
                        .onDelete { offsets in
                            deleteCategories(at: offsets, from: custom)
                        }
                    }

                    Button("Add Category", systemImage: "plus.circle") {
                        showingAddCategory = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategoryView()
            }
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: category.icon)
                .foregroundStyle(Color(hex: category.colorHex))
                .frame(width: 24)
            Text(category.name)
                .font(.body)
                .foregroundStyle(Color.Theme.textPrimary)
            Spacer()
            Text("\(category.bills.count)")
                .font(.caption)
                .foregroundStyle(Color.Theme.textTertiary)
        }
    }

    private func deleteCategories(at offsets: IndexSet, from custom: [Category]) {
        for index in offsets {
            let category = custom[index]
            try? environment.categoryService.delete(category)
        }
        try? environment.categoryService.save()
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "tag"
    @State private var selectedColor = "0A84FF"

    private let iconOptions = [
        "tag", "creditcard", "house", "car", "heart",
        "gamecontroller", "music.note", "film", "book",
        "graduationcap", "cross.case", "dumbbell", "fork.knife",
        "gift", "phone", "wifi", "bolt", "drop"
    ]

    private let colorOptions = [
        "FF453A", "FF6B6B", "FF9F0A", "FFD60A",
        "30D158", "64D2FF", "0A84FF", "5E5CE6",
        "BF5AF2", "FF375F"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category Name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.md) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(
                                        selectedIcon == icon
                                            ? Color(hex: selectedColor)
                                            : Color.Theme.textSecondary
                                    )
                            }
                            .glassEffect(
                                selectedIcon == icon
                                    ? .regular.tint(Color(hex: selectedColor).opacity(0.3))
                                    : .regular,
                                in: .rect(cornerRadius: CornerRadius.medium)
                            )
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: Spacing.md) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if selectedColor == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }

                Section {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: selectedIcon)
                            .foregroundStyle(Color(hex: selectedColor))
                            .frame(width: 24)
                        Text(name.isEmpty ? "Preview" : name)
                            .foregroundStyle(name.isEmpty ? Color.Theme.textTertiary : Color.Theme.textPrimary)
                    }
                } header: {
                    Text("Preview")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.Theme.background)
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = try? environment.categoryService.create(
                            name: name, icon: selectedIcon, colorHex: selectedColor
                        )
                        try? environment.categoryService.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
