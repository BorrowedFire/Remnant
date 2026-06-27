import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

struct ReceiptMetadata {
    let merchant: String?
    let date: Date?
    let amount: Decimal?
    let confidence: Double
    let sourceText: String
}

enum ReceiptMetadataExtractor {
    static func extract(from sourceURL: URL, data: Data) -> ReceiptMetadata {
        let text = textContent(from: sourceURL, data: data)
        return parse(text: text, fallbackFilename: sourceURL.lastPathComponent)
    }

    static func parse(text: String, fallbackFilename: String) -> ReceiptMetadata {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchant = merchant(in: normalizedText) ?? merchant(fromFilename: fallbackFilename)
        let date = date(in: normalizedText)
        let amount = amount(in: normalizedText)

        var confidence = 0.0
        if merchant != nil {
            confidence += normalizedText.isEmpty ? 0.15 : 0.25
        }
        if date != nil {
            confidence += 0.30
        }
        if amount != nil {
            confidence += 0.40
        }

        return ReceiptMetadata(
            merchant: merchant,
            date: date,
            amount: amount,
            confidence: min(confidence, 0.95),
            sourceText: normalizedText
        )
    }

    private static func textContent(from sourceURL: URL, data: Data) -> String {
        let pathExtension = sourceURL.pathExtension.lowercased()

        #if canImport(PDFKit)
        if pathExtension == "pdf", let document = PDFDocument(data: data) {
            return (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
        }
        #endif

        let textExtensions = Set(["csv", "text", "txt"])
        guard textExtensions.contains(pathExtension) else {
            return ""
        }

        for encoding in [String.Encoding.utf8, .utf16, .ascii, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        return ""
    }

    private static func merchant(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { cleanLine($0) }
            .first { isMerchantCandidate($0) }
    }

    private static func isMerchantCandidate(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= 80 else { return false }

        let lowercased = line.lowercased()
        let blockedTerms = [
            "receipt", "invoice", "order", "subtotal", "total", "amount", "date",
            "payment", "paid", "balance", "transaction", "card", "visa",
            "mastercard", "amex", "tax", "tip"
        ]
        guard !blockedTerms.contains(where: { lowercased.contains($0) }) else {
            return false
        }
        guard date(in: line) == nil, amount(in: line) == nil else {
            return false
        }

        let alphanumerics = line.filter { $0.isLetter || $0.isNumber }
        guard !alphanumerics.isEmpty else { return false }
        let digitCount = alphanumerics.filter(\.isNumber).count
        return Double(digitCount) / Double(alphanumerics.count) < 0.5
    }

    private static func merchant(fromFilename filename: String) -> String? {
        var stem = (filename as NSString).deletingPathExtension
        stem = replacingMatches(
            in: stem,
            pattern: #"\b\d{4}[-_]\d{1,2}[-_]\d{1,2}\b|\b\d{1,2}[-_]\d{1,2}[-_]\d{2,4}\b"#,
            with: " "
        )
        stem = replacingMatches(in: stem, pattern: #"[-_]+"#, with: " ")
        stem = replacingMatches(in: stem, pattern: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stem.isEmpty else { return nil }
        return stem.capitalized
    }

    private static func date(in text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        var best: (date: Date, priority: Int, order: Int)?
        var order = 0

        for line in lines.isEmpty ? [text] : lines {
            let lowercased = line.lowercased()
            let priority = lowercased.contains("date")
                || lowercased.contains("paid")
                || lowercased.contains("transaction") ? 1 : 0

            for candidate in dateCandidates(in: line) {
                if let parsed = parseDate(candidate) {
                    let current = (date: parsed, priority: priority, order: order)
                    if best == nil
                        || current.priority > best!.priority
                        || (current.priority == best!.priority && current.order < best!.order) {
                        best = current
                    }
                    order += 1
                }
            }
        }

        return best?.date
    }

    private static func dateCandidates(in text: String) -> [String] {
        let patterns = [
            #"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"#,
            #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,
            #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}\b"#
        ]

        return patterns.flatMap { matches(in: text, pattern: $0) }
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let value = rawValue.replacingOccurrences(of: ".", with: "")
        let formats = [
            "yyyy-MM-dd", "yyyy/M/d", "yyyy/MM/dd",
            "M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MM/dd/yy",
            "MMM d yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMMM d, yyyy"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func amount(in text: String) -> Decimal? {
        let lines = text.components(separatedBy: .newlines)
        var best: (amount: Decimal, priority: Int)?

        for line in lines.isEmpty ? [text] : lines {
            let lowercased = line.lowercased()
            var priority = 0
            if lowercased.contains("grand total")
                || lowercased.contains("amount paid")
                || lowercased.contains("total")
                || lowercased.contains("paid")
                || lowercased.contains("charged")
                || lowercased.contains("charge")
                || lowercased.contains("amount") {
                priority += 10
            }
            if lowercased.contains("subtotal") || lowercased.contains("tax") || lowercased.contains("tip") {
                priority -= 4
            }

            for candidate in amountCandidates(in: line) {
                guard var value = decimal(from: candidate) else { continue }
                if value < 0 {
                    value *= -1
                }

                if best == nil
                    || priority > best!.priority
                    || (priority == best!.priority && value > best!.amount) {
                    best = (value, priority)
                }
            }
        }

        return best?.amount
    }

    private static func amountCandidates(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"[$€£]?\s*\(?-?\d{1,3}(?:,\d{3})*(?:\.\d{2})\)?|[$€£]?\s*\(?-?\d+\.\d{2}\)?"#
        )
    }

    private static func decimal(from rawValue: String) -> Decimal? {
        let cleaned = rawValue
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func cleanLine(_ line: String) -> String {
        replacingMatches(in: line, pattern: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
