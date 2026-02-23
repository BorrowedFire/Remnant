import Foundation

@MainActor
final class ImportService {

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case parsingFailed(String)
        case noTransactionsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "Unsupported file format. Use CSV, OFX, or QFX."
            case .parsingFailed(let detail): "Failed to parse file: \(detail)"
            case .noTransactionsFound: "No transactions found in this file."
            }
        }
    }

    func parseFile(at url: URL) throws -> [ImportedTransaction] {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ImportError.parsingFailed("Unable to read file encoding.")
        }

        let transactions: [ImportedTransaction]
        switch ext {
        case "csv":
            transactions = try parseCSV(content)
        case "ofx", "qfx":
            transactions = try parseOFX(content)
        default:
            throw ImportError.unsupportedFormat
        }

        guard !transactions.isEmpty else { throw ImportError.noTransactionsFound }
        return transactions.sorted { $0.date > $1.date }
    }

    // MARK: - CSV Parsing

    private func parseCSV(_ content: String) throws -> [ImportedTransaction] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { throw ImportError.parsingFailed("CSV must have a header row and at least one data row.") }

        let header = parseCSVRow(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let columns = detectCSVColumns(header: header)

        guard let dateCol = columns.date, let amountCol = columns.amount else {
            throw ImportError.parsingFailed("Could not find Date and Amount columns. Expected headers like 'Date', 'Amount', 'Debit', 'Credit'.")
        }

        var transactions: [ImportedTransaction] = []
        for i in 1..<lines.count {
            let fields = parseCSVRow(lines[i])
            guard fields.count > max(dateCol, amountCol, columns.description ?? 0) else { continue }

            guard let date = parseDate(fields[dateCol]) else { continue }

            let (amount, type) = parseCSVAmount(
                fields: fields,
                amountCol: amountCol,
                debitCol: columns.debit,
                creditCol: columns.credit
            )
            guard amount != 0 else { continue }

            let name = columns.description.map { fields[$0].trimmingCharacters(in: .whitespaces) } ?? ""

            transactions.append(ImportedTransaction(
                name: name.isEmpty ? "Unknown" : name,
                amount: abs(amount),
                date: date,
                type: type
            ))
        }
        return transactions
    }

    private struct CSVColumns {
        var date: Int?
        var amount: Int?
        var description: Int?
        var debit: Int?
        var credit: Int?
    }

    private func detectCSVColumns(header: [String]) -> CSVColumns {
        var columns = CSVColumns()
        for (i, col) in header.enumerated() {
            if col.contains("date") || col.contains("posted") {
                columns.date = columns.date ?? i
            } else if col == "amount" || col == "total" {
                columns.amount = columns.amount ?? i
            } else if col.contains("description") || col.contains("memo") || col.contains("name") || col.contains("payee") {
                columns.description = columns.description ?? i
            } else if col == "debit" || col.contains("withdrawal") {
                columns.debit = columns.debit ?? i
            } else if col == "credit" || col.contains("deposit") {
                columns.credit = columns.credit ?? i
            }
        }
        // If no unified amount column, use debit as primary
        if columns.amount == nil, let debit = columns.debit {
            columns.amount = debit
        }
        return columns
    }

    private func parseCSVAmount(fields: [String], amountCol: Int, debitCol: Int?, creditCol: Int?) -> (Decimal, ImportedTransaction.TransactionType) {
        // If separate debit/credit columns
        if let debitCol, let creditCol {
            let debit = parseDecimal(fields[debitCol])
            let credit = parseDecimal(fields[creditCol])
            if debit != 0 {
                return (abs(debit), .debit)
            } else if credit != 0 {
                return (abs(credit), .credit)
            }
        }
        // Single amount column (negative = debit, positive = credit)
        let amount = parseDecimal(fields[amountCol])
        return (abs(amount), amount < 0 ? .debit : .credit)
    }

    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: - OFX/QFX Parsing

    private func parseOFX(_ content: String) throws -> [ImportedTransaction] {
        // Strip OFX/QFX headers (everything before first <)
        guard let xmlStart = content.firstIndex(of: "<") else {
            throw ImportError.parsingFailed("No OFX data found.")
        }
        let xmlContent = String(content[xmlStart...])

        // Extract transaction blocks
        var transactions: [ImportedTransaction] = []
        let pattern = "<STMTTRN>(.*?)</STMTTRN>"
        let closedTagContent = xmlContent
            .replacingOccurrences(of: "<STMTTRN>\n", with: "<STMTTRN>")
            .replacingOccurrences(of: "\n</STMTTRN>", with: "</STMTTRN>")

        // OFX v1 doesn't use closing tags. Handle both formats.
        let blocks = extractOFXBlocks(from: xmlContent)

        for block in blocks {
            let trnType = extractOFXValue("TRNTYPE", from: block)
            let dateStr = extractOFXValue("DTPOSTED", from: block)
            let amountStr = extractOFXValue("TRNAMT", from: block)
            let name = extractOFXValue("NAME", from: block)
                ?? extractOFXValue("MEMO", from: block)
                ?? "Unknown"

            guard let amount = parseDecimal(amountStr ?? ""),
                  let date = parseOFXDate(dateStr ?? "") else { continue }

            let type: ImportedTransaction.TransactionType = amount < 0 ? .debit : .credit

            transactions.append(ImportedTransaction(
                name: name.trimmingCharacters(in: .whitespaces),
                amount: abs(amount),
                date: date,
                type: type
            ))
        }
        return transactions
    }

    private func extractOFXBlocks(from content: String) -> [String] {
        var blocks: [String] = []
        var searchRange = content.startIndex..<content.endIndex

        while let start = content.range(of: "<STMTTRN>", range: searchRange) {
            // Look for closing tag or next opening tag
            let afterStart = start.upperBound
            if let end = content.range(of: "</STMTTRN>", range: afterStart..<content.endIndex) {
                blocks.append(String(content[afterStart..<end.lowerBound]))
                searchRange = end.upperBound..<content.endIndex
            } else if let nextStart = content.range(of: "<STMTTRN>", range: afterStart..<content.endIndex) {
                blocks.append(String(content[afterStart..<nextStart.lowerBound]))
                searchRange = nextStart.lowerBound..<content.endIndex
            } else {
                // Last block without closing tag
                blocks.append(String(content[afterStart...]))
                break
            }
        }
        return blocks
    }

    private func extractOFXValue(_ tag: String, from block: String) -> String? {
        // Match both <TAG>value and <TAG>value</TAG>
        guard let tagRange = block.range(of: "<\(tag)>") else { return nil }
        let afterTag = block[tagRange.upperBound...]
        // Value ends at next < or newline
        let value = afterTag.prefix(while: { $0 != "<" && $0 != "\n" && $0 != "\r" })
        let trimmed = String(value).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let formatters: [String] = [
            "MM/dd/yyyy", "yyyy-MM-dd", "M/d/yyyy", "M/d/yy",
            "MM-dd-yyyy", "dd/MM/yyyy", "yyyy/MM/dd"
        ]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func parseOFXDate(_ string: String) -> Date? {
        // OFX dates: YYYYMMDDHHMMSS or YYYYMMDD
        let digits = string.prefix(8)
        guard digits.count >= 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(digits))
    }

    private func parseDecimal(_ string: String) -> Decimal {
        let cleaned = string
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Decimal(string: cleaned) ?? 0
    }
}
