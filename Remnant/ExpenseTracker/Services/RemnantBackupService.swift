import CryptoKit
import Foundation
import SwiftData

enum RemnantBackupIssueKind: String, Codable, Equatable {
    case brokenAttachmentExpenseLink
    case brokenExpenseAttachmentLink
    case corruptBackupFile
    case corruptReceiptFile
    case missingBackupFile
    case missingBackupManifest
    case missingBackupStore
    case missingReceiptFile
    case staleReceiptPath
}

struct RemnantBackupIntegrityIssue: Identifiable, Codable, Equatable {
    let kind: RemnantBackupIssueKind
    let detail: String

    var id: String { "\(kind.rawValue):\(detail)" }
}

struct RemnantBackupIntegrityReport: Equatable {
    let expenseCount: Int
    let attachmentCount: Int
    let receiptFileCount: Int
    let checkedFileCount: Int
    let issues: [RemnantBackupIntegrityIssue]

    var hasIssues: Bool {
        !issues.isEmpty
    }
}

struct RemnantBackupFileRecord: Codable, Equatable {
    let path: String
    let sha256: String
}

struct RemnantBackupManifest: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let storeFiles: [RemnantBackupFileRecord]
    let receiptFiles: [RemnantBackupFileRecord]
}

struct RemnantAutomaticBackupResult: Equatable {
    let backupURL: URL
    let report: RemnantBackupIntegrityReport
}

enum RemnantBackupError: LocalizedError {
    case destinationExists(URL)
    case invalidBackup(RemnantBackupIntegrityReport)
    case missingStore(URL)
    case restoreRequiresConfirmation
    case unreadableBackup(URL)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let url):
            "A backup already exists at \(url.lastPathComponent)."
        case .invalidBackup(let report):
            "Backup integrity check failed with \(report.issues.count) issue(s)."
        case .missingStore(let url):
            "Remnant could not find the local store at \(url.lastPathComponent)."
        case .restoreRequiresConfirmation:
            "Restore requires explicit confirmation before current local data is replaced."
        case .unreadableBackup(let url):
            "Remnant could not read \(url.lastPathComponent)."
        }
    }
}

@MainActor
enum RemnantBackupService {
    static let backupExtension = "remnantbackup"
    static let automaticBackupEnabledKey = "remnant.automaticBackup.enabled"
    static let automaticBackupLastRunKey = "remnant.automaticBackup.lastRun"
    static let automaticBackupMinimumInterval: TimeInterval = 86_400

    private static let manifestFilename = "manifest.json"
    private static let storeDirectoryName = "Store"
    private static let receiptDirectoryName = "Receipts"
    private static let automaticBackupDirectoryName = "AutomaticBackups"

    @discardableResult
    static func createBackup(
        at destinationURL: URL,
        context: ModelContext,
        storeURL: URL? = nil,
        vaultDirectory: URL? = nil,
        allowOverwrite: Bool = false
    ) throws -> RemnantBackupIntegrityReport {
        let fileManager = FileManager.default
        let resolvedStoreURL = try storeURL ?? RemnantStore.defaultStoreURL()
        let resolvedVaultDirectory = try vaultDirectory ?? ReceiptVault.defaultVaultDirectory()

        try context.save()

        guard RemnantStore.storeFileURLs(for: resolvedStoreURL).contains(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw RemnantBackupError.missingStore(resolvedStoreURL)
        }

        let liveReport = try integrityReport(context: context, vaultDirectory: resolvedVaultDirectory)

        if fileManager.fileExists(atPath: destinationURL.path) {
            guard allowOverwrite else {
                throw RemnantBackupError.destinationExists(destinationURL)
            }
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let storeBackupDirectory = destinationURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
        let receiptBackupDirectory = destinationURL.appendingPathComponent(receiptDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: storeBackupDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: receiptBackupDirectory, withIntermediateDirectories: true)

        for storeFileURL in RemnantStore.storeFileURLs(for: resolvedStoreURL) where fileManager.fileExists(atPath: storeFileURL.path) {
            try fileManager.copyItem(
                at: storeFileURL,
                to: storeBackupDirectory.appendingPathComponent(storeFileURL.lastPathComponent)
            )
        }

        if fileManager.fileExists(atPath: resolvedVaultDirectory.path) {
            try copyDirectoryContents(from: resolvedVaultDirectory, to: receiptBackupDirectory)
        }

        let manifest = RemnantBackupManifest(
            version: RemnantBackupManifest.currentVersion,
            createdAt: Date(),
            storeFiles: try fileRecords(in: destinationURL, under: storeDirectoryName),
            receiptFiles: try fileRecords(in: destinationURL, under: receiptDirectoryName)
        )
        try writeManifest(manifest, to: destinationURL)

        return liveReport
    }

    @discardableResult
    static func runAutomaticBackupIfNeeded(
        context: ModelContext,
        storeURL: URL? = nil,
        vaultDirectory: URL? = nil,
        backupRootDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        minimumInterval: TimeInterval = automaticBackupMinimumInterval
    ) throws -> RemnantAutomaticBackupResult? {
        guard defaults.bool(forKey: automaticBackupEnabledKey) else {
            return nil
        }

        let lastRun = defaults.double(forKey: automaticBackupLastRunKey)
        guard lastRun <= 0 || now.timeIntervalSince1970 - lastRun >= minimumInterval else {
            return nil
        }

        return try createAutomaticBackup(
            context: context,
            storeURL: storeURL,
            vaultDirectory: vaultDirectory,
            backupRootDirectory: backupRootDirectory,
            defaults: defaults,
            now: now
        )
    }

    @discardableResult
    static func createAutomaticBackup(
        context: ModelContext,
        storeURL: URL? = nil,
        vaultDirectory: URL? = nil,
        backupRootDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> RemnantAutomaticBackupResult {
        let backupDirectory = try automaticBackupDirectory(rootDirectory: backupRootDirectory)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let backupURL = backupDirectory.appendingPathComponent(
            "remnant-auto-\(automaticBackupDateFormatter.string(from: now))-\(UUID().uuidString.prefix(6)).\(backupExtension)",
            isDirectory: true
        )
        let report = try createBackup(
            at: backupURL,
            context: context,
            storeURL: storeURL,
            vaultDirectory: vaultDirectory,
            allowOverwrite: false
        )
        defaults.set(now.timeIntervalSince1970, forKey: automaticBackupLastRunKey)
        return RemnantAutomaticBackupResult(backupURL: backupURL, report: report)
    }

    static func automaticBackupDirectory(rootDirectory: URL? = nil) throws -> URL {
        let baseDirectory: URL
        if let rootDirectory {
            baseDirectory = rootDirectory
        } else {
            baseDirectory = try RemnantStore.defaultStoreURL().deletingLastPathComponent()
        }
        return baseDirectory.appendingPathComponent(automaticBackupDirectoryName, isDirectory: true)
    }

    static func stageRestore(
        from backupURL: URL,
        allowOverwrite: Bool
    ) throws -> RemnantBackupIntegrityReport {
        guard allowOverwrite else {
            throw RemnantBackupError.restoreRequiresConfirmation
        }

        let report = try validateBackup(at: backupURL)
        guard !report.hasIssues else {
            throw RemnantBackupError.invalidBackup(report)
        }

        let fileManager = FileManager.default
        let pendingRestoreDirectory = try RemnantStore.pendingRestoreDirectory()
        if fileManager.fileExists(atPath: pendingRestoreDirectory.path) {
            try fileManager.removeItem(at: pendingRestoreDirectory)
        }

        try fileManager.createDirectory(at: pendingRestoreDirectory, withIntermediateDirectories: true)
        try copyItemIfPresent(
            from: backupURL.appendingPathComponent(storeDirectoryName, isDirectory: true),
            to: pendingRestoreDirectory.appendingPathComponent(storeDirectoryName, isDirectory: true)
        )
        try copyItemIfPresent(
            from: backupURL.appendingPathComponent(receiptDirectoryName, isDirectory: true),
            to: pendingRestoreDirectory.appendingPathComponent(receiptDirectoryName, isDirectory: true)
        )
        try copyItemIfPresent(
            from: backupURL.appendingPathComponent(manifestFilename),
            to: pendingRestoreDirectory.appendingPathComponent(manifestFilename)
        )

        return report
    }

    static func validateBackup(at backupURL: URL) throws -> RemnantBackupIntegrityReport {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw RemnantBackupError.unreadableBackup(backupURL)
        }

        let manifestURL = backupURL.appendingPathComponent(manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return RemnantBackupIntegrityReport(
                expenseCount: 0,
                attachmentCount: 0,
                receiptFileCount: 0,
                checkedFileCount: 0,
                issues: [
                    RemnantBackupIntegrityIssue(
                        kind: .missingBackupManifest,
                        detail: manifestFilename
                    )
                ]
            )
        }

        let manifest = try readManifest(from: backupURL)
        var issues: [RemnantBackupIntegrityIssue] = []
        let records = manifest.storeFiles + manifest.receiptFiles

        if manifest.storeFiles.isEmpty {
            issues.append(
                RemnantBackupIntegrityIssue(
                    kind: .missingBackupStore,
                    detail: RemnantStore.storeFilename
                )
            )
        }

        for record in records {
            let fileURL = backupURL.appendingPathComponent(record.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                issues.append(RemnantBackupIntegrityIssue(kind: .missingBackupFile, detail: record.path))
                continue
            }

            let currentHash = try sha256(for: fileURL)
            if currentHash != record.sha256 {
                issues.append(RemnantBackupIntegrityIssue(kind: .corruptBackupFile, detail: record.path))
            }
        }

        return RemnantBackupIntegrityReport(
            expenseCount: 0,
            attachmentCount: 0,
            receiptFileCount: manifest.receiptFiles.count,
            checkedFileCount: records.count,
            issues: issues
        )
    }

    static func integrityReport(
        context: ModelContext,
        vaultDirectory: URL? = nil
    ) throws -> RemnantBackupIntegrityReport {
        let resolvedVaultDirectory = try vaultDirectory ?? ReceiptVault.defaultVaultDirectory()
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        let expensesByID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
        let attachmentsByID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
        let attachmentsByHash = Dictionary(grouping: attachments) { normalizedHash($0.contentHash) }
        var issues: [RemnantBackupIntegrityIssue] = []
        var checkedFileCount = 0

        for expense in expenses {
            if let receiptAttachmentID = expense.receiptAttachmentID,
               attachmentsByID[receiptAttachmentID] == nil {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .brokenExpenseAttachmentLink,
                        detail: "\(expense.merchant) references missing attachment \(receiptAttachmentID.uuidString)."
                    )
                )
            }

            if let receiptContentHash = expense.receiptContentHash,
               !normalizedHash(receiptContentHash).isEmpty,
               attachmentsByHash[normalizedHash(receiptContentHash), default: []].isEmpty {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .brokenExpenseAttachmentLink,
                        detail: "\(expense.merchant) references missing receipt hash \(receiptContentHash)."
                    )
                )
            }
        }

        for attachment in attachments {
            if let expenseID = attachment.expenseID,
               expensesByID[expenseID] == nil {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .brokenAttachmentExpenseLink,
                        detail: "\(attachment.originalFilename) references missing expense \(expenseID.uuidString)."
                    )
                )
            }

            let resolution = receiptFileResolution(for: attachment, vaultDirectory: resolvedVaultDirectory)
            guard let fileURL = resolution.fileURL else {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .missingReceiptFile,
                        detail: attachment.originalFilename
                    )
                )
                continue
            }

            if resolution.isStalePath {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .staleReceiptPath,
                        detail: attachment.originalFilename
                    )
                )
            }

            checkedFileCount += 1
            let currentHash = try sha256(for: fileURL)
            if !normalizedHash(attachment.contentHash).isEmpty,
               currentHash != normalizedHash(attachment.contentHash) {
                issues.append(
                    RemnantBackupIntegrityIssue(
                        kind: .corruptReceiptFile,
                        detail: attachment.originalFilename
                    )
                )
            }
        }

        return RemnantBackupIntegrityReport(
            expenseCount: expenses.count,
            attachmentCount: attachments.count,
            receiptFileCount: checkedFileCount,
            checkedFileCount: checkedFileCount,
            issues: issues
        )
    }

    @discardableResult
    static func repairReceiptPaths(
        context: ModelContext,
        vaultDirectory: URL? = nil
    ) throws -> Int {
        let resolvedVaultDirectory = try vaultDirectory ?? ReceiptVault.defaultVaultDirectory()
        let attachments = try context.fetch(FetchDescriptor<ReceiptAttachment>())
        var repairedCount = 0

        for attachment in attachments {
            let resolution = receiptFileResolution(for: attachment, vaultDirectory: resolvedVaultDirectory)
            if resolution.isStalePath, let fileURL = resolution.fileURL {
                attachment.localPath = fileURL.path
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            try context.save()
        }
        return repairedCount
    }

    private static func receiptFileResolution(
        for attachment: ReceiptAttachment,
        vaultDirectory: URL
    ) -> (fileURL: URL?, isStalePath: Bool) {
        let fileManager = FileManager.default
        if !attachment.localPath.isEmpty {
            let storedURL = URL(fileURLWithPath: attachment.localPath)
            if fileManager.fileExists(atPath: storedURL.path) {
                return (storedURL, false)
            }

            let fallbackURL = vaultDirectory.appendingPathComponent(storedURL.lastPathComponent)
            if fileManager.fileExists(atPath: fallbackURL.path) {
                return (fallbackURL, true)
            }
        }

        if !attachment.contentHash.isEmpty {
            let matches = (try? fileManager.contentsOfDirectory(
                at: vaultDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            if let hashMatch = matches.first(where: { $0.lastPathComponent.hasPrefix(attachment.contentHash) }) {
                return (hashMatch, true)
            }
        }

        return (nil, false)
    }

    private static func readManifest(from backupURL: URL) throws -> RemnantBackupManifest {
        let manifestURL = backupURL.appendingPathComponent(manifestFilename)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemnantBackupManifest.self, from: data)
    }

    private static func writeManifest(_ manifest: RemnantBackupManifest, to backupURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: backupURL.appendingPathComponent(manifestFilename), options: .atomic)
    }

    private static func fileRecords(in backupURL: URL, under directoryName: String) throws -> [RemnantBackupFileRecord] {
        let directoryURL = backupURL.appendingPathComponent(directoryName, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [RemnantBackupFileRecord] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = relativePath(for: fileURL, from: backupURL)
            records.append(RemnantBackupFileRecord(path: relativePath, sha256: try sha256(for: fileURL)))
        }
        return records.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func copyDirectoryContents(from sourceDirectory: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
        for sourceURL in contents {
            try copyItemIfPresent(
                from: sourceURL,
                to: destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            )
        }
    }

    private static func copyItemIfPresent(from sourceURL: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func relativePath(for fileURL: URL, from baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(basePath.count + 1))
    }

    private static func sha256(for fileURL: URL) throws -> String {
        try sha256(for: Data(contentsOf: fileURL))
    }

    private static func sha256(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizedHash(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static var automaticBackupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }
}
