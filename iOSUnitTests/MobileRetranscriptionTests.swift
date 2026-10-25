import XCTest
import AVFoundation
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileRetranscriptionTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func audio(_ library: SavedAudioLibrary, id: String, offset: Double = 0) throws -> SavedAudioRun {
        let run = try XCTUnwrap(library.beginRun(conversationID: id, sources: [.you], startedAt: Date(),
                                                timelineOffset: offset, timesMatchAudio: true).first)
        try Data([0]).write(to: XCTUnwrap(library.url(for: run, conversationID: id)))
        library.finishRun(conversationID: id, fileName: run.fileName,
                          result: SavedAudioRunResult(duration: 5, firstTimestamp: nil, failure: nil))
        return try XCTUnwrap(library.runs(for: id).last)
    }

    func testCompressedFileReaderRecognizesEOFWithoutDroppingFrames() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("audio.m4a")
        let frames: AVAudioFrameCount = 17_123
        do {
            let writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 24_000])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: frames))
            buffer.frameLength = frames
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<Int(frames) { channel[index] = Float(sin(Double(index) * 0.06) * 0.2) }
            try writer.write(from: buffer)
        }
        let reader = try XCTUnwrap(AudioFileChunkProducer(url: url, source: .others))
        var samples = 0
        while let chunk = try await reader.next() { samples += chunk.samples.count; XCTAssertEqual(chunk.source, .others) }
        XCTAssertEqual(samples, Int(frames))
        let eof = try await reader.next()
        XCTAssertNil(eof, "Normal AAC EOF must not be reported as a failed re-transcription")
    }

    func testApplyPreservesNotesAndSummariesAndRejectsStalePreview() throws {
        let session = MobileSession(storageDirectory: root)
        session.notes = "Keep these notes"; session.summary = "Keep summary"
        session.segments = [.init(source: .you, text: "Original", isFinal: true, start: 0, end: 2)]
        XCTAssertTrue(session.save(announce: false))
        let run = try audio(session.savedAudio.library, id: session.id)
        let replacement = TranscriptSegment(source: .you, text: "Bonjour", isFinal: true,
                                            start: 0, end: 2, language: "fr-FR")
        let preview = try ConversationRetranscription(original: session.currentRecord, segments: [replacement],
                                                       language: "fr-FR", audioRuns: [run])
        session.notes = "Latest notes"
        try session.applyRetranscription(preview)
        XCTAssertEqual(session.segments, [replacement])
        XCTAssertEqual(session.notes, "Latest notes")
        XCTAssertEqual(session.summary, "Keep summary")
        XCTAssertEqual(session.currentRecord.conversationLanguages.current, "fr-FR")
        XCTAssertThrowsError(try session.applyRetranscription(preview))
        let reopened = MobileSession(storageDirectory: root)
        XCTAssertEqual(reopened.segments, [replacement])
        XCTAssertEqual(reopened.notes, "Latest notes")
    }

    func testRetainedWatchReplacementKeepsDeviceProvenanceAfterReopen() async throws {
        let session = MobileSession(storageDirectory: root)
        session.segments = [.init(source: .you, text: "Original", isFinal: true, start: 10, end: 12,
                                  speakerID: "watch:old:1", speakerName: "Alex")]
        XCTAssertTrue(session.save(announce: false))
        let source = root.appendingPathComponent("watch-fixture.m4a")
        try Data([0]).write(to: source)
        try session.savedAudio.library.importWatchChunk(from: source, conversationID: session.id,
            recordingID: UUID(), chunkIndex: 0, startedAt: Date(), timelineOffset: 10, duration: 5)
        let draft = SavedAudioRetranscription()
        draft.start(original: session.currentRecord, library: session.savedAudio.library,
                    language: "fr-FR", terms: []) { _, _, _, _ in
            [.init(source: .you, text: "Bonjour", isFinal: true, start: 1, end: 3,
                   speakerID: "stale", speakerName: "Old identity")]
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while draft.isRunning && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(draft.isRunning)
        let preview = try XCTUnwrap(draft.preview)
        try session.applyRetranscription(preview)
        let reopened = MobileSession(storageDirectory: root)
        let line = try XCTUnwrap(reopened.segments.first)
        XCTAssertEqual(line.text, "Bonjour")
        XCTAssertEqual(line.start, 11)
        XCTAssertEqual(line.end, 13)
        XCTAssertEqual(line.speakerName, "Apple Watch")
        XCTAssertNil(line.speakerID, "Inferred identities must be reset")
        XCTAssertTrue(MobileSession.isWatchLine(line), "Live microphone analysis must still exclude Watch audio")
        let run = try XCTUnwrap(reopened.savedAudio.library.runs(for: reopened.id).first)
        XCTAssertEqual(run.deviceName, "Apple Watch")
        XCTAssertTrue(run.title(partCount: 1).contains("Apple Watch"))
        XCTAssertEqual(run.timelineOffset, 10)
    }

    func testCancelledUncooperativeRecognitionCannotOfferAReplacement() async throws {
        let library = SavedAudioLibrary(root: root, excludeFromBackup: true)
        _ = try audio(library, id: "one")
        let record = SessionRecord(id: "one", title: "Test", date: Date(), transcript: "Original", summary: "")
        let draft = SavedAudioRetranscription()
        var resume: CheckedContinuation<[TranscriptSegment], Never>?
        draft.start(original: record, library: library, language: "en-US", terms: []) { _, _, _, _ in
            await withCheckedContinuation { resume = $0 }
        }
        for _ in 0..<100 where resume == nil { await Task.yield() }
        XCTAssertNotNil(resume)
        draft.cancel()
        resume?.resume(returning: [.init(source: .you, text: "Late", isFinal: true, start: 0, end: 1)])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(draft.preview)
        XCTAssertFalse(draft.isRunning)
    }

    func testLaterTrackFailureNeverOffersPartialTranscript() async throws {
        let library = SavedAudioLibrary(root: root, excludeFromBackup: true)
        _ = try audio(library, id: "one")
        _ = try audio(library, id: "one", offset: 5)
        let record = SessionRecord(id: "one", title: "Test", date: Date(), transcript: "Original", summary: "")
        let draft = SavedAudioRetranscription()
        draft.start(original: record, library: library, language: "en-US", terms: ["Acme"]) { _, run, language, terms in
            XCTAssertEqual(language, "en-US"); XCTAssertEqual(terms, ["Acme"])
            if run.index == 2 { throw CocoaError(.fileReadCorruptFile) }
            return [.init(source: .you, text: "First", isFinal: true, start: 0, end: 1)]
        }
        for _ in 0..<100 where draft.isRunning { await Task.yield() }
        XCTAssertFalse(draft.isRunning)
        XCTAssertNotNil(draft.error)
        XCTAssertNil(draft.preview)
    }
}
