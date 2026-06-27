import AppKit
import SwiftData
import SwiftUI

@main
enum RemnantMain {
    @MainActor private static var delegate: RemnantAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = RemnantAppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        appDelegate.showMainWindow()

        if CommandLine.arguments.contains("--verify-window") {
            let visibleWindowCount = app.windows.filter(\.isVisible).count
            if visibleWindowCount < 1 {
                fputs("Remnant did not create a visible main window.\n", stderr)
                exit(1)
            }
            fputs("Remnant window verified: \(visibleWindowCount)\n", stdout)
            exit(0)
        }

        app.run()
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

    static var schema: Schema {
        Schema([
            Expense.self,
            ReceiptAttachment.self,
            ExpenseCategory.self,
            BusinessDimension.self,
            ImportBatch.self,
            VendorRule.self
        ])
    }

    static func makeContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let schema = schema
        let url = try storeURL ?? resolvedStoreURL()
        let configuration = ModelConfiguration(configurationName, schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
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

    private static func copyStoreFiles(from sourceURL: URL, to destinationURL: URL) throws {
        for (source, destination) in storeFilePairs(from: sourceURL, to: destinationURL) {
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
    }

    private static func removeStoreFiles(at storeURL: URL) {
        for url in storeFileURLs(for: storeURL) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func storeFilePairs(from sourceURL: URL, to destinationURL: URL) -> [(URL, URL)] {
        zip(storeFileURLs(for: sourceURL), storeFileURLs(for: destinationURL)).map { pair in
            (pair.0, pair.1)
        }
    }

    private static func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }
}
