import Foundation

struct ExpenseImportCandidate: Identifiable {
    let id = UUID()
    let expense: Expense
    let sourceRow: Int
    let rawMerchant: String
    let duplicateOf: Expense?
}

struct ExpenseImportSummary {
    let sourceName: String
    let activeProfileName: String?
    let columnMapping: CSVColumnMapping
    let rowCount: Int
    let accepted: [ExpenseImportCandidate]
    let duplicates: [ExpenseImportCandidate]
    let ignoredRows: [Int]
    let notes: [String]
}

enum ExpenseImportError: LocalizedError {
    case unreadableFile
    case missingRequiredColumns

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The file could not be read as UTF-8 or ASCII text."
        case .missingRequiredColumns:
            "The CSV needs date, merchant or description, and amount or debit/credit columns."
        }
    }
}

@MainActor
enum ExpenseImportService {
    static func previewCSV(
        at url: URL,
        existingExpenses: [Expense],
        source: ExpenseSource,
        defaultStatus: ExpenseStatus = .draft,
        profile: CSVImportProfile? = nil,
        vendorRules: [VendorRule] = []
    ) throws -> ExpenseImportSummary {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ExpenseImportError.unreadableFile
        }

        let rows = parseCSV(content)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let header = rows.first else { throw ExpenseImportError.unreadableFile }

        let autoColumns = detectColumns(header)
        let columns = columns(from: profile?.mapping, header: header, fallback: autoColumns)
        guard let dateColumn = columns.date,
              let merchantColumn = columns.merchant,
              columns.amount != nil || columns.debit != nil || columns.credit != nil else {
            throw ExpenseImportError.missingRequiredColumns
        }

        var accepted: [ExpenseImportCandidate] = []
        var duplicates: [ExpenseImportCandidate] = []
        var ignoredRows: [Int] = []
        var notes: [String] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let sourceRow = offset + 2
            guard let date = parseDate(value(row, at: dateColumn)),
                  let merchant = nonBlank(value(row, at: merchantColumn)),
                  let amount = expenseAmount(row: row, columns: columns) else {
                ignoredRows.append(sourceRow)
                continue
            }

            if amount == 0 {
                ignoredRows.append(sourceRow)
                continue
            }

            let importedCategory = nonBlank(value(row, at: columns.category))
            let ruleCategory = VendorRuleMatcher.categoryName(for: merchant, rules: vendorRules)

            let expense = Expense(
                date: date,
                merchant: merchant,
                amount: amount,
                currencyCode: currencyCode(value(row, at: columns.currency)),
                categoryName: importedCategory ?? ruleCategory ?? "Uncategorized",
                note: nonBlank(value(row, at: columns.note)) ?? "",
                paymentAccount: nonBlank(value(row, at: columns.account)) ?? "",
                paymentMethod: nonBlank(value(row, at: columns.paymentMethod)) ?? "",
                status: defaultStatus,
                source: source,
                receiptFilename: nonBlank(value(row, at: columns.receipt))
            )

            let candidate = ExpenseImportCandidate(
                expense: expense,
                sourceRow: sourceRow,
                rawMerchant: merchant,
                duplicateOf: ExpenseLedger.possibleDuplicate(
                    of: expense,
                    in: existingExpenses + accepted.map(\.expense)
                )
            )

            if candidate.duplicateOf == nil {
                accepted.append(candidate)
            } else {
                duplicates.append(candidate)
            }
        }

        if ignoredRows.isEmpty == false {
            notes.append("\(ignoredRows.count) rows were skipped because they were credits or missing required values.")
        }
        if duplicates.isEmpty == false {
            notes.append("\(duplicates.count) possible duplicates were kept out of the import.")
        }

        return ExpenseImportSummary(
            sourceName: url.lastPathComponent,
            activeProfileName: profile?.name,
            columnMapping: mapping(from: columns, header: header),
            rowCount: max(rows.count - 1, 0),
            accepted: accepted,
            duplicates: duplicates,
            ignoredRows: ignoredRows,
            notes: notes
        )
    }

    private struct Columns {
        var date: Int?
        var merchant: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
        var category: Int?
        var account: Int?
        var paymentMethod: Int?
        var note: Int?
        var receipt: Int?
        var transactionType: Int?
        var direction: Int?
        var currency: Int?
    }

    private static func detectColumns(_ header: [String]) -> Columns {
        var columns = Columns()
        for (index, rawName) in header.enumerated() {
            let name = normalizeHeader(rawName)
            switch name {
            case "date", "transaction date", "posted date", "post date", "settled date", "payment date", "expense date":
                columns.date = columns.date ?? index
            case "merchant", "merchant name", "description", "payee", "payee name", "name", "vendor", "vendor name", "supplier", "supplier name":
                columns.merchant = columns.merchant ?? index
            case "amount", "total", "transaction amount", "net amount", "expense amount", "paid amount", "value":
                columns.amount = columns.amount ?? index
            case "debit", "withdrawal", "withdrawals", "spent", "money out", "outflow", "charge", "charges", "paid":
                columns.debit = columns.debit ?? index
            case "credit", "deposit", "deposits", "received", "money in", "inflow", "refund", "refunds":
                columns.credit = columns.credit ?? index
            case "category", "expense category", "account category", "business category":
                columns.category = columns.category ?? index
            case "account", "payment account", "paid through", "bank account", "card account":
                columns.account = columns.account ?? index
            case "payment method", "method", "payment type", "paid by":
                columns.paymentMethod = columns.paymentMethod ?? index
            case "note", "memo", "notes", "details", "comments":
                columns.note = columns.note ?? index
            case "receipt", "receipt filename", "receipt attachment", "attachment", "attachments", "file":
                columns.receipt = columns.receipt ?? index
            case "type", "transaction type", "kind", "transaction kind", "entry type":
                columns.transactionType = columns.transactionType ?? index
            case "direction", "transaction direction", "flow":
                columns.direction = columns.direction ?? index
            case "currency", "currency code":
                columns.currency = columns.currency ?? index
            default:
                break
            }
        }
        return columns
    }

    private static func columns(
        from mapping: CSVColumnMapping?,
        header: [String],
        fallback: Columns
    ) -> Columns {
        guard let mapping else { return fallback }
        var columns = fallback
        apply(mapping.dateHeader, to: &columns.date, header: header)
        apply(mapping.merchantHeader, to: &columns.merchant, header: header)
        apply(mapping.amountHeader, to: &columns.amount, header: header)
        apply(mapping.debitHeader, to: &columns.debit, header: header)
        apply(mapping.creditHeader, to: &columns.credit, header: header)
        apply(mapping.categoryHeader, to: &columns.category, header: header)
        apply(mapping.accountHeader, to: &columns.account, header: header)
        apply(mapping.paymentMethodHeader, to: &columns.paymentMethod, header: header)
        apply(mapping.noteHeader, to: &columns.note, header: header)
        apply(mapping.receiptHeader, to: &columns.receipt, header: header)
        apply(mapping.transactionTypeHeader, to: &columns.transactionType, header: header)
        apply(mapping.directionHeader, to: &columns.direction, header: header)
        apply(mapping.currencyHeader, to: &columns.currency, header: header)
        return columns
    }

    private static func apply(_ mappedHeader: String, to column: inout Int?, header: [String]) {
        guard let index = index(of: mappedHeader, in: header) else { return }
        column = index
    }

    private static func index(of mappedHeader: String, in header: [String]) -> Int? {
        let normalizedMappedHeader = normalizeHeader(mappedHeader)
        guard !normalizedMappedHeader.isEmpty else { return nil }
        return header.firstIndex { normalizeHeader($0) == normalizedMappedHeader }
    }

    private static func mapping(from columns: Columns, header: [String]) -> CSVColumnMapping {
        CSVColumnMapping(
            dateHeader: value(header, at: columns.date) ?? "",
            merchantHeader: value(header, at: columns.merchant) ?? "",
            amountHeader: value(header, at: columns.amount) ?? "",
            debitHeader: value(header, at: columns.debit) ?? "",
            creditHeader: value(header, at: columns.credit) ?? "",
            categoryHeader: value(header, at: columns.category) ?? "",
            accountHeader: value(header, at: columns.account) ?? "",
            paymentMethodHeader: value(header, at: columns.paymentMethod) ?? "",
            noteHeader: value(header, at: columns.note) ?? "",
            receiptHeader: value(header, at: columns.receipt) ?? "",
            transactionTypeHeader: value(header, at: columns.transactionType) ?? "",
            directionHeader: value(header, at: columns.direction) ?? "",
            currencyHeader: value(header, at: columns.currency) ?? ""
        )
    }

    private static func expenseAmount(row: [String], columns: Columns) -> Decimal? {
        if shouldSkipTransaction(row: row, columns: columns) {
            return nil
        }
        if let credit = parseDecimal(value(row, at: columns.credit)), credit != 0 {
            return nil
        }
        if let debit = parseDecimal(value(row, at: columns.debit)), debit != 0 {
            return abs(debit)
        }
        if let amount = parseDecimal(value(row, at: columns.amount)) {
            return abs(amount)
        }
        return nil
    }

    private static func shouldSkipTransaction(row: [String], columns: Columns) -> Bool {
        [columns.transactionType, columns.direction]
            .compactMap { nonBlank(value(row, at: $0)) }
            .map(normalizeHeader)
            .contains(where: isNonExpenseTransactionKind)
    }

    private static func isNonExpenseTransactionKind(_ value: String) -> Bool {
        let exactMatches = Set([
            "credit",
            "deposit",
            "income",
            "money in",
            "inflow",
            "owner investment",
            "revenue",
            "sales"
        ])
        guard !exactMatches.contains(value) else { return true }

        let substrings = [
            "refund",
            "reimbursement",
            "payment received",
            "transfer"
        ]
        return substrings.contains { value.contains($0) }
    }

    private static func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]

            if character == "\"" {
                let next = content.index(after: index)
                if isQuoted, next < content.endIndex, content[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    isQuoted.toggle()
                }
            } else if character == "," && !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n" && !isQuoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character == "\r" && !isQuoted {
                let next = content.index(after: index)
                if next < content.endIndex, content[next] == "\n" {
                    index = next
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index = content.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = nonBlank(value) else { return nil }
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func parseDecimal(_ value: String?) -> Decimal? {
        guard var value = nonBlank(value) else { return nil }
        value = value.replacingOccurrences(of: "\u{FEFF}", with: "")
        var isNegativeParentheses = false
        if value.hasPrefix("("), value.hasSuffix(")") {
            isNegativeParentheses = true
            value.removeFirst()
            value.removeLast()
        }
        let isNegativeSign = value.contains("-") || value.contains("−")
        let cleaned = value.filter { $0.isNumber || $0 == "." }
        guard var decimal = Decimal(string: cleaned) else { return nil }
        if isNegativeParentheses || isNegativeSign {
            decimal *= -1
        }
        return decimal
    }

    private static func currencyCode(_ value: String?) -> String {
        guard let value = nonBlank(value) else { return "USD" }
        let letters = value.uppercased().filter(\.isLetter)
        guard letters.count >= 3 else { return "USD" }
        return String(letters.prefix(3))
    }

    private static func value(_ row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        return row[index]
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
