import AppKit
import SwiftUI
import XCTest
import ListenToMeCore

@MainActor
final class MacWorkspaceUsabilityTests: XCTestCase {
    func testOptionalSettingsStartCollapsedAndNativeDisclosureRevealsThem() {
        _ = NSApplication.shared
        var appeared = false
        var options = ConversationLanguageOptions(translationTarget: "fr")
        let original = options
        let translation = LiveTranslationCoordinator()
        var saves = 0
        let content = MacWorkspaceSection(title: "Recording settings") {
            ConversationLanguageControls(options: Binding(get: { options }, set: { options = $0 }),
                translation: translation, conversationID: "native-disclosure", save: { saves += 1 })
        }.padding(12).onAppear { appeared = true }
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 260, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        var finished = false
        func finish() {
            finished = true; NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(event, atStart: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(appeared)
            let collapsed = host.fittingSize.height
            XCTAssertLessThan(collapsed, 80, "Optional settings must start collapsed")
            self.attach(host, name: "Collapsed native settings")
            // Native pointer events hit the production disclosure, not its binding or callback.
            let local = NSPoint(x: 18, y: host.isFlipped ? 22 : host.bounds.height - 22)
            let point = host.convert(local, to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height, collapsed + 80, "Native disclosure must reveal its actual settings")
                self.attach(host, name: "Expanded native settings")
                XCTAssertEqual(options, original, "Opening actual language controls must preserve saved choices")
                XCTAssertEqual(saves, 0, "Disclosure must not write conversation settings")
                XCTAssertFalse(translation.isTranslating, "Disclosure must not start optional work")
                finish()
            }
        }
        NSApp.run()
        XCTAssertTrue(finished)
    }

    private func attach(_ view: NSView, name: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return XCTFail("No native render") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("No PNG") }
        let shot = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
