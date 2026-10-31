import AppKit
import SwiftUI
import XCTest
import ListenToMeCore

/// Send real AppKit events through the hosted production row. No app history, microphone,
/// provider, or callback shortcut participates in this interaction contract.
@MainActor
final class MacTranscriptInteractionTests: XCTestCase {
    func testLongSpeakerNameDoesNotPaintOverAdjacentTranscript() {
        let state = SpeakerNameRenderState()
        let text = "The synthetic cedar meeting starts at noon."
        let fullName = "Dana QA334 Full Name Regression Check"
        let row = SpeakerNameRenderRow(state: state, text: text)
            .frame(width: 572, height: 100, alignment: .topLeading).background(Color.white)
        host(row, width: 600) { window, view, finish in
            do {
                window.appearance = NSAppearance(named: .aqua); view.appearance = window.appearance
                let label = try XCTUnwrap(self.descendants(view).compactMap { $0 as? MacSpeakerNameButton }.first)
                let transcript = try XCTUnwrap(self.descendants(view).compactMap { $0 as? TranscriptTextView }.first)
                let labelFrame = label.convert(label.bounds, to: view)
                let textFrame = transcript.convert(transcript.bounds, to: view)
                XCTAssertEqual(labelFrame.width, 100, accuracy: 0.5)
                XCTAssertLessThan(labelFrame.maxX, textFrame.minX)
                XCTAssertEqual(transcript.string, text)
                let short = try self.speakerRaster(view, name: "Short speaker beside original transcript")
                state.name = fullName
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    defer { finish() }
                    do {
                        view.layoutSubtreeIfNeeded()
                        XCTAssertEqual(label.title, fullName.uppercased(), "The actual native label must update")
                        XCTAssertEqual(label.convert(label.bounds, to: view), labelFrame)
                        XCTAssertEqual(transcript.convert(transcript.bounds, to: view), textFrame)
                        XCTAssertEqual(transcript.string, text)
                        XCTAssertEqual(label.toolTip, fullName.uppercased() + " — Double-click to rename this speaker")
                        XCTAssertEqual(label.accessibilityLabel(), "Rename speaker " + fullName.uppercased())
                        let long = try self.speakerRaster(view, name: "Long speaker beside original transcript")
                        let changes = try self.speakerPixelChanges(short, long, label: labelFrame,
                                                                  transcript: textFrame, in: view)
                        let evidence = XCTAttachment(string: "label=\(labelFrame), transcript=\(textFrame), "
                            + "changed name pixels inside=\(changes.inside), beyond column=\(changes.outside), "
                            + "original transcript ink=\(changes.transcriptInk)")
                        evidence.name = "Actual speaker glyph containment"; evidence.lifetime = .keepAlways
                        self.add(evidence)
                        XCTAssertGreaterThan(changes.inside, 24,
                                             "A blank or unchanged label cannot satisfy the render check")
                        XCTAssertGreaterThan(changes.transcriptInk, 24, "The original transcript must actually render")
                        XCTAssertEqual(changes.outside, 0,
                            "A longer speaker name must not paint beyond its column over the original transcript")
                    } catch { XCTFail("Speaker render measurement failed: \(error)") }
                }
            } catch {
                XCTFail("Speaker render setup failed: \(error)"); finish()
            }
        }
    }

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

    func testSpeakerDoubleClickOpensNameSheetAndCancelKeepsTranscript() {
        let segment = TranscriptSegment(source: .others, text: "The budget is $120.",
            isFinal: true, start: 34, end: 36, speakerID: "speaker-a", speakerName: "Dana")
        var changes: [String] = []
        let row = EditableTranscriptRow(segment: segment, speakerLabel: "Dana", copyTranscript: {},
            edit: { _ in XCTFail("Speaker click must not edit transcript text") }, delete: {}, addTerm: {},
            renameSpeaker: { changes.append($0) })
        host(row) { window, view, finish in
            guard let label = self.descendants(view).compactMap({ $0 as? MacSpeakerNameButton }).first else {
                XCTFail("Identified speaker control missing"); finish(); return
            }
            let point = label.convert(NSPoint(x: label.bounds.midX, y: label.bounds.midY), to: nil)
            self.click(window, point: point, count: 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let sheet = window.attachedSheet, let content = sheet.contentView else {
                    XCTFail("Speaker double-click must open the actual name sheet"); finish(); return
                }
                let fields = self.descendants(content).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
                XCTAssertEqual(fields.map(\.stringValue), ["Dana"])
                XCTAssertFalse(self.descendants(view).contains { ($0 as? NSTextField)?.isEditable == true },
                               "Speaker gesture must leave the transcript read-only")
                self.attach(content, name: "Speaker name sheet beside transcript editor")
                guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                    isARepeat: false, keyCode: 53) else {
                    XCTFail("Could not construct Cancel keyboard event"); finish(); return
                }
                sheet.makeKey()
                NSApp.sendEvent(escape)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    XCTAssertNil(window.attachedSheet)
                    XCTAssertTrue(changes.isEmpty, "Cancel must not save a name")
                    XCTAssertEqual(label.title, "Dana")
                    XCTAssertTrue(self.descendants(view).contains { ($0 as? NSTextView)?.string == segment.text })
                    finish()
                }
            }
        }
    }

    func testDoubleClickFinalRowOpensOnlyThatLineEditor() throws {
        let first = TranscriptSegment(source: .others, text: "The budget is $120.",
                                      isFinal: true, start: 34, end: 36,
                                      speakerID: "speaker-a", speakerName: "Dana", language: "en")
        let second = TranscriptSegment(source: .you, text: "The next review is Monday.",
                                       isFinal: true, start: 37, end: 39, language: "en")
        var changes: [String] = []
        let rows = VStack {
            EditableTranscriptRow(segment: first, speakerLabel: "Dana", copyTranscript: {},
                                  edit: { changes.append($0) }, delete: {}, addTerm: {},
                                  renameSpeaker: { _ in XCTFail("Text edit must not rename the speaker") })
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
                    XCTAssertNil(window.attachedSheet, "Text double-click must not open the name sheet")
                    XCTAssertTrue(self.descendants(view).contains { ($0 as? MacSpeakerNameButton)?.title == "Dana" })
                    XCTAssertTrue(changes.isEmpty, "Opening an editor must not save a change")
                    finish()
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func speakerRaster(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return bitmap
    }

    private func speakerPixelChanges(
        _ short: NSBitmapImageRep, _ long: NSBitmapImageRep, label: CGRect, transcript: CGRect, in view: NSView
    ) throws -> (inside: Int, outside: Int, transcriptInk: Int) {
        XCTAssertEqual(short.pixelsWide, long.pixelsWide)
        XCTAssertEqual(short.pixelsHigh, long.pixelsHigh)
        let scaleX = CGFloat(long.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(long.pixelsHigh) / view.bounds.height
        let top = view.isFlipped ? label.minY - view.bounds.minY : view.bounds.maxY - label.maxY
        let x0 = Int(ceil((label.minX - view.bounds.minX) * scaleX))
        let boundary = Int(ceil((label.maxX - view.bounds.minX) * scaleX))
        let textStart = Int(ceil((transcript.minX - view.bounds.minX) * scaleX))
        let y0 = Int(ceil(top * scaleY)), y1 = Int(floor((top + label.height) * scaleY))
        XCTAssertGreaterThanOrEqual(x0, 0); XCTAssertLessThan(boundary, long.pixelsWide)
        XCTAssertGreaterThanOrEqual(y0, 0); XCTAssertLessThanOrEqual(y1, long.pixelsHigh)
        guard x0 >= 0, boundary < long.pixelsWide, y0 >= 0, y1 <= long.pixelsHigh, y0 < y1 else {
            throw NSError(domain: "SpeakerRenderBounds", code: 1)
        }
        var inside = 0, outside = 0, transcriptInk = 0
        for y in y0..<y1 {
            for x in x0..<long.pixelsWide {
                let before = try XCTUnwrap(short.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let after = try XCTUnwrap(long.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if x >= textStart, before.alphaComponent > 0.99,
                   max(max(before.redComponent, before.greenComponent), before.blueComponent) < 0.7 {
                    transcriptInk += 1
                }
                let difference = max(max(abs(before.redComponent - after.redComponent),
                                         abs(before.greenComponent - after.greenComponent)),
                                     max(abs(before.blueComponent - after.blueComponent),
                                         abs(before.alphaComponent - after.alphaComponent)))
                if difference > 0.02 {
                    if x < boundary { inside += 1 }
                    // Ignore one physical antialias pixel at the measured column edge.
                    else if x > boundary { outside += 1 }
                }
            }
        }
        return (inside, outside, transcriptInk)
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

@MainActor private final class SpeakerNameRenderState: ObservableObject {
    @Published var name = "Dana"
    let lineID = UUID()
}

private struct SpeakerNameRenderRow: View {
    @ObservedObject var state: SpeakerNameRenderState
    let text: String
    var body: some View {
        let segment = TranscriptSegment(id: state.lineID, source: .others, text: text,
            isFinal: true, start: 34, end: 36, speakerID: "synthetic-speaker", speakerName: state.name)
        EditableTranscriptRow(segment: segment, speakerLabel: state.name.uppercased(),
            copyTranscript: {}, edit: { _ in }, delete: {}, addTerm: {}, renameSpeaker: { _ in })
    }
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
