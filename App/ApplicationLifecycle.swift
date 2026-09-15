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
    /// True while capture is running, so the menu item can read "Stop listening".
    let isCapturing: Bool
    /// False while a lifecycle operation (finalizing, importing) owns the session.
    let canToggleCapture: Bool
    /// False when AI is turned off, so the three copilot items are visibly unavailable.
    let canUseAI: Bool
    let save: () -> Void
    let new: () -> Void
    let history: () -> Void
    let export: () -> Void
    let settings: () -> Void
    let toggleCapture: () -> Void
    let deepAnswer: () -> Void
    let recap: () -> Void
    let refreshSummary: () -> Void
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
    /// nil whenever no MeetingView window is key — including after the user closes the window while
    /// the app stays in the Dock. Every item must be `.disabled` on nil, or its shortcut is a silent
    /// no-op (issue #136).
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
                .disabled(actions == nil)
            Button("Conversation history…") { actions?.history() }.keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.settings() }.keyboardShortcut(",")
                .disabled(actions == nil)
        }
        // The app's most frequent actions had no keyboard equivalents at all (issue #136). ⌘⇧Space
        // (Quick answer) stays with HotkeyMonitor because it must work while another app is front.
        CommandMenu("Session") {
            Button(actions?.isCapturing == true ? "Stop listening" : "Start listening") {
                actions?.toggleCapture()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(actions?.canToggleCapture != true)
            Divider()
            Button("Deep answer") { actions?.deepAnswer() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(actions?.canUseAI != true)
            Button("Recap so far") { actions?.recap() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(actions?.canUseAI != true)
            Button("Refresh summary") { actions?.refreshSummary() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(actions?.canUseAI != true)
        }
    }
}
