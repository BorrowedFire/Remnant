import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportCenterView: View {
    @EnvironmentObject private var appState: RemnantAppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ImportBatch.importedAt, order: .reverse)])
    private var importBatches: [ImportBatch]
    @Query(sort: [SortDescriptor(\CSVImportProfile.name)])
    private var importProfiles: [CSVImportProfile]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]

    @State private var isShowingImporter = false
    @State private var isShowingReceiptImporter = false
    @State private var isShowingEmailImporter = false
    @State private var importMode = ExpenseImportMode.statementReview
    @State private var importSummary: ExpenseImportSummary?
    @State private var importError: String?
    @State private var importNotice: String?
    @State private var selectedProfileID: UUID?
    @State private var profileDraftName = ""
    @State private var editingProfile: CSVImportProfile?

    private var selectedProfile: CSVImportProfile? {
        guard let selectedProfileID else { return nil }
        return importProfiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header("Imports", subtitle: "Bring in Wave exports, local receipts, and .eml receipt attachments without connecting to a service.")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Import Mode", selection: $importMode) {
                    ForEach(ExpenseImportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text(importMode.detail)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                Picker("CSV Profile", selection: $selectedProfileID) {
                    Text("Auto Detect").tag(Optional<UUID>.none)
                    ForEach(importProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 260)
                .onChange(of: selectedProfileID) { _, _ in
                    if let selectedProfile {
                        importMode = selectedProfile.importMode
                        profileDraftName = selectedProfile.name
                    } else {
                        profileDraftName = ""
                    }
                    importSummary = nil
                    importNotice = nil
                }

                if let selectedProfile {
                    Button {
                        editingProfile = selectedProfile
                    } label: {
                        Label("Edit Profile", systemImage: "slider.horizontal.3")
                    }
                }
            }

            HStack(spacing: Spacing.md) {
                Button {
                    isShowingImporter = true
                } label: {
                    Label("Choose CSV", systemImage: "doc.badge.plus")
                }
                Button {
                    isShowingReceiptImporter = true
                } label: {
                    Label("Add Receipts", systemImage: "doc.badge.gearshape")
                }
                Button {
                    isShowingEmailImporter = true
                } label: {
                    Label("Import .eml", systemImage: "envelope.badge")
                }
                Text("CSV, receipt, and email files are parsed locally. Nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }

            if let importError {
                Text(importError)
                    .foregroundStyle(.red)
            }
            if let importNotice {
                Text(importNotice)
                    .foregroundStyle(.secondary)
            }

            if let importSummary {
                importPreview(importSummary)
            } else if importBatches.isEmpty && receiptAttachments.isEmpty {
                emptyState("No imports yet", "Choose a Wave CSV or add locally downloaded receipts from your inbox.")
            }

            if !importBatches.isEmpty {
                Text("Import History")
                    .font(.headline)
                List(importBatches) { batch in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(batch.sourceName)
                                .font(.body.weight(.medium))
                            Text("\(batch.importMode.label) · \(batch.importedAt.mediumFormatted)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(batch.acceptedCount) imported")
                        Text("\(batch.duplicateCount) duplicates")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !importProfiles.isEmpty {
                csvProfileList
            }

            if !receiptAttachments.isEmpty {
                Text("Receipt Vault")
                    .font(.headline)
                List(receiptAttachments.prefix(12)) { attachment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(attachment.originalFilename)
                                .font(.body.weight(.medium))
                            Text(attachment.importedAt.mediumFormatted)
                                .foregroundStyle(.secondary)
                            if let summary = receiptMetadataSummary(for: attachment) {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(attachment.contentHash.prefix(12)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            openReceiptFile(attachment)
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(receiptFileExists(attachment) ? "Open receipt" : "Receipt file is missing")
                        .disabled(!receiptFileExists(attachment))
                        Button {
                            revealReceiptFile(attachment)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(receiptFileExists(attachment) ? "Show receipt in Finder" : "Receipt file is missing")
                        .disabled(!receiptFileExists(attachment))
                    }
                }
                .frame(minHeight: 140)
            }

            ReceiptReconciliationPanel(
                receipts: receiptAttachments,
                expenses: expenses
            )
        }
        .padding(24)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .fileImporter(
            isPresented: $isShowingReceiptImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            handleReceiptSelection(result)
        }
        .fileImporter(
            isPresented: $isShowingEmailImporter,
            allowedContentTypes: [emlContentType],
            allowsMultipleSelection: true
        ) { result in
            handleEmailReceiptSelection(result)
        }
        .onChange(of: importMode) { _, _ in
            importSummary = nil
            importNotice = nil
        }
        .sheet(item: $editingProfile) { profile in
            CSVImportProfileFormView(profile: profile)
                .frame(width: 560)
        }
        .onChange(of: appState.commandRequest) { _, request in
            guard let request else { return }
            guard appState.selectedSection == .imports else { return }
            switch request.kind {
            case .focusSearch:
                break
            case .importFiles:
                isShowingImporter = true
            case .exportReport:
                appState.selectedSection = .reports
            }
        }
    }

    private func importPreview(_ summary: ExpenseImportSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(summary.sourceName)
                .font(.headline)
            HStack(spacing: Spacing.lg) {
                metric("Rows", "\(summary.rowCount)")
                metric("Ready", "\(summary.accepted.count)")
                metric("Duplicates", "\(summary.duplicates.count)")
                metric("Skipped", "\(summary.ignoredRows.count)")
            }

            HStack(spacing: Spacing.md) {
                Label(summary.activeProfileName ?? "Auto Detect", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Text("\(summary.columnMapping.mappedCount) mapped columns")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                TextField("Profile Name", text: $profileDraftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button {
                    saveProfile(from: summary)
                } label: {
                    Label(selectedProfile == nil ? "Save Profile" : "Update Profile", systemImage: "square.and.arrow.down")
                }
                .disabled(normalizedProfileDraftName.isEmpty || summary.columnMapping.mappedCount == 0)
            }

            if !summary.notes.isEmpty {
                ForEach(summary.notes, id: \.self) { note in
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }

            if !summary.accepted.isEmpty {
                List(summary.accepted.prefix(12)) { candidate in
                    HStack {
                        Text("#\(candidate.sourceRow)")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Text(candidate.expense.merchant)
                        Spacer()
                        Text(candidate.expense.amount.currencyFormatted)
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 140)
            }

            HStack {
                Button("Clear Preview") {
                    importSummary = nil
                }
                Spacer()
                Button("Import \(summary.accepted.count) Expenses") {
                    commitImport(summary)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(summary.accepted.isEmpty)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var csvProfileList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("CSV Profiles")
                .font(.headline)
            List(importProfiles) { profile in
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.body.weight(.medium))
                        Text("\(profile.importMode.label) · \(profile.mapping.mappedCount) mapped columns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        selectedProfileID = profile.id
                        importMode = profile.importMode
                        profileDraftName = profile.name
                        importSummary = nil
                    } label: {
                        Label("Use", systemImage: "checkmark.circle")
                    }
                    Button {
                        editingProfile = profile
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        deleteProfile(profile)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .frame(minHeight: 150)
        }
    }

    private var emlContentType: UTType {
        UTType(filenameExtension: "eml") ?? .data
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let profile = selectedProfile
            importSummary = try ExpenseImportService.previewCSV(
                at: url,
                existingExpenses: expenses,
                source: importMode.source,
                defaultStatus: importMode.defaultStatus,
                profile: profile,
                vendorRules: vendorRules
            )
            if profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileDraftName = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            importSummary = nil
            importError = error.localizedDescription
        }
    }

    private func commitImport(_ summary: ExpenseImportSummary) {
        let batch = ImportBatch(
            sourceName: summary.sourceName,
            importMode: importMode,
            rowCount: summary.rowCount,
            acceptedCount: summary.accepted.count,
            duplicateCount: summary.duplicates.count,
            ignoredCount: summary.ignoredRows.count,
            notes: ([importMode.detail, profileNote(for: summary)] + summary.notes).joined(separator: " ")
        )
        modelContext.insert(batch)

        for candidate in summary.accepted {
            candidate.expense.importBatchID = batch.id
            modelContext.insert(candidate.expense)
        }

        try? RemnantStore.saveLedgerMutation(context: modelContext)
        importSummary = nil
        importNotice = "Imported \(summary.accepted.count) expenses from \(summary.sourceName)."
    }

    private var normalizedProfileDraftName: String {
        profileDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveProfile(from summary: ExpenseImportSummary) {
        guard !normalizedProfileDraftName.isEmpty else { return }

        if let selectedProfile {
            selectedProfile.name = normalizedProfileDraftName
            selectedProfile.importMode = importMode
            selectedProfile.apply(mapping: summary.columnMapping)
            selectedProfileID = selectedProfile.id
        } else {
            let profile = CSVImportProfile(
                name: normalizedProfileDraftName,
                importMode: importMode,
                mapping: summary.columnMapping
            )
            modelContext.insert(profile)
            selectedProfileID = profile.id
        }

        try? modelContext.save()
        importNotice = "Saved CSV profile \(normalizedProfileDraftName)."
    }

    private func deleteProfile(_ profile: CSVImportProfile) {
        if selectedProfileID == profile.id {
            selectedProfileID = nil
            profileDraftName = ""
            importSummary = nil
        }
        modelContext.delete(profile)
        try? modelContext.save()
    }

    private func profileNote(for summary: ExpenseImportSummary) -> String {
        if let activeProfileName = summary.activeProfileName {
            return "Profile: \(activeProfileName)."
        }
        return "Profile: Auto Detect."
    }

    private func handleReceiptSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            let urls = try result.get()
            let summary = ReceiptVault.importReceipts(at: urls, context: modelContext)
            try RemnantStore.saveLedgerMutation(context: modelContext)

            var parts = ["Added \(summary.importedCount) receipts"]
            if summary.duplicateCount > 0 {
                parts.append("\(summary.duplicateCount) duplicates")
            }
            if !summary.failedFilenames.isEmpty {
                parts.append("\(summary.failedFilenames.count) failed")
            }
            importNotice = parts.joined(separator: ", ") + "."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleEmailReceiptSelection(_ result: Result<[URL], Error>) {
        importError = nil
        importNotice = nil

        do {
            let urls = try result.get()
            let summary = EmailReceiptImportService.importEMLFiles(at: urls, context: modelContext)
            try RemnantStore.saveLedgerMutation(context: modelContext)

            var parts = ["Imported \(summary.importedCount) email receipts"]
            if summary.duplicateCount > 0 {
                parts.append("\(summary.duplicateCount) duplicates")
            }
            if summary.skippedAttachmentCount > 0 {
                parts.append("\(summary.skippedAttachmentCount) skipped attachments")
            }
            if !summary.failedFilenames.isEmpty {
                parts.append(failedEmailImportSummary(summary.failedFilenames))
            }
            importNotice = parts.joined(separator: ", ") + "."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func failedEmailImportSummary(_ filenames: [String]) -> String {
        let visibleFilenames = filenames.prefix(3).joined(separator: ", ")
        let label = filenames.count == 1 ? "failed message" : "failed messages"
        if filenames.count > 3 {
            return "\(filenames.count) \(label): \(visibleFilenames), and \(filenames.count - 3) more"
        }
        return "\(filenames.count) \(label): \(visibleFilenames)"
    }

    private func receiptMetadataSummary(for attachment: ReceiptAttachment) -> String? {
        var parts: [String] = []
        if let merchant = attachment.extractedMerchant {
            parts.append(merchant)
        }
        if let date = attachment.extractedDate {
            parts.append(date.mediumFormatted)
        }
        if let amount = attachment.extractedAmount {
            parts.append(amount.currencyFormatted)
        }
        if let subject = attachment.sourceMessageSubject {
            parts.append("Email: \(subject)")
        } else if let filename = attachment.sourceMessageFilename {
            parts.append("Email: \(filename)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct CSVImportProfileFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: CSVImportProfile

    @State private var name: String
    @State private var importMode: ExpenseImportMode
    @State private var dateHeader: String
    @State private var merchantHeader: String
    @State private var amountHeader: String
    @State private var debitHeader: String
    @State private var creditHeader: String
    @State private var categoryHeader: String
    @State private var accountHeader: String
    @State private var paymentMethodHeader: String
    @State private var noteHeader: String
    @State private var receiptHeader: String
    @State private var transactionTypeHeader: String
    @State private var directionHeader: String
    @State private var currencyHeader: String

    init(profile: CSVImportProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _importMode = State(initialValue: profile.importMode)
        _dateHeader = State(initialValue: profile.dateHeader)
        _merchantHeader = State(initialValue: profile.merchantHeader)
        _amountHeader = State(initialValue: profile.amountHeader)
        _debitHeader = State(initialValue: profile.debitHeader)
        _creditHeader = State(initialValue: profile.creditHeader)
        _categoryHeader = State(initialValue: profile.categoryHeader)
        _accountHeader = State(initialValue: profile.accountHeader)
        _paymentMethodHeader = State(initialValue: profile.paymentMethodHeader)
        _noteHeader = State(initialValue: profile.noteHeader)
        _receiptHeader = State(initialValue: profile.receiptHeader)
        _transactionTypeHeader = State(initialValue: profile.transactionTypeHeader)
        _directionHeader = State(initialValue: profile.directionHeader)
        _currencyHeader = State(initialValue: profile.currencyHeader)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("CSV Profile", subtitle: "Saved locally for recurring imports.")

            Form {
                TextField("Name", text: $name)
                Picker("Import Mode", selection: $importMode) {
                    ForEach(ExpenseImportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Date Header", text: $dateHeader)
                TextField("Merchant Header", text: $merchantHeader)
                TextField("Amount Header", text: $amountHeader)
                TextField("Debit Header", text: $debitHeader)
                TextField("Credit Header", text: $creditHeader)
                TextField("Category Header", text: $categoryHeader)
                TextField("Account Header", text: $accountHeader)
                TextField("Payment Method Header", text: $paymentMethodHeader)
                TextField("Note Header", text: $noteHeader)
                TextField("Receipt Header", text: $receiptHeader)
                TextField("Transaction Type Header", text: $transactionTypeHeader)
                TextField("Direction Header", text: $directionHeader)
                TextField("Currency Header", text: $currencyHeader)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedName.isEmpty)
            }
        }
        .padding(24)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        profile.name = normalizedName
        profile.importMode = importMode
        profile.apply(mapping: CSVColumnMapping(
            dateHeader: dateHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            merchantHeader: merchantHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            amountHeader: amountHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            debitHeader: debitHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            creditHeader: creditHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryHeader: categoryHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            accountHeader: accountHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            paymentMethodHeader: paymentMethodHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            noteHeader: noteHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            receiptHeader: receiptHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            transactionTypeHeader: transactionTypeHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            directionHeader: directionHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyHeader: currencyHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        try? modelContext.save()
        dismiss()
    }
}

private struct ReceiptReconciliationPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\VendorRule.merchantPattern)])
    private var vendorRules: [VendorRule]

    let receipts: [ReceiptAttachment]
    let expenses: [Expense]

    @State private var selectedReceiptID: UUID?
    @State private var selectedExpenseID: UUID?
    @State private var actionNotice: String?

    private var unmatchedReceipts: [ReceiptAttachment] {
        receipts.filter { $0.expenseID == nil }
    }

    private var missingReceiptExpenses: [Expense] {
        ExpenseLedger.expensesMissingReceipts(in: expenses)
    }

    private var selectedReceipt: ReceiptAttachment? {
        guard let selectedReceiptID else { return nil }
        return unmatchedReceipts.first { $0.id == selectedReceiptID }
    }

    private var suggestions: [ReceiptMatchSuggestion] {
        ReceiptMatcher.suggestions(receipts: receipts, expenses: expenses)
    }

    private var receiptsReadyForDrafts: [ReceiptAttachment] {
        let suggestedReceiptIDs = Set(suggestions.map { $0.receipt.id })
        return unmatchedReceipts.filter { receipt in
            receipt.extractedAmount != nil && !suggestedReceiptIDs.contains(receipt.id)
        }
    }

    var body: some View {
        Group {
            if !unmatchedReceipts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Receipt Matching")
                        .font(.headline)

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Suggested Matches")
                                .font(.subheadline.weight(.semibold))
                            ForEach(suggestions.prefix(5)) { suggestion in
                                HStack(spacing: Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.receipt.extractedMerchant ?? suggestion.receipt.originalFilename)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        Text("to \(suggestion.expense.merchant) · \(suggestion.expense.amount.currencyFormatted)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(suggestion.score)%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(suggestion.reasons.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 140, alignment: .trailing)
                                    Button {
                                        openReceiptFile(suggestion.receipt)
                                    } label: {
                                        Label("Open Receipt", systemImage: "arrow.up.forward.square")
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help(receiptFileExists(suggestion.receipt) ? "Open receipt" : "Receipt file is missing")
                                    .disabled(!receiptFileExists(suggestion.receipt))
                                    Button {
                                        attach(suggestion)
                                    } label: {
                                        Label("Attach", systemImage: "link")
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    }

                    if !receiptsReadyForDrafts.isEmpty {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Receipt Drafts")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(receiptsReadyForDrafts.count) receipt-only items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                createDraftExpensesFromReceipts()
                            } label: {
                                Label("Create Drafts", systemImage: "tray.and.arrow.down")
                            }
                        }
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    }

                    HStack(spacing: Spacing.md) {
                        Picker("Receipt", selection: $selectedReceiptID) {
                            Text("Choose Receipt").tag(nil as UUID?)
                            ForEach(unmatchedReceipts) { receipt in
                                Text(receiptPickerTitle(for: receipt)).tag(receipt.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)

                        if !missingReceiptExpenses.isEmpty {
                            Picker("Expense", selection: $selectedExpenseID) {
                                Text("Choose Expense").tag(nil as UUID?)
                                ForEach(missingReceiptExpenses) { expense in
                                    Text("\(expense.merchant) · \(expense.amount.currencyFormatted)")
                                        .tag(expense.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 320)

                            Button {
                                attachSelection()
                            } label: {
                                Label("Attach", systemImage: "link")
                            }
                            .disabled(selectedReceiptID == nil || selectedExpenseID == nil)
                        }

                        Button {
                            createExpenseFromSelection()
                        } label: {
                            Label("Create Expense", systemImage: "plus")
                        }
                        .disabled(selectedReceipt?.extractedAmount == nil)
                    }

                    if let actionNotice {
                        Text(actionNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(unmatchedReceipts.count) receipts are waiting in the local vault. \(missingReceiptExpenses.count) expenses are missing receipts.")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    private func attachSelection() {
        guard let selectedReceiptID,
              let selectedExpenseID,
              let receipt = unmatchedReceipts.first(where: { $0.id == selectedReceiptID }),
              let expense = missingReceiptExpenses.first(where: { $0.id == selectedExpenseID }) else {
            return
        }

        ReceiptVault.link(attachment: receipt, to: expense)
        try? RemnantStore.saveLedgerMutation(context: modelContext)
        actionNotice = nil
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func attach(_ suggestion: ReceiptMatchSuggestion) {
        ReceiptVault.link(attachment: suggestion.receipt, to: suggestion.expense)
        try? RemnantStore.saveLedgerMutation(context: modelContext)
        actionNotice = nil
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func createExpenseFromSelection() {
        guard let receipt = selectedReceipt else { return }
        guard ReceiptVault.createDraftExpense(from: receipt, context: modelContext, vendorRules: vendorRules) != nil else { return }
        try? RemnantStore.saveLedgerMutation(context: modelContext)
        actionNotice = "Created 1 draft expense."
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func createDraftExpensesFromReceipts() {
        let createdCount = ReceiptVault.createDraftExpenses(
            from: receiptsReadyForDrafts,
            context: modelContext,
            vendorRules: vendorRules
        )
        guard createdCount > 0 else { return }
        try? RemnantStore.saveLedgerMutation(context: modelContext)
        actionNotice = "Created \(createdCount) draft expenses."
        self.selectedReceiptID = nil
        self.selectedExpenseID = nil
    }

    private func receiptPickerTitle(for receipt: ReceiptAttachment) -> String {
        var title = receipt.extractedMerchant ?? receipt.originalFilename
        if let amount = receipt.extractedAmount {
            title += " · \(amount.currencyFormatted)"
        }
        return title
    }
}
