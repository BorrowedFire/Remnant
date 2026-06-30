import AppKit
import SwiftUI

struct RemnantFocusedActions {
    var newExpense: (() -> Void)?
    var editSelection: (() -> Void)?
    var openSelection: (() -> Void)?
    var openReceipt: (() -> Void)?
    var markReviewed: (() -> Void)?
    var ignoreSelection: (() -> Void)?
    var copySelection: (() -> Void)?
    var focusSearch: (() -> Void)?
    var importFiles: (() -> Void)?
    var exportReport: (() -> Void)?

    var canEditSelection: Bool { editSelection != nil }
    var canOpenSelection: Bool { openSelection != nil }
    var canOpenReceipt: Bool { openReceipt != nil }
    var canReviewSelection: Bool { markReviewed != nil }
    var canIgnoreSelection: Bool { ignoreSelection != nil }
    var canCopySelection: Bool { copySelection != nil }
}

private struct RemnantFocusedActionsKey: FocusedValueKey {
    typealias Value = RemnantFocusedActions
}

extension FocusedValues {
    var remnantActions: RemnantFocusedActions? {
        get { self[RemnantFocusedActionsKey.self] }
        set { self[RemnantFocusedActionsKey.self] = newValue }
    }
}

struct RemnantCommands: Commands {
    @ObservedObject var appState: RemnantAppState
    @FocusedValue(\.remnantActions) private var focusedActions

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .newItem) {
            Button("New Expense") {
                (focusedActions?.newExpense ?? appState.showNewExpense)()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                copyTextOrSelection()
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)

            Divider()

            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") {
                (focusedActions?.focusSearch ?? { appState.request(.focusSearch) })()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Navigate") {
            ForEach(ExpenseSection.allCases) { section in
                Button(section.rawValue) {
                    appState.select(section)
                }
                .keyboardShortcut(section.commandKey, modifiers: .command)
            }
        }

        CommandMenu("Ledger") {
            Button("Open Selection") {
                focusedActions?.openSelection?()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canOpenSelection)

            Button("Edit Selection") {
                focusedActions?.editSelection?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!canEditSelection)

            Button("Open Receipt") {
                focusedActions?.openReceipt?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!canOpenReceipt)

            Divider()

            Button("Mark Reviewed") {
                focusedActions?.markReviewed?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canReviewSelection)

            Button("Ignore Selection") {
                focusedActions?.ignoreSelection?()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!canIgnoreSelection)

            Divider()

            Button("Import Files") {
                if let importFiles = focusedActions?.importFiles {
                    importFiles()
                } else if appState.selectedSection == .imports {
                    appState.request(.importFiles)
                } else {
                    appState.select(.imports)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Export Current Report") {
                if let exportReport = focusedActions?.exportReport {
                    exportReport()
                } else if appState.selectedSection == .reports {
                    appState.request(.exportReport)
                } else {
                    appState.select(.reports)
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
        }
    }

    private var canEditSelection: Bool {
        focusedActions?.canEditSelection == true
    }

    private var canOpenSelection: Bool {
        focusedActions?.canOpenSelection == true
    }

    private var canOpenReceipt: Bool {
        focusedActions?.canOpenReceipt == true
    }

    private var canReviewSelection: Bool {
        focusedActions?.canReviewSelection == true
    }

    private var canIgnoreSelection: Bool {
        focusedActions?.canIgnoreSelection == true
    }

    private func copyTextOrSelection() {
        if !NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
            focusedActions?.copySelection?()
        }
    }
}
