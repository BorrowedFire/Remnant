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
        return (entity.attachments, entity.skippedCount)
    }

    private struct ParsedEntity {
        let attachments: [EmailReceiptAttachmentCandidate]
        let skippedCount: Int
        let hasHeaderBodySeparator: Bool
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
            return ParsedEntity(attachments: [], skippedCount: 0, hasHeaderBodySeparator: false)
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
            var skippedCount = 0

            for part in parts {
                let parsed = try parseEntity(part, sourceFilename: sourceFilename, inheritedMetadata: metadata)
                attachments.append(contentsOf: parsed.attachments)
                skippedCount += parsed.skippedCount
            }

            return ParsedEntity(attachments: attachments, skippedCount: skippedCount, hasHeaderBodySeparator: true)
        }

        guard let filename = attachmentFilename(headers: headers) else {
            return ParsedEntity(attachments: [], skippedCount: 0, hasHeaderBodySeparator: true)
        }

        guard isSupportedAttachment(filename) else {
            return ParsedEntity(attachments: [], skippedCount: 1, hasHeaderBodySeparator: true)
        }

        guard let attachmentData = decodedBody(split.body, encoding: headers["content-transfer-encoding"]) else {
            return ParsedEntity(attachments: [], skippedCount: 1, hasHeaderBodySeparator: true)
        }

        return ParsedEntity(
            attachments: [
                EmailReceiptAttachmentCandidate(
                    filename: safeFilename(filename),
                    data: attachmentData,
                    metadata: metadata
                )
            ],
            skippedCount: 0,
            hasHeaderBodySeparator: true
        )
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
