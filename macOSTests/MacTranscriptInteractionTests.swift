import AppKit
import SwiftUI
import XCTest
import ListenToMeCore

/// Send real AppKit events through the hosted production row. No app history, microphone,
/// provider, or callback shortcut participates in this interaction contract.
@MainActor
final class MacTranscriptInteractionTests: XCTestCase {
    func testWrappedTextFitsAfterResizeAndSelectionSurvivesSameTextRefresh() {
        let state = TranscriptRefreshState()
        let long = TranscriptSegment(source: .others,
            text: "Please keep the original speaker and timestamp while this sentence wraps. "
                + "会議の資料は共有フォルダーに保存します。次の打ち合わせは月曜日です。"
                + "\nThe second paragraph must also remain visible without clipping.",
            isFinal: true, start: 34, end: 36, language: "en")
        let next = TranscriptSegment(source: .you, text: "The next line stays separate.",
                                     isFinal: true, start: 37, end: 39, language: "en")
        host(RefreshingTranscriptRows(state: state, first: long, second: next), width: 420) { window, view, finish in
            guard let text = self.descendants(view).compactMap({ $0 as? NSTextView })
                .first(where: { $0.string == long.text }) else {
                XCTFail("Wrapped transcript missing"); finish(); return
            }
            self.assertCompleteLayout(text, adjacent: next.text, in: view)
            self.attach(view, name: "Narrow wrapped CJK transcript")
            let narrowHeight = text.bounds.height
            let selected = NSRange(location: 12, length: 8)
            text.setSelectedRange(selected)
            state.dark.toggle()
            window.setContentSize(NSSize(width: 800, height: 300))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                view.layoutSubtreeIfNeeded()
                self.assertCompleteLayout(text, adjacent: next.text, in: view)
                XCTAssertLessThan(text.bounds.height, narrowHeight)
                XCTAssertEqual(text.selectedRange(), selected, "Refresh must retain the selected phrase")
                XCTAssertEqual(text.string, long.text)
                self.attach(view, name: "Wide wrapped transcript after same-text refresh")
                finish()
            }
        }
    }

    func testPartialRowCannotOpenEditor() {
        let partial = TranscriptSegment(source: .others, text: "Still speaking", isFinal: false, start: 0, end: 1)
        host(EditableTranscriptRow(segment: partial, speakerLabel: "OTHERS", copyTranscript: {},
            edit: { _ in XCTFail("Partial text saved") }, delete: {}, addTerm: {})) { window, view, finish in
            guard let text = self.descendants(view).first(where: {
                ($0.accessibilityValue() as? String) == partial.text
            }) else { XCTFail("Partial text missing"); finish(); return }
            let point = self.glyphPoint(text, word: "speaking")
            self.click(window, point: point, count: 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                XCTAssertFalse(self.descendants(view).contains { ($0 as? NSTextField)?.isEditable == true })
                XCTAssertFalse(text.accessibilityCustomActions()?.contains { $0.name == "Edit line" } ?? false)
                finish()
            }
        }
    }

    func testNativeSelectionCopiesOnlySelectedPhraseAndAccessibleActionOpensEditor() {
        let segment = TranscriptSegment(source: .others, text: "The budget is $120.", isFinal: true, start: 34, end: 36)
        host(EditableTranscriptRow(segment: segment, speakerLabel: "OTHERS", copyTranscript: {},
            edit: { _ in XCTFail("Opening editor saved text") }, delete: {}, addTerm: {})) { _, view, finish in
            guard let text = self.descendants(view).compactMap({ $0 as? NSTextView }).first else {
                XCTFail("No native selectable transcript control"); finish(); return
            }
            text.setSelectedRange(NSRange(location: 4, length: 6))
            XCTAssertEqual(text.string, segment.text)
            XCTAssertEqual(text.selectedRange(), NSRange(location: 4, length: 6))
            let pasteboard = NSPasteboard(name: .init("ListenToMe-test-" + UUID().uuidString))
            // NSTextView advertises NSStringPboardType on this runtime. Exercise its actual
            // Copy serialization rather than requesting an unadvertised pasteboard type.
            let types = text.writablePasteboardTypes
            XCTAssertTrue(text.writeSelection(to: pasteboard, types: types))
            XCTAssertTrue(types.contains { pasteboard.string(forType: $0) == "budget" })
            pasteboard.releaseGlobally()
            guard let action = text.accessibilityCustomActions()?.first(where: { $0.name == "Edit line" }) else {
                XCTFail("Accessible edit action missing"); finish(); return
            }
            XCTAssertEqual(action.handler?(), true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let editors = self.descendants(view).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
                XCTAssertEqual(editors.map(\.stringValue), [segment.text])
                finish()
            }
        }
    }

    func testDoubleClickFinalRowOpensOnlyThatLineEditor() throws {
        let first = TranscriptSegment(source: .others, text: "The budget is $120.",
                                      isFinal: true, start: 34, end: 36, language: "en")
        let second = TranscriptSegment(source: .you, text: "The next review is Monday.",
                                       isFinal: true, start: 37, end: 39, language: "en")
        var changes: [String] = []
        let rows = VStack {
            EditableTranscriptRow(segment: first, speakerLabel: "OTHERS", copyTranscript: {},
                                  edit: { changes.append($0) }, delete: {}, addTerm: {})
            EditableTranscriptRow(segment: second, speakerLabel: "YOU", copyTranscript: {},
                                  edit: { _ in XCTFail("Adjacent line edited") }, delete: {}, addTerm: {})
        }
        host(rows) { window, view, finish in
            guard let text = self.descendants(view).first(where: {
                ($0.accessibilityValue() as? String) == first.text
            }) else {
                XCTFail("Rendered selectable transcript text is missing"); finish(); return
            }
            let point = self.glyphPoint(text, word: "is")
            self.click(window, point: point, count: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.click(window, point: point, count: 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let editors = self.descendants(view).compactMap { $0 as? NSTextField }
                        .filter { $0.isEditable }
                    XCTAssertEqual(editors.map(\.stringValue), [first.text],
                                   "Double-click must open the selected row's actual editor")
                    XCTAssertTrue(self.descendants(view).contains {
                        ($0.accessibilityValue() as? String) == second.text
                    }, "Adjacent transcript must remain visible and unchanged")
                    XCTAssertTrue(changes.isEmpty, "Opening an editor must not save a change")
                    finish()
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func assertCompleteLayout(_ text: NSTextView, adjacent: String, in view: NSView) {
        guard let layout = text.layoutManager, let container = text.textContainer,
              let next = descendants(view).compactMap({ $0 as? NSTextView })
                .first(where: { $0.string == adjacent }) else {
            XCTFail("Native layout or adjacent transcript missing"); return
        }
        layout.ensureLayout(for: container)
        XCTAssertEqual(layout.glyphRange(for: container).length, layout.numberOfGlyphs)
        XCTAssertLessThanOrEqual(layout.usedRect(for: container).maxY + text.textContainerOrigin.y,
                                 text.bounds.height + 0.5, "Rendered row must contain every line")
        XCTAssertFalse(text.convert(text.bounds, to: view).intersects(next.convert(next.bounds, to: view)),
                       "Wrapped text must not cover the next transcript row")
    }

    private func attach(_ view: NSView, name: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("Native transcript screenshot unavailable"); return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Native screenshot encoding failed"); return
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func glyphPoint(_ view: NSView, word: String) -> NSPoint {
        let string = (view.accessibilityValue() as? String) ?? ""
        let range = (string as NSString).range(of: word)
        XCTAssertNotEqual(range.location, NSNotFound)
        if let text = view as? NSTextView, let layout = text.layoutManager, let container = text.textContainer {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let point = NSPoint(x: rect.midX, y: rect.midY)
            let character = layout.characterIndex(for: point, in: container,
                                                 fractionOfDistanceBetweenInsertionPoints: nil)
            XCTAssertTrue(NSLocationInRange(character, range), "Pointer must hit the intended word")
            return text.convert(NSPoint(x: point.x + text.textContainerOrigin.x,
                                        y: point.y + text.textContainerOrigin.y), to: nil)
        }
        // The legacy selectable Text has a tight native glyph frame. Its center remains an
        // actual text hit in the pre-fix replay; the replacement's full-width blank area does not.
        return view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }

    private func click(_ window: NSWindow, point: NSPoint, count: Int) {
        let time = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: time, windowNumber: window.windowNumber, context: nil,
            eventNumber: count * 2, clickCount: count, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: time + 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: count * 2 + 1, clickCount: count, pressure: 0) else {
            XCTFail("Could not construct native pointer events"); return
        }
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }

    private func host<Content: View>(
        _ content: Content, width: CGFloat = 800,
        exercise: @escaping @MainActor (NSWindow, NSView, @escaping @MainActor () -> Void) -> Void
    ) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let view = NSHostingView(rootView: ScrollView { content.padding(14) }
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ListenToMe native transcript contract — synthetic"
        window.contentView = view
        var finished = false
        let finish: @MainActor () -> Void = {
            guard !finished else { return }
            finished = true
            window.close()
            NSApp.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !finished else { return }
            view.layoutSubtreeIfNeeded()
            exercise(window, view, finish)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !finished else { return }
            XCTFail("Native transcript interaction did not finish")
            finish()
        }
        NSApp.run()
    }
}

@MainActor private final class TranscriptRefreshState: ObservableObject {
    @Published var dark = false
}

private struct RefreshingTranscriptRows: View {
    @ObservedObject var state: TranscriptRefreshState
    let first: TranscriptSegment
    let second: TranscriptSegment
    var body: some View {
        VStack {
            ForEach([first, second]) { segment in
                EditableTranscriptRow(segment: segment, speakerLabel: segment.speakerLabel,
                                      copyTranscript: {}, edit: { _ in }, delete: {}, addTerm: {})
            }
        }
        .background(state.dark ? Color.black : Color.white)
        .environment(\.colorScheme, state.dark ? .dark : .light)
    }
}
