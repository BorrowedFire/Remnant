import Foundation
import SwiftData

struct EmailReceiptSourceMetadata: Equatable {
    let messageFilename: String
    let subject: String?
    let sender: String?
    let sentDate: Date?
    let messageID: String?
}

struct EmailReceiptAttachmentCandidate: Equatable {
    let filename: String
    let data: Data
    let metadata: EmailReceiptSourceMetadata
}

struct EmailReceiptImportSummary: Equatable {
    let messageCount: Int
    let importedCount: Int
    let duplicateCount: Int
    let skippedAttachmentCount: Int
    let failedFilenames: [String]
}

enum EmailReceiptImportError: LocalizedError {
    case malformedMessage(String)

    var errorDescription: String? {
        switch self {
        case .malformedMessage(let filename):
            "Remnant could not read receipt attachments from \(filename)."
        }
    }
}

@MainActor
enum EmailReceiptImportService {
    private static let supportedAttachmentExtensions: Set<String> = [
        "heic",
        "jpeg",
        "jpg",
        "pdf",
        "png",
        "txt"
    ]

    static func importEMLFiles(
        at urls: [URL],
        context: ModelContext,
        vaultDirectory: URL? = nil
    ) -> EmailReceiptImportSummary {
        var importedCount = 0
        var duplicateCount = 0
        var skippedAttachmentCount = 0
        var failedFilenames: [String] = []

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let attachments = try attachmentCandidates(in: url)
                skippedAttachmentCount += attachments.skippedCount

                for candidate in attachments.candidates {
                    let temporaryURL = try writeTemporaryAttachment(candidate)
                    defer { try? FileManager.default.removeItem(at: temporaryURL.deletingLastPathComponent()) }

                    let result = try ReceiptVault.importReceipt(
                        at: temporaryURL,
                        context: context,
                        vaultDirectory: vaultDirectory
                    )
                    applySourceMetadata(candidate.metadata, to: result.attachment)

                    if result.isDuplicate {
                        duplicateCount += 1
                    } else {
                        importedCount += 1
                    }
                }
            } catch {
                failedFilenames.append(url.lastPathComponent)
            }
        }

        return EmailReceiptImportSummary(
            messageCount: urls.count,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            skippedAttachmentCount: skippedAttachmentCount,
            failedFilenames: failedFilenames
        )
    }

    static func attachmentCandidates(in url: URL) throws -> (candidates: [EmailReceiptAttachmentCandidate], skippedCount: Int) {
        let data = try Data(contentsOf: url)
        guard let rawMessage = messageString(from: data) else {
            throw EmailReceiptImportError.malformedMessage(url.lastPathComponent)
        }

        let entity = try parseEntity(rawMessage, sourceFilename: url.lastPathComponent)
        guard entity.hasHeaderBodySeparator else {
            throw EmailReceiptImportError.malformedMessage(url.lastPathComponent)
        }

        if entity.attachments.isEmpty,
           let bodyEvidence = bodyEvidenceCandidate(from: entity.bodyCandidates, sourceFilename: url.lastPathComponent) {
            return ([bodyEvidence], entity.skippedCount)
        }

        return (entity.attachments, entity.skippedCount)
    }

    private struct ParsedEntity {
        let attachments: [EmailReceiptAttachmentCandidate]
        let bodyCandidates: [EmailReceiptBodyCandidate]
        let skippedCount: Int
        let hasHeaderBodySeparator: Bool
    }

    private struct EmailReceiptBodyCandidate {
        let text: String
        let isHTML: Bool
        let metadata: EmailReceiptSourceMetadata
    }

    private struct ParsedHeaders {
        let values: [String: String]

        subscript(_ key: String) -> String? {
            values[key.lowercased()]
        }
    }

    private static func parseEntity(
        _ rawEntity: String,
        sourceFilename: String,
        inheritedMetadata: EmailReceiptSourceMetadata? = nil
    ) throws -> ParsedEntity {
        guard let split = splitHeadersAndBody(rawEntity) else {
            return ParsedEntity(attachments: [], bodyCandidates: [], skippedCount: 0, hasHeaderBodySeparator: false)
        }

        let headers = parseHeaders(split.headers)
        let metadata = inheritedMetadata ?? EmailReceiptSourceMetadata(
            messageFilename: sourceFilename,
            subject: decodedHeader(headers["subject"]),
            sender: decodedHeader(headers["from"]),
            sentDate: parsedMessageDate(headers["date"]),
            messageID: headers["message-id"]
        )
        let contentType = parsedHeaderValue(headers["content-type"] ?? "text/plain")

        if contentType.value.lowercased().hasPrefix("multipart/"),
           let boundary = contentType.parameters["boundary"] {
            let parts = splitMultipartBody(split.body, boundary: boundary)
            var attachments: [EmailReceiptAttachmentCandidate] = []
            var bodyCandidates: [EmailReceiptBodyCandidate] = []
            var skippedCount = 0

            for part in parts {
                let parsed = try parseEntity(part, sourceFilename: sourceFilename, inheritedMetadata: metadata)
                attachments.append(contentsOf: parsed.attachments)
                bodyCandidates.append(contentsOf: parsed.bodyCandidates)
                skippedCount += parsed.skippedCount
            }

            return ParsedEntity(
                attachments: attachments,
                bodyCandidates: bodyCandidates,
                skippedCount: skippedCount,
                hasHeaderBodySeparator: true
            )
        }

        guard let filename = attachmentFilename(headers: headers) else {
            let bodyCandidates = bodyCandidate(
                from: split.body,
                headers: headers,
                metadata: metadata
            ).map { [$0] } ?? []
            return ParsedEntity(
                attachments: [],
                bodyCandidates: bodyCandidates,
                skippedCount: 0,
                hasHeaderBodySeparator: true
            )
        }

        guard isSupportedAttachment(filename) else {
            return ParsedEntity(attachments: [], bodyCandidates: [], skippedCount: 1, hasHeaderBodySeparator: true)
        }

        guard let attachmentData = decodedBody(split.body, encoding: headers["content-transfer-encoding"]) else {
            return ParsedEntity(attachments: [], bodyCandidates: [], skippedCount: 1, hasHeaderBodySeparator: true)
        }

        return ParsedEntity(
            attachments: [
                EmailReceiptAttachmentCandidate(
                    filename: safeFilename(filename),
                    data: attachmentData,
                    metadata: metadata
                )
            ],
            bodyCandidates: [],
            skippedCount: 0,
            hasHeaderBodySeparator: true
        )
    }

    private static func bodyCandidate(
        from body: String,
        headers: ParsedHeaders,
        metadata: EmailReceiptSourceMetadata
    ) -> EmailReceiptBodyCandidate? {
        let contentType = parsedHeaderValue(headers["content-type"] ?? "text/plain")
        let normalizedContentType = contentType.value.lowercased()
        guard normalizedContentType.hasPrefix("text/plain") || normalizedContentType.hasPrefix("text/html") else {
            return nil
        }
        guard let bodyData = decodedBody(body, encoding: headers["content-transfer-encoding"]),
              let bodyText = messageString(from: bodyData) else {
            return nil
        }

        let normalizedText = normalizedContentType.hasPrefix("text/html")
            ? plainText(fromHTML: bodyText)
            : bodyText
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return EmailReceiptBodyCandidate(
            text: normalizedText,
            isHTML: normalizedContentType.hasPrefix("text/html"),
            metadata: metadata
        )
    }

    private static func bodyEvidenceCandidate(
        from bodyCandidates: [EmailReceiptBodyCandidate],
        sourceFilename: String
    ) -> EmailReceiptAttachmentCandidate? {
        let receiptBodies = bodyCandidates
            .map { candidate in
                (
                    candidate: candidate,
                    text: normalizedReceiptBody(candidate.text),
                    score: bodyEvidenceScore(candidate.text, isHTML: candidate.isHTML)
                )
            }
            .filter { isReceiptLikeBody($0.text) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text.count > rhs.text.count
                }
                return lhs.score > rhs.score
            }

        guard let best = receiptBodies.first else { return nil }
        let metadata = best.candidate.metadata
        let evidenceText = emailEvidenceText(
            body: best.text,
            metadata: metadata,
            sourceFilename: sourceFilename
        )
        guard let evidenceData = evidenceText.data(using: .utf8) else { return nil }

        return EmailReceiptAttachmentCandidate(
            filename: emailEvidenceFilename(metadata: metadata, sourceFilename: sourceFilename),
            data: evidenceData,
            metadata: metadata
        )
    }

    private static func bodyEvidenceScore(_ text: String, isHTML: Bool) -> Int {
        let lowercased = text.lowercased()
        var score = isHTML ? 0 : 10
        for term in ["receipt", "amount paid", "date paid", "payment method", "order number", "order confirmation", "invoice", "total"] {
            if lowercased.contains(term) {
                score += 5
            }
        }
        return score
    }

    private static func isReceiptLikeBody(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let receiptTerms = [
            "receipt",
            "amount paid",
            "date paid",
            "payment method",
            "order number",
            "order confirmation",
            "invoice",
            "view full receipt"
        ]
        guard receiptTerms.contains(where: { lowercased.contains($0) }) else {
            return false
        }

        return lowercased.range(
            of: #"(?:[$€£]\s*)\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\btotal\s*:?\s*\d+\.\d{2}"#,
            options: .regularExpression
        ) != nil
    }

    private static func emailEvidenceText(
        body: String,
        metadata: EmailReceiptSourceMetadata,
        sourceFilename: String
    ) -> String {
        var lines = [
            body,
            "",
            "--- Source Email ---",
            "Source file: \(sourceFilename)"
        ]

        if let subject = metadata.subject {
            lines.append("Subject: \(subject)")
        }
        if let sender = metadata.sender {
            lines.append("From: \(sender)")
        }
        if let sentDate = metadata.sentDate {
            lines.append("Date: \(evidenceDateFormatter.string(from: sentDate))")
        }
        if let messageID = metadata.messageID {
            lines.append("Message-ID: \(messageID)")
        }

        return lines.joined(separator: "\n")
    }

    private static func emailEvidenceFilename(
        metadata: EmailReceiptSourceMetadata,
        sourceFilename: String
    ) -> String {
        let subject = metadata.subject ?? (sourceFilename as NSString).deletingPathExtension
        let stem = safeEvidenceFilenameStem(subject)
        let datePrefix = metadata.sentDate.map { filenameDateFormatter.string(from: $0) }
        return ([datePrefix, stem, "email-receipt"].compactMap(\.self).joined(separator: "-") + ".txt")
    }

    private static func safeEvidenceFilenameStem(_ value: String) -> String {
        let ascii = value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let cleaned = ascii
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = cleaned.isEmpty ? "email" : cleaned
        return String(stem.prefix(72)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func normalizedReceiptBody(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?is)<(script|style).*?</\1>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</p>|</div>|</tr>|</li>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeHTMLEntities(text)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func splitHeadersAndBody(_ rawEntity: String) -> (headers: String, body: String)? {
        let normalized = rawEntity
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let range = normalized.range(of: "\n\n") else { return nil }
        return (
            headers: String(normalized[..<range.lowerBound]),
            body: String(normalized[range.upperBound...])
        )
    }

    private static func parseHeaders(_ headerText: String) -> ParsedHeaders {
        var unfoldedLines: [String] = []
        for line in headerText.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard let last = unfoldedLines.popLast() else { continue }
                unfoldedLines.append(last + " " + line.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                unfoldedLines.append(line)
            }
        }

        var values: [String: String] = [:]
        for line in unfoldedLines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                values[key] = String(value)
            }
        }

        return ParsedHeaders(values: values)
    }

    private static func parsedHeaderValue(_ value: String) -> (value: String, parameters: [String: String]) {
        let pieces = splitHeaderParameters(value)
        let baseValue = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
        var parameters: [String: String] = [:]

        for parameter in pieces.dropFirst() {
            guard let separator = parameter.firstIndex(of: "=") else { continue }
            let key = parameter[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parameter[parameter.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            parameters[key] = decodedParameterValue(String(value))
        }

        return (baseValue, parameters)
    }

    private static func splitHeaderParameters(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isQuoted = false

        for character in value {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character == ";", !isQuoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func splitMultipartBody(_ body: String, boundary: String) -> [String] {
        let delimiter = "--\(boundary)"
        let closingDelimiter = "--\(boundary)--"
        var parts: [String] = []
        var current: [String] = []
        var isCapturing = false

        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .newlines)
            if line == delimiter {
                if isCapturing, !current.isEmpty {
                    parts.append(current.joined(separator: "\n"))
                }
                current = []
                isCapturing = true
            } else if line == closingDelimiter {
                if isCapturing, !current.isEmpty {
                    parts.append(current.joined(separator: "\n"))
                }
                break
            } else if isCapturing {
                current.append(rawLine)
            }
        }

        return parts
    }

    private static func attachmentFilename(headers: ParsedHeaders) -> String? {
        if let disposition = headers["content-disposition"] {
            let parsedDisposition = parsedHeaderValue(disposition)
            if let filename = parsedDisposition.parameters["filename*"] ?? parsedDisposition.parameters["filename"] {
                return filename
            }
        }

        if let contentType = headers["content-type"] {
            let parsedContentType = parsedHeaderValue(contentType)
            if let filename = parsedContentType.parameters["name*"] ?? parsedContentType.parameters["name"] {
                return filename
            }
        }

        return nil
    }

    private static func decodedBody(_ body: String, encoding: String?) -> Data? {
        let normalizedEncoding = encoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedEncoding {
        case "base64":
            let base64 = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: base64)
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body.data(using: .utf8)
        }
    }

    private static func decodeQuotedPrintable(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "=") {
                if index + 1 < bytes.count,
                   bytes[index + 1] == UInt8(ascii: "\n") {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count,
                   let high = hexValue(bytes[index + 1]),
                   let low = hexValue(bytes[index + 2]) {
                    decoded.append((high << 4) | low)
                    index += 3
                    continue
                }
            }

            decoded.append(byte)
            index += 1
        }

        return Data(decoded)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            byte - UInt8(ascii: "a") + 10
        default:
            nil
        }
    }

    private static func decodedParameterValue(_ value: String) -> String {
        let unquoted = stripQuotes(value)
        if let separator = unquoted.range(of: "''") {
            let encodedValue = String(unquoted[separator.upperBound...])
            return encodedValue.removingPercentEncoding ?? encodedValue
        }
        return decodedHeader(unquoted) ?? unquoted
    }

    private static func decodedHeader(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.hasPrefix("=?"), value.hasSuffix("?=") else { return value }
        let trimmed = value.dropFirst(2).dropLast(2)
        let pieces = trimmed.components(separatedBy: "?")
        guard pieces.count == 3 else { return value }

        let charset = pieces[0].lowercased()
        let encoding = pieces[1].lowercased()
        let encodedValue = pieces[2]
        let stringEncoding: String.Encoding = charset.contains("iso-8859-1") ? .isoLatin1 : .utf8

        if encoding == "b",
           let data = Data(base64Encoded: encodedValue),
           let decoded = String(data: data, encoding: stringEncoding) {
            return decoded
        }

        if encoding == "q",
           let decoded = String(data: decodeQuotedPrintable(encodedValue.replacingOccurrences(of: "_", with: " ")), encoding: stringEncoding) {
            return decoded
        }

        return value
    }

    private static func parsedMessageDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z"
        ]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func writeTemporaryAttachment(_ candidate: EmailReceiptAttachmentCandidate) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remnant-eml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(candidate.filename)
        try candidate.data.write(to: url, options: .atomic)
        return url
    }

    private static func applySourceMetadata(
        _ metadata: EmailReceiptSourceMetadata,
        to attachment: ReceiptAttachment
    ) {
        if attachment.sourceMessageFilename == nil {
            attachment.sourceMessageFilename = metadata.messageFilename
        }
        if attachment.sourceMessageSubject == nil {
            attachment.sourceMessageSubject = metadata.subject
        }
        if attachment.sourceMessageSender == nil {
            attachment.sourceMessageSender = metadata.sender
        }
        if attachment.sourceMessageDate == nil {
            attachment.sourceMessageDate = metadata.sentDate
        }
        if attachment.sourceMessageID == nil {
            attachment.sourceMessageID = metadata.messageID
        }
    }

    private static var evidenceDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter
    }

    private static var filenameDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func messageString(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func safeFilename(_ filename: String) -> String {
        let lastPathComponent = (filename as NSString).lastPathComponent
        let trimmed = lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "receipt" : trimmed
    }

    private static func stripQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count >= 2 {
            result.removeFirst()
            result.removeLast()
        }
        return result
    }

    private static func isSupportedAttachment(_ filename: String) -> Bool {
        supportedAttachmentExtensions.contains((filename as NSString).pathExtension.lowercased())
    }
}
