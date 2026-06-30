import AppKit
import SwiftData
import SwiftUI

@main
enum RemnantMain {
    @MainActor private static var delegate: RemnantAppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--import-receipts-manifest") {
            do {
                try ReceiptBackfillImportService.runFromCommandLine(arguments: CommandLine.arguments)
                exit(0)
            } catch {
                fputs("Receipt import failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let appDelegate = RemnantAppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.setRemnantApplicationIcon()
        appDelegate.showMainWindow()

        if CommandLine.arguments.contains("--verify-window") {
            let visibleWindowCount = app.windows.filter(\.isVisible).count
            if visibleWindowCount < 1 {
                fputs("Remnant did not create a visible main window.\n", stderr)
                exit(1)
            }
            if app.applicationIconImage == nil {
                fputs("Remnant did not load the bundled app icon.\n", stderr)
                exit(1)
            }
            fputs("Remnant window verified: \(visibleWindowCount)\n", stdout)
            fputs("Remnant app icon verified.\n", stdout)
            exit(0)
        }

        app.run()
    }
}

private extension NSApplication {
    func setRemnantApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }

        applicationIconImage = image
    }
}

@MainActor
final class RemnantAppDelegate: NSObject, NSApplicationDelegate {
    private let container: ModelContainer
    private var mainWindow: NSWindow?

    override init() {
        do {
            container = try RemnantStore.makeContainer()
        } catch {
            fatalError("Failed to create local expense store: \(error)")
        }

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func showMainWindow() {
        let window: NSWindow
        if let existingWindow = mainWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Remnant"
            window.minSize = NSSize(width: 920, height: 620)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("main")
            window.contentView = NSHostingView(
                rootView: ContentView()
                    .modelContainer(container)
                    .frame(minWidth: 920, minHeight: 620)
            )
            window.center()
            mainWindow = window
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum RemnantStore {
    static let configurationName = "RemnantExpenseTrackerV1"
    static let storeFilename = "RemnantExpenseTrackerV1.store"
    static let legacyDefaultStoreFilename = "default.store"
    static let pendingRestoreDirectoryName = "PendingRestore"

    static var schema: Schema {
        Schema([
            Expense.self,
            ReceiptAttachment.self,
            ExpenseCategory.self,
            BusinessDimension.self,
            CSVImportProfile.self,
            ImportBatch.self,
            VendorRule.self
        ])
    }

    @MainActor
    static func makeContainer(storeURL: URL? = nil) throws -> ModelContainer {
        if storeURL == nil {
            try applyPendingRestoreIfNeeded()
        }
        let schema = schema
        let url = try storeURL ?? resolvedStoreURL()
        let configuration = ModelConfiguration(configurationName, schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
    @MainActor
    static func migrateLegacyStoreIfNeeded(from legacyStoreURL: URL, to targetStoreURL: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: targetStoreURL.path),
              fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return false
        }

        try fileManager.createDirectory(
            at: targetStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try copyStoreFiles(from: legacyStoreURL, to: targetStoreURL)

        do {
            _ = try makeContainer(storeURL: targetStoreURL)
            return true
        } catch {
            removeStoreFiles(at: targetStoreURL)
            return false
        }
    }

    static func defaultStoreURL() throws -> URL {
        let directory = try remnantApplicationSupportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(storeFilename)
    }

    static func legacyDefaultStoreURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(legacyDefaultStoreFilename)
    }

    static func pendingRestoreDirectory() throws -> URL {
        try remnantApplicationSupportDirectory()
            .appendingPathComponent(pendingRestoreDirectoryName, isDirectory: true)
    }

    @discardableResult
    @MainActor
    static func applyPendingRestoreIfNeeded() throws -> Bool {
        let fileManager = FileManager.default
        let pendingRestoreDirectory = try pendingRestoreDirectory()
        guard fileManager.fileExists(atPath: pendingRestoreDirectory.path) else {
            return false
        }

        let pendingReport = try RemnantBackupService.validateBackup(at: pendingRestoreDirectory)
        guard !pendingReport.hasIssues else {
            try fileManager.removeItem(at: pendingRestoreDirectory)
            return false
        }

        let pendingStoreURL = pendingRestoreDirectory
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent(storeFilename)
        guard fileManager.fileExists(atPath: pendingStoreURL.path) else {
            try fileManager.removeItem(at: pendingRestoreDirectory)
            return false
        }

        let targetStoreURL = try defaultStoreURL()
        let targetVaultDirectory = try ReceiptVault.defaultVaultDirectory()
        let safetyDirectory = try restoreSafetyDirectory()
        try fileManager.createDirectory(at: safetyDirectory, withIntermediateDirectories: true)

        let currentStoreFiles = storeFileURLs(for: targetStoreURL).filter { fileManager.fileExists(atPath: $0.path) }
        if !currentStoreFiles.isEmpty {
            let safetyStoreDirectory = safetyDirectory.appendingPathComponent("Store", isDirectory: true)
            try fileManager.createDirectory(at: safetyStoreDirectory, withIntermediateDirectories: true)
            try copyStoreFiles(
                from: targetStoreURL,
                to: safetyStoreDirectory.appendingPathComponent(storeFilename)
            )
        }

        if fileManager.fileExists(atPath: targetVaultDirectory.path) {
            try fileManager.moveItem(
                at: targetVaultDirectory,
                to: safetyDirectory.appendingPathComponent("Receipts", isDirectory: true)
            )
        }

        removeStoreFiles(at: targetStoreURL)
        try copyStoreFiles(from: pendingStoreURL, to: targetStoreURL)

        let pendingReceiptsDirectory = pendingRestoreDirectory.appendingPathComponent("Receipts", isDirectory: true)
        if fileManager.fileExists(atPath: pendingReceiptsDirectory.path) {
            try fileManager.createDirectory(
                at: targetVaultDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: pendingReceiptsDirectory, to: targetVaultDirectory)
        }

        try fileManager.removeItem(at: pendingRestoreDirectory)
        return true
    }

    @MainActor
    private static func resolvedStoreURL() throws -> URL {
        let storeURL = try defaultStoreURL()
        if FileManager.default.fileExists(atPath: storeURL.path) {
            return storeURL
        }

        let legacyStoreURL = try legacyDefaultStoreURL()
        _ = try migrateLegacyStoreIfNeeded(from: legacyStoreURL, to: storeURL)
        return storeURL
    }

    private static func remnantApplicationSupportDirectory() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent("com.borrowedfire.remnant", isDirectory: true)
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return applicationSupport
    }

    static func copyStoreFiles(from sourceURL: URL, to destinationURL: URL) throws {
        for (source, destination) in storeFilePairs(from: sourceURL, to: destinationURL) {
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
    }

    static func removeStoreFiles(at storeURL: URL) {
        for url in storeFileURLs(for: storeURL) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func storeFilePairs(from sourceURL: URL, to destinationURL: URL) -> [(URL, URL)] {
        zip(storeFileURLs(for: sourceURL), storeFileURLs(for: destinationURL)).map { pair in
            (pair.0, pair.1)
        }
    }

    static func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }

    private static func restoreSafetyDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(8)
        return try remnantApplicationSupportDirectory()
            .appendingPathComponent("RestoreSafetyBackups", isDirectory: true)
            .appendingPathComponent("\(formatter.string(from: Date()))-\(suffix)", isDirectory: true)
    }
}
