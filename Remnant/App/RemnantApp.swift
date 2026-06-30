import AppKit
import SwiftData
import SwiftUI

@MainActor
@main
struct RemnantApp: App {
    @NSApplicationDelegateAdaptor(RemnantAppDelegate.self) private var appDelegate
    @StateObject private var appState = RemnantAppState()

    private let container: ModelContainer

    init() {
        RemnantLaunchPreflight.runCommandLineModesIfNeeded()

        do {
            container = try RemnantStore.makeContainer()
        } catch {
            fatalError("Failed to create local expense store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Remnant") {
            ContentView(appState: appState)
                .modelContainer(container)
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            RemnantCommands(appState: appState)
        }

        Settings {
            ExpenseSettingsView()
                .modelContainer(container)
                .frame(width: 720, height: 640)
        }
    }
}

enum RemnantLaunchPreflight {
    @MainActor
    static func runCommandLineModesIfNeeded() {
        guard CommandLine.arguments.contains("--import-receipts-manifest") else {
            return
        }

        do {
            try ReceiptBackfillImportService.runFromCommandLine(arguments: CommandLine.arguments)
            exit(0)
        } catch {
            fputs("Receipt import failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.setRemnantApplicationIcon()

        if CommandLine.arguments.contains("--verify-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                RemnantWindowVerifier.verifyAndExit(deadline: Date().addingTimeInterval(5))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

enum RemnantWindowVerifier {
    @MainActor
    static func verifyAndExit(deadline: Date) {
        let app = NSApplication.shared
        let visibleWindowCount = app.windows.filter(\.isVisible).count
        let requiredCommands: [(String, String)] = [
            ("New Expense", "n"),
            ("Find", "f"),
            ("Open Receipt", "o"),
            ("Import Files", "i"),
            ("Export Current Report", "e")
        ]

        let missingCommands = requiredCommands.filter { command in
            !mainMenuContainsItem(title: command.0, keyEquivalent: command.1)
        }

        if visibleWindowCount < 1 || app.applicationIconImage == nil || !missingCommands.isEmpty {
            guard Date() < deadline else {
                if visibleWindowCount < 1 {
                    fputs("Remnant did not create a visible main window.\n", stderr)
                }
                if app.applicationIconImage == nil {
                    fputs("Remnant did not load the bundled app icon.\n", stderr)
                }
                for command in missingCommands {
                    fputs("Remnant menu command missing: \(command.0) (\(command.1)).\n", stderr)
                }
                exit(1)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                verifyAndExit(deadline: deadline)
            }
            return
        }

        fputs("Remnant window verified: \(visibleWindowCount)\n", stdout)
        fputs("Remnant app icon verified.\n", stdout)
        fputs("Remnant native commands verified.\n", stdout)
        exit(0)
    }

    @MainActor
    private static func mainMenuContainsItem(title: String, keyEquivalent: String) -> Bool {
        guard let mainMenu = NSApplication.shared.mainMenu else { return false }
        return menu(mainMenu, containsItemWithTitle: title, keyEquivalent: keyEquivalent)
    }

    @MainActor
    private static func menu(_ menu: NSMenu, containsItemWithTitle title: String, keyEquivalent: String) -> Bool {
        for item in menu.items {
            if item.title == title && item.keyEquivalent == keyEquivalent {
                return true
            }
            if let submenu = item.submenu,
               self.menu(submenu, containsItemWithTitle: title, keyEquivalent: keyEquivalent) {
                return true
            }
        }
        return false
    }
}
