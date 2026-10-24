import AVFoundation
import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

@MainActor
final class MobileWatchSpeakerTests: XCTestCase {
    private var root: URL!
    private var priorEnabled: Any?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        priorEnabled = UserDefaults.standard.object(forKey: MobileSpeakers.enabledKey)
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(priorEnabled, forKey: MobileSpeakers.enabledKey)
        try? FileManager.default.removeItem(at: root)
    }

    private func audio(seconds: Int, offset: Double = 0, index: Int = 0) throws -> WatchAudioChunk {
        let url = root.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for _ in 0..<seconds { try file.write(from: buffer) }
        return WatchAudioChunk(index: index, url: url, startOffset: offset, duration: Double(seconds))
    }

    func testWindowsCoverLongAudioWithoutFillingGapsOrGrowingPCM() async throws {
        let reader = WatchSpeakerAudio(chunks: [try audio(seconds: 725), try audio(seconds: 7, offset: 900, index: 1)])
        var windows: [(Double, Double)] = []
        while let window = try await reader.next() {
            XCTAssertLessThanOrEqual(window.samples.count, 60 * 16_000)
            windows.append((window.start, window.start + Double(window.samples.count) / 16_000))
        }
        XCTAssertEqual(windows.first?.0, 0)
        XCTAssertEqual(windows[windows.count - 2].1, 725)
        XCTAssertEqual(windows.last?.0, 900)
        XCTAssertEqual(windows.last?.1, 907)
        for pair in zip(windows.dropLast(2), windows.dropFirst().dropLast()) {
            XCTAssertLessThanOrEqual(pair.1.0, pair.0.1, "No uncovered audio between windows")
        }
    }

    func testOverlappingChunkOffsetsMatchTheTranscriberAndCancellationStopsReading() async throws {
        let reader = WatchSpeakerAudio(chunks: [try audio(seconds: 10, offset: 100),
                                                try audio(seconds: 10, offset: 105, index: 1)])
        let window = try await reader.next()
        XCTAssertEqual(window?.start, 100)
        XCTAssertEqual(window?.samples.count, 320_000)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.next()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { throw error }
    }

    func testWatchImportsDoNotPrepareModelsOrTouchLiveRun() async throws {
        let model = WatchSpeakerModel()
        let speakers = MobileSpeakers(makeDiarizer: { model })
        let unavailable = try await speakers.analyzeFileWindow(Array(repeating: 0.1, count: 160_000))
        XCTAssertNil(unavailable)
        let before = await model.counts()
        XCTAssertEqual(before.0, 0)
        XCTAssertEqual(before.1, 0)
        _ = speakers.beginRun(offset: 42, existing: [])
        await speakers.preparation?.value
        let token = speakers.runToken
        let result = try await speakers.analyzeFileWindow(Array(repeating: 0.1, count: 160_000))
        XCTAssertNotNil(result)
        XCTAssertEqual(speakers.runToken, token)
        XCTAssertTrue(speakers.isRunning)
        speakers.enabled = false
        let disabled = try await speakers.analyzeFileWindow(Array(repeating: 0.1, count: 160_000))
        XCTAssertNil(disabled)
        speakers.endRun()
    }

    func testWindowIdentitiesSurviveModelClusterChangesAndKeepWatchProvenance() {
        var labels = WatchSpeakerLabels(existing: [])
        labels.append(DiarizedWindow(segments: [DiarizedSegment(speakerId: "a", start: 0, duration: 60)],
                                     embeddings: ["a": [1, 0]]), at: 100)
        labels.append(DiarizedWindow(segments: [DiarizedSegment(speakerId: "b", start: 0, duration: 60)],
                                     embeddings: ["b": [1, 0]]), at: 150)
        let first = labels.label(TranscriptSegment(source: .you, text: "First", isFinal: true, start: 110, end: 120,
                                                   speakerName: MobileFileTranscriber.speakerName))
        var last = labels.label(TranscriptSegment(source: .you, text: "Last", isFinal: true, start: 190, end: 200,
                                                  speakerName: MobileFileTranscriber.speakerName))
        XCTAssertNotNil(first.speakerID)
        XCTAssertEqual(first.speakerID, last.speakerID)
        last.speakerName = "Alice"
        XCTAssertTrue(MobileSession.isWatchLine(last))
        XCTAssertEqual(MobileSession.promptSegment(last).speakerName, "Alice")
        let unheard = labels.label(TranscriptSegment(source: .you, text: "Gap", isFinal: true, start: 80, end: 90,
                                                     speakerName: MobileFileTranscriber.speakerName))
        XCTAssertNil(unheard.speakerID)
        XCTAssertNil(MobileSession.promptSegment(unheard).speakerName, "Unidentified Watch speech still means You")
    }

    func testDrainSavesLabelsBeforeDeletingAudioAndKeepsOpenConversation() async throws {
        let model = WatchSpeakerModel()
        let transcriber = FakeWatchTranscriber()
        transcriber.script = [0: [.init(text: "Budget review", start: 1, end: 5)]]
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() },
                                    makeWatchTranscriber: { transcriber }, makeDiarizer: { model })
        session.applicationIsActive = { true }
        session.languageChoice = "en-US"
        session.speakers.startPreparing()
        await session.speakers.preparation?.value
        let originalID = session.id
        session.notes = "My open conversation"
        let chunk = try audio(seconds: 10)
        let recording = UUID()
        let metadata = WatchChunkMetadata(recordingID: recording, index: 0, startOffset: 0, duration: 10,
                                          isLast: false, startedAt: Date(), watchBuild: "test")
        XCTAssertEqual(session.watchInbox.accept(fileAt: chunk.url, metadata: metadata.transferMetadata, now: Date()), .stored)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(session.id, originalID)
        XCTAssertEqual(session.notes, "My open conversation")
        let record = try XCTUnwrap(session.history.first { MobileSession.isFromAppleWatch($0) })
        XCTAssertEqual(record.segments?.first?.speakerName, "Speaker 1")
        XCTAssertTrue(record.transcript.contains("Speaker 1"))
        let saved = try XCTUnwrap(SessionArchive(directory: root.appendingPathComponent("Conversations")).all()
            .first { $0.id == record.id })
        XCTAssertEqual(saved.segments, record.segments)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.watchInbox.chunkURL(recordingID: recording, index: 0).path))
        session.open(saved)
        let speakerID = try XCTUnwrap(session.segments.first?.speakerID)
        session.renameSpeaker(id: speakerID, to: "Alice")
        XCTAssertTrue(MobileSession.isWatchLine(try XCTUnwrap(session.segments.first)))
        XCTAssertEqual(session.segments.first?.speakerName, "Alice")
        XCTAssertFalse(session.isSummarizing)
        let second = try audio(seconds: 10, offset: 300, index: 1)
        let next = WatchChunkMetadata(recordingID: recording, index: 1, startOffset: 300, duration: 10,
                                      isLast: true, startedAt: metadata.startedAt, watchBuild: "test")
        transcriber.script[1] = [.init(text: "Same person later", start: 301, end: 305)]
        XCTAssertEqual(session.watchInbox.accept(fileAt: second.url, metadata: next.transferMetadata, now: Date()), .stored)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(session.segments.last?.speakerID, speakerID)
        XCTAssertEqual(session.segments.last?.speakerName, "Alice")
        XCTAssertTrue(session.watchSpeakerContexts.isEmpty, "Completed imports discard voiceprints")
    }

    func testExistingPreparationIsAwaitedAndCancellationDoesNotConsumeAudio() async throws {
        let model = WatchSpeakerModel()
        await model.holdPreparation()
        let transcriber = FakeWatchTranscriber()
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() },
                                    makeWatchTranscriber: { transcriber }, makeDiarizer: { model })
        session.applicationIsActive = { true }
        session.languageChoice = "en-US"
        session.speakers.startPreparing()
        let chunk = try audio(seconds: 10)
        let recording = UUID()
        let metadata = WatchChunkMetadata(recordingID: recording, index: 0, startOffset: 0, duration: 10,
                                          isLast: true, startedAt: Date(), watchBuild: "test")
        XCTAssertEqual(session.watchInbox.accept(fileAt: chunk.url, metadata: metadata.transferMetadata, now: Date()), .stored)
        session.importWatchInbox()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(transcriber.calls.isEmpty)
        session.watchDrainTask?.cancel()
        await session.watchDrainTask?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.watchInbox.chunkURL(recordingID: recording, index: 0).path))
        XCTAssertTrue(session.watchSpeakerContexts.isEmpty)
        await model.releasePreparation()
        await session.speakers.preparation?.value
        transcriber.script[0] = [.init(text: "Ready now", start: 1, end: 5)]
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(session.history.first { MobileSession.isFromAppleWatch($0) }?.segments?.first?.speakerName, "Speaker 1")
        let counts = await model.counts()
        XCTAssertEqual(counts.0, 1, "The import never initiates another preparation")
    }
}

private actor WatchSpeakerModel: MobileSpeakerDiarizing {
    private var preparations = 0
    private var passes = 0
    func counts() -> (Int, Int) { (preparations, passes) }
    private var shouldHold = false
    private var gate: CheckedContinuation<Void, Never>?
    func holdPreparation() { shouldHold = true }
    func releasePreparation() { shouldHold = false; gate?.resume(); gate = nil }
    func prepareModels() async throws {
        preparations += 1
        if shouldHold { await withCheckedContinuation { gate = $0 } }
    }
    func retryModelLoad() async {}
    func diarize(samples: [Float]) async throws -> DiarizedWindow {
        passes += 1
        return DiarizedWindow(segments: [DiarizedSegment(speakerId: "voice", start: 0,
                                                        duration: Double(samples.count) / 16_000)],
                              embeddings: ["voice": [1, 0]])
    }
}
