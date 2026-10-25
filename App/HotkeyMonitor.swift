import AppKit
import Carbon
import Observation

/// Registers only ⌘⇧Space with the OS. No global key monitor or Accessibility permission is used.
@MainActor @Observable
final class HotkeyMonitor {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var action: (() -> Void)?
    private var pressed = false
    private(set) var statusMessage: String?
    private static let signature: OSType = 0x4C544D48 // LTMH

    isolated deinit { stop() }

    func start(_ action: @escaping () -> Void) {
        stop()
        self.action = action
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue().receive(event)
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let registered = installed == noErr
            ? RegisterEventHotKey(49, UInt32(cmdKey | shiftKey),
                                  EventHotKeyID(signature: Self.signature, id: 1),
                                  GetApplicationEventTarget(), 0, &hotKey)
            : installed
        guard registered != noErr else { return }
        // An occupied shortcut should not disable the in-app shortcut or request more permissions.
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        statusMessage = "Global ⌘⇧Space is unavailable (another app may use it). Quick still works here."
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                if event.keyCode == 49, !event.isARepeat,
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] {
                    self?.action?()
                    return true
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        hotKey = nil; handler = nil; localMonitor = nil
        action = nil; pressed = false; statusMessage = nil
    }

    private func receive(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
              identifier.signature == Self.signature, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard !pressed else { return noErr }
            pressed = true
            action?()
        case UInt32(kEventHotKeyReleased): pressed = false
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
