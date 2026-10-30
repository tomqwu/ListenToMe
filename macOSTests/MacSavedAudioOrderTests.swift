import AppKit
import AVFoundation
import SwiftUI
import Vision
import XCTest
import ListenToMeCore

/// Exercise the actual History section and player with an explicitly injected temporary library.
/// Vision locates rendered text in the native bitmap; native pointer events activate those rows.
/// The only playback is generated digital silence. No microphone, user defaults or app archive is used.
@MainActor
final class MacSavedAudioOrderTests: XCTestCase {
    func testDelayedRowsRenderChronologicallyAndPlayOriginalSourceAndOffset() throws {
        try runNative {
            let first = UUID(), second = UUID()
            let rows = [
                self.line("UNTIMED BOUNDARY", 0, run: first, end: 0),
                self.line("LATER MICROPHONE", 20, run: first, source: .you),
                self.line("EARLIER SYSTEM", 17, run: first),
                self.line("TIED SYSTEM", 17, run: first),
                self.line("SECOND LATER", 48, run: second),
                self.line("SECOND EARLIER", 43, run: second)
            ]
            try await self.exercise(rows: rows, runs: [
                .init(sources: [.you, .others], offset: 2, firstSegment: 0),
                .init(sources: [.others], offset: 40, firstSegment: 4)
            ], expected: [
                .init(text: "EARLIER SYSTEM", part: 1, source: .others, time: 15),
                .init(text: "TIED SYSTEM", part: 1, source: .others, time: 15),
                .init(text: "LATER MICROPHONE", part: 1, source: .you, time: 18),
                .init(text: "SECOND EARLIER", part: 2, source: .others, time: 3),
                .init(text: "SECOND LATER", part: 2, source: .others, time: 8)
            ])
        }
    }

    func testUntimedAndLegacyBoundariesStayInPlaceAndLeavingStopsPlayback() throws {
        try runNative {
            let first = UUID()
            let rows = [
                self.line("BEFORE BOUNDARY", 20, run: first),
                self.line("UNTIMED BOUNDARY", 0, run: first, end: 0),
                self.line("AFTER BOUNDARY", 1, run: first),
                self.line("LEGACY LATER", 8, run: nil),
                self.line("LEGACY EARLIER", 2, run: nil)
            ]
            try await self.exercise(rows: rows, runs: [
                .init(sources: [.others], offset: 0, firstSegment: 0),
                .init(sources: [.others], offset: 0, firstSegment: 3)
            ], expected: [
                .init(text: "BEFORE BOUNDARY", part: 1, source: .others, time: 20),
                .init(text: "AFTER BOUNDARY", part: 1, source: .others, time: 1),
                .init(text: "LEGACY LATER", part: 2, source: .others, time: 8),
                .init(text: "LEGACY EARLIER", part: 2, source: .others, time: 2)
            ])
        }
    }

    func testRestoredDuplicateIDsKeepDistinctOriginalAudioTargets() throws {
        try runNative {
            let duplicate = UUID(), first = UUID(), second = UUID()
            let rows = [
                TranscriptSegment(id: duplicate, source: .others, text: "RESTORED FIRST", isFinal: true,
                                  start: 20, end: 21, recordingID: first),
                self.line("FIRST EARLIER", 17, run: first),
                TranscriptSegment(id: duplicate, source: .others, text: "RESTORED SECOND", isFinal: true,
                                  start: 6, end: 7, recordingID: second),
                self.line("SECOND EARLIER", 3, run: second)
            ]
            try await self.exercise(rows: rows, runs: [
                .init(sources: [.others], offset: 10, firstSegment: 0),
                .init(sources: [.others], offset: 0, firstSegment: 2)
            ], expected: [
                .init(text: "FIRST EARLIER", part: 1, source: .others, time: 7),
                .init(text: "RESTORED FIRST", part: 1, source: .others, time: 10),
                .init(text: "SECOND EARLIER", part: 2, source: .others, time: 3),
                .init(text: "RESTORED SECOND", part: 2, source: .others, time: 6)
            ])
        }
    }
}

extension MacSavedAudioOrderTests {
    private struct RunSpec {
        let sources: [SpeakerSource]
        let offset: TimeInterval
        let firstSegment: Int
    }
    private struct ExpectedLine {
        let text: String
        let part: Int
        let source: SpeakerSource
        let time: TimeInterval
    }
    private struct RenderedText {
        let text: String
        let bounds: CGRect // Vision's normalized lower-left origin.
    }

    private func line(_ text: String, _ start: TimeInterval, run: UUID?,
                      source: SpeakerSource = .others, end: TimeInterval? = nil) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true,
                          start: start, end: end ?? start + 1, recordingID: run)
    }

    private func exercise(rows: [TranscriptSegment], runs: [RunSpec], expected: [ExpectedLine]) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacAudioOrder-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SavedAudioLibrary(root: root.appendingPathComponent("Audio"), excludeFromBackup: true)
        let stored = SessionRecord(id: UUID().uuidString, title: "Synthetic saved-audio ordering",
            date: Date(timeIntervalSince1970: 0), transcript: "Synthetic only", summary: "", segments: rows)
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        try archive.save(stored)
        let record = try XCTUnwrap(archive.read().records.first)
        XCTAssertEqual(record.segments, rows, "Archive decoding must preserve every row, including duplicate IDs")
        for spec in runs {
            let parts = try library.beginRun(conversationID: record.id, sources: spec.sources,
                startedAt: Date(timeIntervalSince1970: 0), timelineOffset: spec.offset, timesMatchAudio: true)
            let index = try XCTUnwrap(parts.first?.index)
            library.anchor(conversationID: record.id, index: index, firstSegment: spec.firstSegment)
            for part in parts {
                let url = try XCTUnwrap(library.url(for: part, conversationID: record.id))
                try writeSilence(to: url)
                library.finishRun(conversationID: record.id, fileName: part.fileName,
                                  result: SavedAudioRunResult(duration: 30))
            }
        }
        let before = try snapshot(root)
        let owner = MacSavedAudio(library: library)
        defer { owner.playback.stop() }
        XCTAssertTrue(owner.library === library)
        XCTAssertEqual(owner.playback.library.root, root.appendingPathComponent("Audio"))
        XCTAssertFalse(owner.enabled)
        XCTAssertEqual(owner.retentionDays, 0)
        XCTAssertNil(owner.runs.recorder.recordingConversation)
        XCTAssertEqual(try snapshot(root), before, "Constructing the isolated owner must not apply retention")
        try await exerciseView(record: record, owner: owner, expected: expected)
        XCTAssertEqual(record.segments, rows, "Presentation must not rewrite canonical arrival order or metadata")
        XCTAssertEqual(try snapshot(root), before,
                       "Reading/seeking/leaving must preserve archive, manifest and audio bytes")
        XCTAssertFalse(owner.enabled); XCTAssertEqual(owner.retentionDays, 0)
        XCTAssertNil(owner.runs.recorder.recordingConversation)
    }

    private func exerciseView(record: SessionRecord, owner: MacSavedAudio, expected: [ExpectedLine]) async throws {
        // Supply the owner explicitly: the default singleton initializer must never execute.
        let host = NSHostingView(rootView: AnyView(MacSavedAudioSection(record: record, audio: owner)
            .padding(20).frame(width: 760, height: 360, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light)))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ListenToMe saved-audio order — synthetic silent fixture"
        window.contentView = host; host.appearance = NSAppearance(named: .aqua)
        defer { window.close() }
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        try await waitUntil { owner.playback.conversationID == record.id && owner.playback.hasAudio }
        try await Task.sleep(for: .milliseconds(150))
        let collapsed = try recognize(host, name: "Saved-audio collapsed real History section")
        let disclosure = try unique("Play from a line", in: collapsed)
        try await click(disclosure.bounds, host: host, window: window)
        let rendered = try recognize(host, name: "Saved-audio expanded real History section")
        let found = try expected.map { (expected: $0, rendered: try unique($0.text, in: rendered)) }
        XCTAssertFalse(rendered.contains { $0.text.contains("UNTIMED BOUNDARY") }, "Untimed lines have no seek control")
        XCTAssertEqual(found.sorted { $0.rendered.bounds.midY > $1.rendered.bounds.midY }.map { $0.expected.text },
                       expected.map(\.text), "Actual rendered rows must follow recording-aware presentation order")
        for (previous, next) in zip(found, found.dropFirst()) {
            XCTAssertGreaterThan(previous.rendered.bounds.midY, next.rendered.bounds.midY,
                                 "Each expected line must occupy a distinct row in presentation order")
        }
        for item in found {
            try await checkTarget(item.expected, bounds: item.rendered.bounds,
                                  owner: owner, host: host, window: window)
        }
        // A final actual row action starts silence; removing that real view exercises onDisappear.
        try await click(try XCTUnwrap(found.last).rendered.bounds, host: host, window: window)
        try await waitUntil { owner.playback.isPlaying }
        host.rootView = AnyView(EmptyView())
        try await waitUntil { owner.playback.conversationID == nil && !owner.playback.isPlaying }
        XCTAssertNil(owner.playback.selected)
    }

    private func checkTarget(_ expected: ExpectedLine, bounds: CGRect,
                             owner: MacSavedAudio, host: NSView, window: NSWindow) async throws {
        try await click(bounds, host: host, window: window)
        try await waitUntil { owner.playback.isPlaying }
        owner.playback.pause() // Inspect the real player after the actual row activated it.
        let selected = try XCTUnwrap(owner.playback.selected)
        let original = try XCTUnwrap(owner.playback.runs.first {
            $0.index == expected.part && $0.source == expected.source
        })
        XCTAssertEqual(selected, original, "\(expected.text) must select its original canonical audio part")
        XCTAssertEqual(owner.playback.currentTime, expected.time, accuracy: 0.3,
                       "\(expected.text) must retain its recording-relative seek offset")
        XCTAssertNil(owner.playback.problem)
    }

    private func writeSilence(to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: SavedAudioFileWriter.fileSettings,
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 30)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.update(repeating: 0, count: Int(frames))
        try file.write(from: buffer)
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root,
                                                               includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in files {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
        }
        return result
    }

    private func recognize(_ host: NSView, name: String) throws -> [RenderedText] {
        host.layoutSubtreeIfNeeded(); host.window?.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        let result = (request.results ?? []).compactMap { observation -> RenderedText? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RenderedText(text: text, bounds: observation.boundingBox)
        }
        let observed = XCTAttachment(string: result.map { "\($0.text) \($0.bounds)" }.joined(separator: "\n"))
        observed.name = name + " observed text positions"; observed.lifetime = .keepAlways; add(observed)
        return result
    }

    private func unique(_ text: String, in observed: [RenderedText]) throws -> RenderedText {
        let matches = observed.filter { $0.text.localizedCaseInsensitiveContains(text) }
        XCTAssertEqual(matches.count, 1, "Native bitmap must contain exactly one rendered label: \(text)")
        return try XCTUnwrap(matches.count == 1 ? matches.first : nil)
    }

    private func click(_ bounds: CGRect, host: NSView, window: NSWindow) async throws {
        XCTAssertGreaterThan(bounds.width, 0); XCTAssertGreaterThan(bounds.height, 0)
        let local = NSPoint(x: bounds.midX * host.bounds.width,
                            y: (host.isFlipped ? 1 - bounds.midY : bounds.midY) * host.bounds.height)
        XCTAssertTrue(host.bounds.contains(local))
        _ = try XCTUnwrap(host.hitTest(local), "Rendered row must have a native hit target")
        let point = host.convert(local, to: nil), time = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: time, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: time + 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        NSApp.postEvent(up, atStart: true); window.sendEvent(down)
        if let release = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
            if release.windowNumber == window.windowNumber {
                window.sendEvent(release)
            } else {
                NSApp.postEvent(release, atStart: true); XCTFail("Unexpected foreign native window event")
            }
        }
        try await Task.sleep(for: .milliseconds(80))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        _ = try XCTUnwrap(condition() ? true : nil, "Actual native action did not complete")
    }

    private func runNative(_ exercise: @escaping @MainActor () async throws -> Void) throws {
        _ = NSApplication.shared
        let oldPolicy = NSApp.activationPolicy()
        XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
        defer { NSApp.setActivationPolicy(oldPolicy) }
        var finished = false
        var failure: Error?
        var worker: Task<Void, Never>?
        func finish() {
            guard !finished else { return }
            finished = true; NSApp.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            worker = Task { @MainActor in
                do { try await exercise() } catch { failure = error }
                finish()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard !finished else { return }
            XCTFail("Native saved-audio order exercise exceeded its deadline")
            worker?.cancel()
        }
        NSApp.run()
        XCTAssertTrue(finished)
        if let failure { throw failure }
    }
}
