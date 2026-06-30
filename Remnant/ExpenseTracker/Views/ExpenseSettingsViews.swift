import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExpenseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]
    @Query(sort: [SortDescriptor(\BusinessDimension.sortOrder), SortDescriptor(\BusinessDimension.name)])
    private var dimensions: [BusinessDimension]

    @AppStorage("remnant.automaticBackup.enabled")
    private var isAutomaticBackupEnabled = false
    @AppStorage("remnant.automaticBackup.lastRun")
    private var automaticBackupLastRun = 0.0

    @State private var merchantPattern = ""
    @State private var selectedCategory = "Uncategorized"
    @State private var newDimensionKind = BusinessDimensionKind.account
    @State private var newDimensionName = ""
    @State private var newDimensionNote = ""
    @State private var backupNotice: String?
    @State private var backupError: String?
    @State private var lastBackupURL: URL?
    @State private var integrityReport: RemnantBackupIntegrityReport?
    @State private var restoreCandidateURL: URL?
    @State private var isConfirmingRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header("Settings", subtitle: "Local rules and privacy controls for expense tracking.")

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Categories")
                        .font(.headline)

                    if categories.isEmpty {
                        Text("No categories yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(categories) { category in
                            HStack(spacing: Spacing.md) {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.body.weight(.medium))
                                    Text(category.taxBucket)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Reporting Dimensions")
                        .font(.headline)

                    HStack(spacing: Spacing.md) {
                        Picker("Type", selection: $newDimensionKind) {
                            ForEach(BusinessDimensionKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        TextField("Name", text: $newDimensionName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)

                        TextField("Note", text: $newDimensionNote)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)

                        Button {
                            addDimension()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .disabled(normalizedDimensionName.isEmpty)
                    }

                    if dimensions.isEmpty {
                        Text("No reporting dimensions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(BusinessDimensionKind.allCases) { kind in
                                let rows = dimensionsForKind(kind)
                                if !rows.isEmpty {
                                    Section(kind.pluralLabel) {
                                        ForEach(rows) { dimension in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(dimension.name)
                                                        .font(.body.weight(.medium))
                                                    if !dimension.note.isEmpty {
                                                        Text(dimension.note)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer()
                                                Button(role: .destructive) {
                                                    deleteDimension(dimension)
                                                } label: {
                                                    Label("Archive", systemImage: "archivebox")
                                                }
                                                .labelStyle(.iconOnly)
                                                .buttonStyle(.borderless)
                                                .help("Archive dimension")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 190)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Vendor Rules")
                        .font(.headline)
                    Text("Use rules to categorize imported expenses and receipt-created drafts when the source file has no category.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.md) {
                        TextField("Merchant contains", text: $merchantPattern)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)

                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categoryNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190)

                        Button {
                            addRule()
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                        }
                        .disabled(normalizedPattern.isEmpty)
                    }

                    if activeVendorRules.isEmpty {
                        Text("No vendor rules yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(activeVendorRules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.merchantPattern)
                                        .font(.body.weight(.medium))
                                    Text(rule.defaultCategoryName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    deleteRule(rule)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Archive rule")
                            }
                        }
                        .frame(minHeight: 120)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))

                backupSection

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Privacy")
                        .font(.headline)

                    Label("No analytics or tracking SDKs", systemImage: "eye.slash")
                    Label("No bank linking or FinanceKit access", systemImage: "building.columns")
                    Label("No StoreKit subscription gates", systemImage: "creditcard.trianglebadge.exclamationmark")
                    Label("Receipts stay in the local vault until you export them", systemImage: "doc.badge.lock")

                    Text("Exports are explicit user actions. Import parsing, duplicate checks, receipt extraction, and vendor rules all run locally.")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .padding(24)
            .onAppear {
                if !categoryNames.contains(selectedCategory) {
                    selectedCategory = categoryNames.first ?? "Uncategorized"
                }
            }
            .confirmationDialog(
                "Restore Backup",
                isPresented: $isConfirmingRestore,
                presenting: restoreCandidateURL
            ) { url in
                Button("Stage Restore", role: .destructive) {
                    stageRestore(from: url)
                }
            } message: { url in
                Text("The selected backup will replace current local data the next time Remnant opens: \(url.lastPathComponent)")
            }
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Backup & Integrity")
                .font(.headline)

            HStack(spacing: Spacing.md) {
                Button {
                    checkIntegrity()
                } label: {
                    Label("Check Integrity", systemImage: "checkmark.shield")
                }

                Button {
                    createBackup()
                } label: {
                    Label("Create Backup", systemImage: "archivebox")
                }

                Button {
                    testAutomaticBackup()
                } label: {
                    Label("Test Auto Backup", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    chooseRestoreBackup()
                } label: {
                    Label("Restore Backup", systemImage: "arrow.counterclockwise")
                }

                if let lastBackupURL {
                    Button {
                        revealFile(lastBackupURL)
                    } label: {
                        Label("Show Backup", systemImage: "folder")
                    }
                }
            }

            Toggle("Automatic daily backup", isOn: $isAutomaticBackupEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                Text("Automatic backups are local packages in Remnant's Application Support folder.")
                    .foregroundStyle(.secondary)
                if automaticBackupLastRun > 0 {
                    Text("Last auto backup: \(Date(timeIntervalSince1970: automaticBackupLastRun).mediumFormatted)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let integrityReport {
                HStack(spacing: Spacing.lg) {
                    metric("Expenses", "\(integrityReport.expenseCount)")
                    metric("Receipts", "\(integrityReport.attachmentCount)")
                    metric("Issues", "\(integrityReport.issues.count)")
                }

                if integrityReport.issues.isEmpty {
                    Label("Integrity check passed", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(integrityReport.issues.prefix(5)) { issue in
                            Label(issue.detail, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if integrityReport.issues.count > 5 {
                            Text("\(integrityReport.issues.count - 5) more issue(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let backupNotice {
                Text(backupNotice)
                    .foregroundStyle(.secondary)
            }
            if let backupError {
                Text(backupError)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    private var activeVendorRules: [VendorRule] {
        vendorRules.filter { !$0.isArchived }
    }

    private var normalizedPattern: String {
        merchantPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDimensionName: String {
        newDimensionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkIntegrity() {
        do {
            integrityReport = try RemnantBackupService.integrityReport(context: modelContext)
            backupError = nil
            backupNotice = nil
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func testAutomaticBackup() {
        do {
            let result = try RemnantBackupService.createAutomaticBackup(context: modelContext)
            integrityReport = result.report
            backupNotice = "Auto backup created at \(result.backupURL.lastPathComponent)."
            backupError = nil
            lastBackupURL = result.backupURL
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func createBackup() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "remnant-backup-\(backupDateFormatter.string(from: Date())).\(RemnantBackupService.backupExtension)"
        panel.title = "Create Remnant Backup"

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        do {
            let report = try RemnantBackupService.createBackup(
                at: url,
                context: modelContext,
                allowOverwrite: true
            )
            integrityReport = report
            backupNotice = "Backup created at \(url.lastPathComponent)."
            backupError = nil
            lastBackupURL = url
        } catch {
            backupError = error.localizedDescription
        }
    }

    private func chooseRestoreBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Remnant Backup"

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        restoreCandidateURL = url
        isConfirmingRestore = true
    }

    private func stageRestore(from url: URL) {
        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let report = try RemnantBackupService.stageRestore(from: url, allowOverwrite: true)
            integrityReport = report
            backupNotice = "Restore staged. Restart Remnant to load \(url.lastPathComponent)."
            backupError = nil
        } catch {
            backupError = error.localizedDescription
        }
    }

    private var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }

    private func dimensionsForKind(_ kind: BusinessDimensionKind) -> [BusinessDimension] {
        dimensions.filter { $0.kind == kind && !$0.isArchived }
    }

    private func addDimension() {
        guard !normalizedDimensionName.isEmpty else { return }
        let existing = dimensions.first {
            $0.kind == newDimensionKind
                && $0.name.compare(normalizedDimensionName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if let existing {
            existing.note = newDimensionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.isArchived = false
        } else {
            let nextSortOrder = ((dimensions.map(\.sortOrder).max() ?? -1) + 1)
            modelContext.insert(
                BusinessDimension(
                    kind: newDimensionKind,
                    name: normalizedDimensionName,
                    note: newDimensionNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    sortOrder: nextSortOrder
                )
            )
        }

        newDimensionName = ""
        newDimensionNote = ""
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func deleteDimension(_ dimension: BusinessDimension) {
        dimension.isArchived = true
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func addRule() {
        guard !normalizedPattern.isEmpty else { return }
        let category = selectedCategory.isEmpty ? "Uncategorized" : selectedCategory
        let taxBucket = categories.first { $0.name == category }?.taxBucket ?? category
        let existingRule = vendorRules.first {
            $0.merchantPattern.compare(normalizedPattern, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if let existingRule {
            existingRule.defaultCategoryName = category
            existingRule.defaultTaxBucket = taxBucket
            existingRule.isArchived = false
        } else {
            modelContext.insert(
                VendorRule(
                    merchantPattern: normalizedPattern,
                    defaultCategoryName: category,
                    defaultTaxBucket: taxBucket
                )
            )
        }

        merchantPattern = ""
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }

    private func deleteRule(_ rule: VendorRule) {
        rule.isArchived = true
        try? RemnantStore.saveLedgerMutation(context: modelContext)
    }
}
