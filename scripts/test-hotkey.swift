import AppKit
import Carbon

/// Process-level Carbon integration: no keyboard injection and no Accessibility grant.
@main
struct HotkeyChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var calls = 0
        let monitor = HotkeyMonitor()
        monitor.start { calls += 1 }
        guard monitor.statusMessage == nil else { fatalError("Test shortcut is occupied; cannot verify registration") }
        func send(_ kind: Int, signature: OSType = 0x4C544D48, id: UInt32 = 1) {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), 0, 0, &event) == noErr)
            guard let event else { fatalError("Missing event") }
            defer { ReleaseEvent(event) }
            var key = EventHotKeyID(signature: signature, id: id)
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           MemoryLayout<EventHotKeyID>.size, &key) == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        }
        send(kEventHotKeyPressed, id: 2)
        send(kEventHotKeyPressed, signature: 0)
        precondition(calls == 0, "Unrelated hotkeys must not invoke Quick")
        send(kEventHotKeyPressed)
        send(kEventHotKeyPressed)
        precondition(calls == 1, "Held shortcut must fire only once")
        send(kEventHotKeyReleased)
        send(kEventHotKeyPressed)
        precondition(calls == 2)
        monitor.stop()
        send(kEventHotKeyPressed)
        precondition(calls == 2, "Stopped registration must not invoke Quick")
        monitor.start { calls += 10 }
        precondition(monitor.statusMessage == nil, "Stop must free the registration")
        send(kEventHotKeyPressed)
        precondition(calls == 12, "Restart must replace the action and clear held state")
        let conflicting = HotkeyMonitor()
        conflicting.start { calls += 100 }
        precondition(conflicting.statusMessage != nil, "Occupied shortcut needs a visible fallback notice")
        conflicting.stop()
        monitor.stop()
        // Deinit must also free the registration even if the view did not call Stop.
        var transient: HotkeyMonitor? = HotkeyMonitor()
        transient?.start {}
        precondition(transient?.statusMessage == nil)
        transient = nil
        monitor.start {}
        precondition(monitor.statusMessage == nil, "Deinit must free the registration")
        monitor.stop()
        print("PASS: Carbon identity filtering, repeat suppression, release, stop/restart, conflict and deinit")
    }
}
