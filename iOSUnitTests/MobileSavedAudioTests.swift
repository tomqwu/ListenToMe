import AVFoundation
import Speech
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Stands in for the m4a writer: records what it was given. No audio is captured or encoded.
final class FakeSavedAudioWriter: SavedAudioWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [(samples: Int, rate: Double)] = []
    private var finishedFlag = false
    private var cancelledFlag = false
    let url: URL
    let onFinish: @Sendable (SavedAudioRunResult) -> Void
    let onFailure: @Sendable (String) -> Void

    init(url: URL, onFailure: @escaping @Sendable (String) -> Void,
         onFinish: @escaping @Sendable (SavedAudioRunResult) -> Void) {
        self.url = url
        self.onFailure = onFailure
        self.onFinish = onFinish
    }

    var seconds: Double { lock.withLock { chunks.reduce(0) { $0 + Double($1.samples) / $1.rate } } }
    var appendCount: Int { lock.withLock { chunks.count } }
    var finished: Bool { lock.withLock { finishedFlag } }
    var cancelled: Bool { lock.withLock { cancelledFlag } }

    func append(samples: [Float], sampleRate: Double, timestamp: TimeInterval?) {
        lock.withLock { chunks.append((samples.count, sampleRate)) }
    }

    /// Writes a placeholder file and reports the seconds it was given, as the real writer would.
    func finish() {
        lock.withLock { finishedFlag = true }
        let duration = seconds
        if duration > 0 { try? Data([0]).write(to: url) }
        onFinish(SavedAudioRunResult(duration: duration))
    }

    func cancel() { lock.withLock { cancelledFlag = true } }
}

/// Collects the writers a recorder makes.
final class FakeWriterFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [FakeSavedAudioWriter] = []
    var writers: [FakeSavedAudioWriter] { lock.withLock { made } }

    var factory: SavedAudioRecorder.WriterFactory {
        { [self] url, failure, finish in
            let writer = FakeSavedAudioWriter(url: url, onFailure: failure, onFinish: finish)
            lock.withLock { made.append(writer) }
            return writer
        }
    }
}

/// A recorder that delivers one line and feeds the attached writer, like the real recorder's sink.
@MainActor
final class SavedAudioTestRecorder: MobileRecording {
    private(set) var writer: (any SavedAudioWriting)?
    private(set) var attachCount = 0
    private var receive: (@MainActor (TranscriptSegment) -> Void)?

    func attachSavedAudio(_ writer: (any SavedAudioWriting)?) {
        attachCount += 1
        self.writer = writer
    }

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { receive = onSegment }

    func stop() async throws {
        writer?.finish()
        writer = nil
        receive = nil
    }

    func reconfigure() async throws {}

    func speak(_ text: String, from start: TimeInterval, to end: TimeInterval) {
        writer?.append(samples: [Float](repeating: 0, count: Int((end - start) * 16_000)), sampleRate: 16_000,
                       timestamp: nil)
        receive?(TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end))
    }
}

@MainActor
final class MobileSavedAudioTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: "saved-audio-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func savedAudio(_ factory: FakeWriterFactory, free: Int64? = 50_000_000_000) -> MobileSavedAudio {
        MobileSavedAudio(root: root.appendingPathComponent("SavedAudio"), defaults: defaults,
                         availableBytes: { free }, makeWriter: factory.factory)
    }

    private func session(_ recorder: SavedAudioTestRecorder, audio: MobileSavedAudio) -> MobileSession {
        MobileSession(storageDirectory: root, makeRecorder: { recorder }, savedAudio: audio)
    }

    private func record(_ session: MobileSession) async throws {
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
    }

    private func settle(_ condition: @autoclosure () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    func testOffByDefaultSoNoAudioIsWritten() async throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory)
        XCTAssertFalse(audio.enabled, "Save audio recordings is opt-in")
        let recorder = SavedAudioTestRecorder()
        let session = session(recorder, audio: audio)
        try await record(session)
        XCTAssertEqual(recorder.attachCount, 1)
        XCTAssertNil(recorder.writer, "Nothing is attached while the setting is off")
        XCTAssertTrue(factory.writers.isEmpty)
        await session.stop()
        XCTAssertFalse(audio.library.hasAudio(session.id))
    }

    func testEachRunSavesAFilePlacedWhereItsLinesStartAndDeletingTheConversationDeletesIt() async throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory)
        audio.enabled = true
        XCTAssertTrue(SavedAudioPolicy.isEnabled(in: defaults), "The choice is remembered")
        let recorder = SavedAudioTestRecorder()
        let session = session(recorder, audio: audio)

        try await record(session)
        XCTAssertTrue(audio.isSavingRun)
        recorder.speak("first run", from: 0, to: 4)
        await session.stop()
        XCTAssertFalse(audio.isSavingRun)
        try await record(session)
        recorder.speak("second run", from: 0, to: 2)
        await session.stop()

        XCTAssertEqual(factory.writers.count, 2)
        XCTAssertTrue(factory.writers.allSatisfy(\.finished), "Stop finishes the run's file")
        let runs = audio.runs(for: session.id)
        XCTAssertEqual(runs.map(\.index), [1, 2], "One file per Start")
        XCTAssertEqual(runs.map(\.timelineOffset), [0, 4], "The second run starts where the first run's lines ended")
        XCTAssertEqual(runs.first?.duration ?? 0, 4, accuracy: 0.01)
        XCTAssertTrue(runs.allSatisfy(\.timesMatchAudio))
        XCTAssertEqual(session.savedAudioFiles.count, 2)
        XCTAssertTrue(session.canPlaySavedAudio)
        // Lines seek into the run that recorded them.
        let second = try XCTUnwrap(session.segments.last)
        XCTAssertEqual(second.start, 4)
        XCTAssertEqual(SavedAudioSeek.target(for: second, index: 1, in: runs)?.run.index, 2)
        XCTAssertEqual(SavedAudioSeek.target(for: second, index: 1, in: runs)?.time ?? -1, 0, accuracy: 0.001)

        let id = session.id
        session.deleteConversation(id: id)
        XCTAssertFalse(audio.library.hasAudio(id), "Deleting the conversation deletes its audio")
        XCTAssertEqual(audio.library.totalBytes(), 0)
    }

    func testLowStorageSavesNoAudioButTheRecordingGoesOn() async throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory, free: 1_000)
        audio.enabled = true
        let recorder = SavedAudioTestRecorder()
        let session = session(recorder, audio: audio)
        try await record(session)
        XCTAssertNil(recorder.writer)
        try await settle(audio.problem != nil)
        XCTAssertTrue(try XCTUnwrap(audio.problem).contains("Transcription continues"))
        XCTAssertEqual(session.state, .recording, "Transcription is not stopped")
        audio.dismissProblem()
        XCTAssertNil(audio.problem)
        await session.stop()
    }

    func testAWriteFailureIsShownWithoutStoppingTheRecording() async throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory)
        audio.enabled = true
        let recorder = SavedAudioTestRecorder()
        let session = session(recorder, audio: audio)
        try await record(session)
        let writer = try XCTUnwrap(factory.writers.first)
        writer.onFailure(SavedAudioPolicy.failureMessage(CocoaError(.fileWriteOutOfSpace), availableBytes: 0))
        try await settle(audio.problem != nil)
        XCTAssertTrue(try XCTUnwrap(audio.problem).contains("storage is full"))
        XCTAssertEqual(session.state, .recording)
        await session.stop()
    }

    func testDeleteAllAndRetentionRemoveAudioButKeepTranscripts() async throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory)
        audio.enabled = true
        let recorder = SavedAudioTestRecorder()
        let session = session(recorder, audio: audio)
        try await record(session)
        recorder.speak("kept text", from: 0, to: 3)
        await session.stop()
        try await settle(audio.bytesUsed > 0)
        XCTAssertGreaterThan(audio.bytesUsed, 0)

        audio.retentionDays = 7
        audio.applyRetention(now: Date().addingTimeInterval(8 * 86_400))
        XCTAssertEqual(audio.bytesUsed, 0, "Audio older than the retention is deleted")
        XCTAssertEqual(session.segments.map(\.text), ["kept text"], "The transcript stays")

        try await record(session)
        recorder.speak("more", from: 0, to: 1)
        await session.stop()
        XCTAssertTrue(audio.library.hasAudio(session.id))
        audio.deleteAll()
        XCTAssertFalse(audio.library.hasAudio(session.id))
        XCTAssertEqual(audio.bytesUsed, 0)
        XCTAssertEqual(session.segments.count, 2)
    }

    func testDeletingWhileAWriterRunsCancelsIt() throws {
        let factory = FakeWriterFactory()
        let audio = savedAudio(factory)
        audio.enabled = true
        let writer = try XCTUnwrap(audio.beginRun(conversation: "CONVERSATION-1", offset: 0) as? FakeSavedAudioWriter)
        audio.delete(conversation: "CONVERSATION-1")
        XCTAssertTrue(writer.cancelled)
        XCTAssertFalse(audio.library.hasAudio("CONVERSATION-1"))
    }

    // MARK: Sink

    func testTheSinkCopiesOnlyAudioTheAnalyzerAccepted() {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let writer = FakeSavedAudioWriter(url: root.appendingPathComponent("x.m4a"), onFailure: { _ in },
                                          onFinish: { _ in })
        let language = SpeakerAudioBuffer()
        let sink = AnalyzerSink(input: input, destination: format, speakerAudio: nil, speakerGeneration: 0,
                                languageAudio: language, languageGeneration: language.currentGeneration(),
                                savedAudio: writer)
        let second = AudioChunk(samples: [Float](repeating: 0.1, count: 48_000), sampleRate: 48_000, source: .you,
                                timestamp: 0)
        XCTAssertEqual(sink.deliver(second), .accepted)
        XCTAssertEqual(sink.deliver(second), .dropped)
        XCTAssertEqual(writer.seconds, 1, accuracy: 0.001, "A dropped chunk is not saved, so times stay aligned")
        XCTAssertEqual(Double(language.sampleCount) / 16_000, 1, accuracy: 0.01, "The language buffer is unchanged")
        _ = sink.hold()
        XCTAssertEqual(sink.deliver(second), .accepted)
        XCTAssertEqual(writer.appendCount, 2, "Audio parked during a language switch is saved once")
        withExtendedLifetime(stream) {}
    }

    // MARK: The real writer, fed synthetic samples (no microphone)

    private func waitForResult(_ expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 10)
    }

    func testTheFileWriterEncodesA16kHzM4AAndFillsCaptureGaps() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("part-001-microphone.m4a")
        let done = expectation(description: "finished")
        let result = ResultBox()
        let writer = SavedAudioFileWriter(url: url, onFailure: { XCTFail($0) }, onFinish: {
            result.value = $0
            done.fulfill()
        })
        let tone = (0..<48_000).map { Float(sin(Double($0) * 0.05) * 0.3) }
        writer.append(samples: tone, sampleRate: 48_000, timestamp: 0.5)
        writer.append(samples: tone, sampleRate: 48_000, timestamp: 3.5)   // a 2 s gap is filled with silence
        writer.finish()
        writer.append(samples: tone, sampleRate: 48_000, timestamp: 4.5)   // after finish: ignored
        await waitForResult(done)
        let finished = try XCTUnwrap(result.value)
        XCTAssertEqual(finished.firstTimestamp, 0.5)
        XCTAssertEqual(finished.duration, 4, accuracy: 0.1)
        XCTAssertNil(finished.failure)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, 4, accuracy: 0.15)
        XCTAssertLessThan(try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize), 40_000)
    }

    func testTheFileWriterReportsAFailureOnceAndStillFinishes() async throws {
        let url = root.appendingPathComponent("missing-folder/part-001-microphone.m4a")
        let failed = expectation(description: "failed")
        let done = expectation(description: "finished")
        let messages = ResultBox()
        let writer = SavedAudioFileWriter(url: url, onFailure: { message in
            messages.messages.append(message)
            failed.fulfill()
        }, onFinish: {
            messages.value = $0
            done.fulfill()
        })
        writer.append(samples: [Float](repeating: 0, count: 1_600), sampleRate: 16_000, timestamp: nil)
        writer.append(samples: [Float](repeating: 0, count: 1_600), sampleRate: 16_000, timestamp: nil)
        await fulfillment(of: [failed], timeout: 10)
        writer.finish()
        await waitForResult(done)
        XCTAssertEqual(messages.messages.count, 1)
        XCTAssertTrue(messages.messages[0].contains("Transcription continues"))
        XCTAssertNotNil(messages.value?.failure)
    }

    func testACancelledWriterReportsNothing() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let writer = SavedAudioFileWriter(url: root.appendingPathComponent("a.m4a"), onFailure: { XCTFail($0) },
                                          onFinish: { _ in XCTFail("A cancelled writer does not finish") })
        writer.append(samples: [Float](repeating: 0, count: 1_600), sampleRate: 16_000, timestamp: nil)
        writer.cancel()
        writer.finish()
        writer.append(samples: [Float](repeating: 0, count: 1_600), sampleRate: 16_000, timestamp: nil)
        try await Task.sleep(for: .milliseconds(200))
    }
}

private final class ResultBox: @unchecked Sendable {
    var value: SavedAudioRunResult?
    var messages: [String] = []
}
