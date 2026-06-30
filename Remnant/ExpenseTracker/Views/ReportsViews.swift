import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum ReportExportScope: String, CaseIterable, Identifiable {
    case all
    case billableOrReimbursable
    case billable
    case reimbursable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Expenses"
        case .billableOrReimbursable: "Billable/Reimbursable"
        case .billable: "Billable"
        case .reimbursable: "Reimbursable"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .all: "all"
        case .billableOrReimbursable: "follow-up-expenses"
        case .billable: "billable-expenses"
        case .reimbursable: "reimbursable-expenses"
        }
    }

    @MainActor
    func expenses(in expenses: [Expense]) -> [Expense] {
        switch self {
        case .all:
            expenses
        case .billableOrReimbursable:
            ExpenseLedger.outstandingFollowUpExpenses(in: expenses)
        case .billable:
            ExpenseLedger.outstandingBillableExpenses(in: expenses)
        case .reimbursable:
            ExpenseLedger.outstandingReimbursableExpenses(in: expenses)
        }
    }
}

private enum ReportExportKind: String, CaseIterable, Identifiable {
    case rawExpenses
    case taxBucketSummary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rawExpenses: "Raw Expenses"
        case .taxBucketSummary: "Tax Summary"
        }
    }

    var filenameSuffix: String {
        switch self {
        case .rawExpenses: "expenses"
        case .taxBucketSummary: "tax-bucket-summary"
        }
    }
}

enum ReportDateRange: String, CaseIterable, Identifiable {
    case taxYear
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taxYear: "Tax Year"
        case .custom: "Custom Dates"
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var appState: RemnantAppState
    @Query(sort: [SortDescriptor(\Expense.date, order: .reverse)])
    private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder)])
    private var categories: [ExpenseCategory]
    @Query(sort: [SortDescriptor(\ReceiptAttachment.importedAt, order: .reverse)])
    private var receiptAttachments: [ReceiptAttachment]

    @Binding var taxYear: Int
    @Binding var dateRange: ReportDateRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @State private var exportKind = ReportExportKind.rawExpenses
    @State private var exportScope = ReportExportScope.all
    @State private var isExportingCSV = false
    @State private var lastCSVExportURL: URL?
    @State private var lastAuditPackageURL: URL?
    @State private var exportNotice: String?
    @State private var auditPackageNotice: String?
    @State private var exportError: String?

    init(
        taxYear: Binding<Int>,
        dateRange: Binding<ReportDateRange>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>
    ) {
        _taxYear = taxYear
        _dateRange = dateRange
        _customStartDate = customStartDate
        _customEndDate = customEndDate
    }

    private var selectedInterval: DateInterval {
        switch dateRange {
        case .taxYear:
            return ExpenseLedger.yearInterval(taxYear)
        case .custom:
            let range = normalizedCustomRange
            return DateInterval(
                start: range.start,
                end: Calendar.current.date(byAdding: .day, value: 1, to: range.end) ?? range.end.addingTimeInterval(86_400)
            )
        }
    }

    private var normalizedCustomRange: (start: Date, end: Date) {
        let orderedStart = min(customStartDate, customEndDate)
        let orderedEnd = max(customStartDate, customEndDate)
        return (
            start: Calendar.current.startOfDay(for: orderedStart),
            end: Calendar.current.startOfDay(for: orderedEnd)
        )
    }

    private var expensesForRange: [Expense] {
        let interval = selectedInterval
        return expenses.filter { interval.contains($0.date) && $0.status != .ignored }
    }

    private var expensesForExport: [Expense] {
        exportScope.expenses(in: expensesForRange)
    }

    private var exportCSV: String {
        switch exportKind {
        case .rawExpenses:
            ExpenseLedger.exportCSV(expenses: expensesForExport, categories: categories)
        case .taxBucketSummary:
            ExpenseLedger.exportTaxBucketSummaryCSV(expenses: expensesForExport, categories: categories)
        }
    }

    private var exportFilename: String {
        "remnant-\(rangeFilenameSuffix)-\(exportScope.filenameSuffix)-\(exportKind.filenameSuffix).csv"
    }

    private var auditPackageFilename: String {
        "remnant-\(rangeFilenameSuffix)-\(exportScope.filenameSuffix)-audit.\(AuditPackageService.packageExtension)"
    }

    private var rangeFilenameSuffix: String {
        switch dateRange {
        case .taxYear:
            return "\(taxYear)"
        case .custom:
            let range = normalizedCustomRange
            return "\(filenameDateFormatter.string(from: range.start))-\(filenameDateFormatter.string(from: range.end))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header("Reports", subtitle: "Exportable summaries for accountant and tax review.")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(ReportDateRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    Picker("Tax Year", selection: $taxYear) {
                        ForEach((2023...Calendar.current.component(.year, from: Date()) + 1), id: \.self) { year in
                            Text("\(year)").tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .disabled(dateRange != .taxYear)

                    if dateRange == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                            .frame(width: 180)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                            .frame(width: 180)
                    }
                }

                HStack(spacing: Spacing.md) {
                    Picker("Export", selection: $exportKind) {
                        ForEach(ReportExportKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    Picker("Export Scope", selection: $exportScope) {
                        ForEach(ReportExportScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
            }

            HStack(spacing: Spacing.lg) {
                metric("Range Total", ExpenseLedger.totalSpent(in: expenses, for: selectedInterval).currencyFormatted)
                metric("Export Rows", "\(expensesForExport.count)")
            }

            HStack {
                Button {
                    isExportingCSV = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(expensesForExport.isEmpty)

                Button {
                    exportAuditPackage()
                } label: {
                    Label("Export Audit Package", systemImage: "archivebox")
                }
                .disabled(expensesForExport.isEmpty)

                if let lastCSVExportURL {
                    Button {
                        revealFile(lastCSVExportURL)
                    } label: {
                        Label("Show CSV", systemImage: "folder")
                    }
                }

                if let lastAuditPackageURL {
                    Button {
                        revealFile(lastAuditPackageURL)
                    } label: {
                        Label("Show Audit Package", systemImage: "folder")
                    }
                }
            }

            HStack {
                if let exportNotice {
                    Text(exportNotice)
                        .foregroundStyle(.secondary)
                }

                if let auditPackageNotice {
                    Text(auditPackageNotice)
                        .foregroundStyle(.secondary)
                }

                if let exportError {
                    Text(exportError)
                        .foregroundStyle(.red)
                }
            }

            Text("CSV Preview")
                .font(.headline)
            Text(exportCSV)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .padding(24)
        .fileExporter(
            isPresented: $isExportingCSV,
            document: ExpenseCSVDocument(csv: exportCSV),
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
                exportNotice = nil
            } else {
                if case .success(let url) = result {
                    lastCSVExportURL = url
                    exportNotice = "Exported \(url.lastPathComponent)."
                }
                exportError = nil
            }
        }
        .onChange(of: appState.commandRequest) { _, request in
            guard let request else { return }
            guard appState.selectedSection == .reports else { return }
            switch request.kind {
            case .focusSearch:
                break
            case .importFiles:
                appState.selectedSection = .imports
            case .exportReport:
                isExportingCSV = !expensesForExport.isEmpty
            }
        }
    }

    private var filenameDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func exportAuditPackage() {
        exportError = nil
        auditPackageNotice = nil
        exportNotice = nil

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = auditPackageFilename

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                do {
                    let summary = try AuditPackageService.createPackage(
                        at: url,
                        expenses: expensesForExport,
                        categories: categories,
                        attachments: receiptAttachments,
                        allowOverwrite: true
                    )
                    var parts = [
                        "Exported \(summary.expenseCount) expenses",
                        "\(summary.copiedReceiptCount) receipts"
                    ]
                    if summary.missingReceiptCount > 0 {
                        parts.append("\(summary.missingReceiptCount) missing receipts")
                    }
                    auditPackageNotice = parts.joined(separator: ", ") + "."
                    lastAuditPackageURL = url
                    exportError = nil
                } catch {
                    exportError = error.localizedDescription
                    auditPackageNotice = nil
                }
            }
        }
    }
}
