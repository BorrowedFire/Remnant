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
