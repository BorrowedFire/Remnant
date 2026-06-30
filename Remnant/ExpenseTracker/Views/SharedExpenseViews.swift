import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct ExpenseRow: View {
    let expense: Expense
    let receipt: ReceiptAttachment?
    let onEdit: () -> Void
    let onOpenReceipt: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.merchant)
                    .font(.body.weight(.medium))
                Text("\(expense.date.mediumFormatted) · \(expense.categoryName ?? "Uncategorized")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.status.label)
                .font(.caption)
                .foregroundStyle(expense.status == .reviewed ? .green : .secondary)
            if expense.isBillable {
                Image(systemName: "briefcase")
                    .foregroundStyle(.secondary)
                    .help("Billable")
            }
            if ExpenseLedger.isReimbursable(expense) {
                Image(systemName: "arrow.uturn.left.circle")
                    .foregroundStyle(.secondary)
                    .help("Reimbursable")
            }
            if isMissingReceipt {
                Image(systemName: "doc.badge.clock")
                    .foregroundStyle(.secondary)
                    .help("Missing receipt")
            }
            Text(expense.amount.currencyFormatted)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
            if let onOpenReceipt {
                Button(action: onOpenReceipt) {
                    Label("Open Receipt", systemImage: "arrow.up.forward.square")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(receiptFileExists(receipt) ? "Open receipt" : "Receipt file is missing")
                .disabled(!receiptFileExists(receipt))
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Edit expense")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit()
        }
    }

    private var isMissingReceipt: Bool {
        expense.receiptFilename == nil
            && expense.receiptAttachmentID == nil
            && expense.receiptContentHash == nil
    }
}

extension ExpenseStatus {
    var label: String {
        switch self {
        case .draft: "Draft"
        case .reviewed: "Reviewed"
        case .reimbursable: "Reimbursable"
        case .ignored: "Ignored"
        }
    }
}

extension ExpenseSource {
    var label: String {
        switch self {
        case .manual: "Manual"
        case .csvImport: "CSV Import"
        case .waveImport: "Wave Import"
        case .receiptDraft: "Receipt Draft"
        }
    }
}

extension ExpenseReviewIssue {
    var label: String {
        switch self {
        case .importedDraft: "Imported Draft"
        case .missingReceipt: "Missing Receipt"
        case .uncategorized: "Uncategorized"
        case .duplicateCandidate: "Duplicate"
        case .manualReview: "Draft Review"
        }
    }

    var systemImage: String {
        switch self {
        case .importedDraft: "tray.and.arrow.down"
        case .missingReceipt: "doc.badge.clock"
        case .uncategorized: "questionmark.folder"
        case .duplicateCandidate: "doc.on.doc"
        case .manualReview: "checklist"
        }
    }
}

func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title)
            .font(.largeTitle.weight(.semibold))
        Text(subtitle)
            .foregroundStyle(.secondary)
    }
}

func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.title2.monospacedDigit().weight(.semibold))
    }
    .padding(14)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
}

func emptyState(_ title: String, _ subtitle: String) -> some View {
    ContentUnavailableView(title, systemImage: "tray", description: Text(subtitle))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

func receiptFileURL(_ attachment: ReceiptAttachment?) -> URL? {
    guard let attachment else { return nil }
    let url = URL(fileURLWithPath: attachment.localPath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

func receiptFileExists(_ attachment: ReceiptAttachment?) -> Bool {
    receiptFileURL(attachment) != nil
}

func openReceiptFile(_ attachment: ReceiptAttachment) {
    guard let url = receiptFileURL(attachment) else { return }
    NSWorkspace.shared.open(url)
}

func revealReceiptFile(_ attachment: ReceiptAttachment) {
    guard let url = receiptFileURL(attachment) else { return }
    revealFile(url)
}

func revealFile(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func normalizedDisplayValue(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}
