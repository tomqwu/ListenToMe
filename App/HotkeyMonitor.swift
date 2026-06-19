import AppKit
import ApplicationServices

/// Listens for ⌘⇧Space both globally (other apps focused) and locally (this app focused).
/// The global path requires Accessibility permission; we prompt for it on first use.
final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(_ action: @escaping () -> Void) {
        // Show the system Accessibility prompt if we're not yet trusted; otherwise the global
        // key monitor silently receives nothing. The key string matches the imported
        // `kAXTrustedCheckOptionPrompt` constant, used as a literal to stay clear of Swift 6
        // concurrency-safety on the imported global.
        let promptKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        // Global: fires when another app is focused.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if Self.isHotkey(event) { action() }
        }
        // Local: fires when this app is focused; return nil to consume the event.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isHotkey(event) {
                action()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// ⌘⇧Space, ignoring auto-repeat. 49 = Space.
    private static func isHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == 49
            && !event.isARepeat
            && event.modifierFlags.contains([.command, .shift])
    }
}
