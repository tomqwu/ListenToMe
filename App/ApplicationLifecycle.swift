import AppKit
import SwiftUI

/// Native close/quit defers termination until finalized text is saved or the user chooses discard.
@MainActor
final class ApplicationLifecycle: NSObject, NSApplicationDelegate {
    static let shared = ApplicationLifecycle()
    var prepareToClose: (() async -> Bool)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepareToClose = Self.shared.prepareToClose else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await prepareToClose()) }
        return .terminateLater
    }
}

struct WindowCloseHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CloseAwareView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CloseAwareView: NSView, NSWindowDelegate {
        private weak var previousDelegate: (any NSWindowDelegate)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window?.delegate !== self { previousDelegate = window?.delegate }
            window?.delegate = self
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            previousDelegate?.responds(to: selector) == true ? previousDelegate : super.forwardingTarget(for: selector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let prepare = ApplicationLifecycle.shared.prepareToClose else { return true }
            Task {
                guard await prepare(), previousDelegate?.windowShouldClose?(sender) != false else { return }
                ApplicationLifecycle.shared.prepareToClose = nil
                sender.close()
            }
            return false
        }
    }
}

struct ConversationCommands {
    let canSave: Bool
    let canStartNew: Bool
    let save: () -> Void
    let new: () -> Void
    let history: () -> Void
    let export: () -> Void
    let settings: () -> Void
}

private struct ConversationCommandsKey: FocusedValueKey {
    typealias Value = ConversationCommands
}

extension FocusedValues {
    var conversationCommands: ConversationCommands? {
        get { self[ConversationCommandsKey.self] }
        set { self[ConversationCommandsKey.self] = newValue }
    }
}

struct ConversationMenu: Commands {
    @FocusedValue(\.conversationCommands) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New conversation") { actions?.new() }.keyboardShortcut("n")
                .disabled(actions?.canStartNew != true)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save conversation") { actions?.save() }.keyboardShortcut("s")
                .disabled(actions?.canSave != true)
            Button("Export conversation…") { actions?.export() }.keyboardShortcut("e")
            Button("Conversation history…") { actions?.history() }.keyboardShortcut("f")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.settings() }.keyboardShortcut(",")
        }
    }
}
