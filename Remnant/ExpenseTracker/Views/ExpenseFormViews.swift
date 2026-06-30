import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\BusinessDimension.sortOrder), SortDescriptor(\BusinessDimension.name)])
    private var dimensions: [BusinessDimension]
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var allExpenses: [Expense]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    private let expense: Expense?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var categoryName = "Uncategorized"
    @State private var status = ExpenseStatus.draft
    @State private var paymentAccount = ""
    @State private var paymentMethod = ""
    @State private var vendorName = ""
    @State private var clientName = ""
    @State private var projectName = ""
    @State private var isBillable = false
    @State private var isReimbursable = false
    @State private var note = ""
    @State private var receiptFilename = ""
    @State private var receiptURL: URL?
    @State private var receiptImportError: String?
    @State private var isShowingReceiptImporter = false

    init(expense: Expense? = nil) {
        self.expense = expense
        _merchant = State(initialValue: expense?.merchant ?? "")
        _amount = State(initialValue: expense.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: expense?.date ?? Date())
        _categoryName = State(initialValue: expense?.categoryName ?? "Uncategorized")
        _status = State(initialValue: expense?.status ?? .draft)
        _paymentAccount = State(initialValue: expense?.paymentAccount ?? "")
        _paymentMethod = State(initialValue: expense?.paymentMethod ?? "")
        _vendorName = State(initialValue: expense?.vendorName ?? "")
        _clientName = State(initialValue: expense?.clientName ?? "")
        _projectName = State(initialValue: ExpenseLedger.isCompanyProjectName(expense?.projectName) ? "" : expense?.projectName ?? "")
        _isBillable = State(initialValue: expense?.isBillable ?? false)
        _isReimbursable = State(initialValue: expense.map { $0.isReimbursable || $0.status == .reimbursable } ?? false)
        _note = State(initialValue: expense?.note ?? "")
        _receiptFilename = State(initialValue: expense?.receiptFilename ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header(formTitle, subtitle: "Saved locally. No receipt or expense data is uploaded.")

            Form {
                TextField("Merchant", text: $merchant)
                TextField("Amount", text: $amount)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Category", selection: $categoryName) {
                    ForEach(categoryNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(ExpenseStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Billable", isOn: $isBillable)
                Toggle("Reimbursable", isOn: $isReimbursable)
                dimensionPicker("Account", kind: .account, selection: $paymentAccount, emptyLabel: "None")
                dimensionPicker("Vendor", kind: .vendor, selection: $vendorName, emptyLabel: "Use merchant")
                dimensionPicker("Client", kind: .client, selection: $clientName, emptyLabel: "None")
                dimensionPicker("Project", kind: .project, selection: $projectName, emptyLabel: "None")
                Picker("Payment Method", selection: $paymentMethod) {
                    Text("Unknown").tag("")
                    ForEach(paymentMethodNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }

            ReceiptPreviewCard(
                title: receiptDisplayName,
                subtitle: receiptSubtitle,
                url: receiptPreviewURL,
                onChoose: {
                    isShowingReceiptImporter = true
                },
                onOpen: receiptPreviewURL.map { url in
                    { _ = NSWorkspace.shared.open(url) }
                },
                onReveal: receiptPreviewURL.map { url in
                    { revealFile(url) }
                }
            )

            if let receiptImportError {
                Text(receiptImportError)
                    .foregroundStyle(.red)
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
                .disabled(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedAmount == nil)
            }
        }
        .padding(24)
        .fileImporter(
            isPresented: $isShowingReceiptImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleReceiptSelection(result)
        }
    }

    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return names.isEmpty ? ["Uncategorized"] : names
    }

    private var paymentMethodNames: [String] {
        var names = Set<String>()
        for dimension in dimensions where dimension.kind == .paymentMethod && !dimension.isArchived {
            if let name = normalizedDisplayValue(dimension.name) {
                names.insert(name)
            }
        }
        for expense in allExpenses {
            if let name = normalizedDisplayValue(expense.paymentMethod) {
                names.insert(name)
            }
        }
        if let current = normalizedDisplayValue(paymentMethod) {
            names.insert(current)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func dimensionPicker(
        _ title: String,
        kind: BusinessDimensionKind,
        selection: Binding<String>,
        emptyLabel: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(emptyLabel).tag("")
            ForEach(dimensionNames(for: kind, currentValue: selection.wrappedValue), id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private func dimensionNames(for kind: BusinessDimensionKind, currentValue: String) -> [String] {
        var names = Set<String>()
        if kind == .project {
            names.formUnion(ExpenseLedger.defaultProjectNames)
        }
        for dimension in dimensions where dimension.kind == kind && !dimension.isArchived {
            if let name = normalizedDisplayValue(dimension.name) {
                names.insert(name)
            }
        }
        if let current = normalizedDisplayValue(currentValue) {
            names.insert(current)
        }
        if kind == .project {
            names = names.filter { !ExpenseLedger.isCompanyProjectName($0) }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var linkedReceipt: ReceiptAttachment? {
        if let id = expense?.receiptAttachmentID,
           let match = receiptAttachments.first(where: { $0.id == id }) {
            return match
        }
        if let hash = normalizedDisplayValue(expense?.receiptContentHash)?.lowercased(),
           let match = receiptAttachments.first(where: { $0.contentHash.lowercased() == hash }) {
            return match
        }
        if let filename = normalizedDisplayValue(receiptFilename),
           let match = receiptAttachments.first(where: { $0.originalFilename == filename }) {
            return match
        }
        return nil
    }

    private var receiptPreviewURL: URL? {
        receiptURL ?? receiptFileURL(linkedReceipt)
    }

    private var receiptDisplayName: String {
        if let receiptURL {
            return receiptURL.lastPathComponent
        }
        if let linkedReceipt {
            return linkedReceipt.originalFilename
        }
        return normalizedDisplayValue(receiptFilename) ?? "No receipt selected"
    }

    private var receiptSubtitle: String {
        if let linkedReceipt {
            var parts: [String] = ["Stored in local vault"]
            if let merchant = linkedReceipt.extractedMerchant {
                parts.append(merchant)
            }
            if let amount = linkedReceipt.extractedAmount {
                parts.append(amount.currencyFormatted)
            }
            return parts.joined(separator: " · ")
        }
        if receiptURL != nil {
            return "Selected for import when you save"
        }
        if normalizedDisplayValue(receiptFilename) != nil {
            return "No matching local receipt file found"
        }
        return "Attach the source PDF, image, or text receipt for audit evidence."
    }

    private var formTitle: String {
        expense == nil ? "Add Expense" : "Edit Expense"
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
    }

    private func save() {
        guard let parsedAmount else { return }
        let target = expense ?? Expense(
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: parsedAmount
        )

        do {
            let importedAttachment: ReceiptAttachment?
            if let receiptURL {
                let importResult = try ReceiptVault.importReceipt(
                    at: receiptURL,
                    context: modelContext,
                    expense: nil
                )
                if case .duplicateLinked(let expenseID) = importResult.status,
                   expenseID != target.id {
                    receiptImportError = "That receipt is already linked to another expense."
                    return
                }
                importedAttachment = importResult.attachment
            } else {
                importedAttachment = nil
            }

            applyFormFields(to: target)

            if let importedAttachment {
                ReceiptVault.link(attachment: importedAttachment, to: target)
            }
        } catch {
            receiptImportError = error.localizedDescription
            return
        }

        if expense == nil {
            modelContext.insert(target)
        }
        try? RemnantStore.saveLedgerMutation(context: modelContext)
        dismiss()
    }

    private func applyFormFields(to target: Expense) {
        target.date = date
        target.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        target.amount = parsedAmount ?? target.amount
        target.categoryName = categoryName
        target.status = status
        target.note = note
        target.paymentAccount = paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        target.paymentMethod = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        target.vendorName = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.clientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.projectName = ExpenseLedger.isCompanyProjectName(normalizedProjectName) ? "" : normalizedProjectName
        target.isBillable = isBillable
        target.isReimbursable = isReimbursable || status == .reimbursable
        target.taxYear = Calendar.current.component(.year, from: date)
        target.receiptFilename = receiptFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : receiptFilename
        target.updatedAt = Date()
    }

    private func handleReceiptSelection(_ result: Result<[URL], Error>) {
        receiptImportError = nil

        do {
            guard let url = try result.get().first else { return }
            receiptURL = url
            receiptFilename = url.lastPathComponent
        } catch {
            receiptImportError = error.localizedDescription
        }
    }
}

private enum ReceiptPreviewContent {
    case empty
    case missing
    case image(NSImage)
    case text(String)
    case unsupported
}

private struct ReceiptPreviewCard: View {
    let title: String
    let subtitle: String
    let url: URL?
    let onChoose: () -> Void
    let onOpen: (() -> Void)?
    let onReveal: (() -> Void)?

    private var preview: ReceiptPreviewContent {
        ReceiptPreviewRenderer.preview(for: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Label("Receipt Evidence", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button {
                    onChoose()
                } label: {
                    Label("Choose Receipt", systemImage: "doc.badge.plus")
                }
            }

            HStack(alignment: .top, spacing: Spacing.md) {
                previewBody
                    .frame(width: 220, height: 150)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .stroke(.quaternary)
                    }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Spacer(minLength: 0)

                    HStack(spacing: Spacing.sm) {
                        if let onOpen {
                            Button {
                                onOpen()
                            } label: {
                                Label("Open", systemImage: "arrow.up.forward.square")
                            }
                        }
                        if let onReveal {
                            Button {
                                onReveal()
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch preview {
        case .empty:
            receiptPreviewPlaceholder("No receipt", systemImage: "doc")
        case .missing:
            receiptPreviewPlaceholder("File missing", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(6)
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        case .unsupported:
            receiptPreviewPlaceholder("Preview unavailable", systemImage: "doc.questionmark")
        }
    }

    private func receiptPreviewPlaceholder(_ title: String, systemImage: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ReceiptPreviewRenderer {
    static func preview(for url: URL?) -> ReceiptPreviewContent {
        guard let url else { return .empty }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            return .image(page.thumbnail(of: CGSize(width: 440, height: 300), for: .mediaBox))
        }

        if let image = NSImage(contentsOf: url) {
            return .image(image)
        }

        if isTextFile(url),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
            let normalizedText = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return .text(String(normalizedText.prefix(900)))
        }

        return .unsupported
    }

    private static func isTextFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .text)
    }
}
