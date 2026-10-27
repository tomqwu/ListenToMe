import AVFoundation
import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

@MainActor
final class MobileWatchLanguageTests: XCTestCase {
    private var root: URL!
    private var automatic: Any?
    private var language: Any?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        automatic = UserDefaults.standard.object(forKey: MobileLanguageDetection.automaticKey)
        language = UserDefaults.standard.object(forKey: MobileSession.languageKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.set(automatic, forKey: MobileLanguageDetection.automaticKey)
        UserDefaults.standard.set(language, forKey: MobileSession.languageKey)
    }

    private func session(_ model: CachedWatchLanguageModel, transcriber: FakeWatchTranscriber) -> MobileSession {
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() },
                                    makeWatchTranscriber: { transcriber }, makeLanguageModel: { model })
        session.applicationIsActive = { true }
        session.languageChoice = MobileSession.automaticLanguageTag
        session.watchLanguageSamples = { _ in Array(repeating: 0.1, count: 160_000) }
        return session
    }

    private func deliver(_ session: MobileSession, id: UUID, index: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("input.m4a")
        try Data([0]).write(to: file)
        let metadata = WatchChunkMetadata(recordingID: id, index: index, startOffset: Double(index) * 300,
                                          duration: 300, isLast: false, startedAt: Date(), watchBuild: "test")
        XCTAssertEqual(session.watchInbox.accept(fileAt: file, metadata: metadata.transferMetadata, now: Date()), .stored)
    }

    func testReceivedAACDecodesForLanguageAndSpeakersWithoutConsumingSource() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "watch-chunk-0", withExtension: "m4a"))
        let original = try Data(contentsOf: url)
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        // Speaker inference deliberately ignores windows shorter than five seconds.
        let chunks = (0..<4).map { index in
            WatchAudioChunk(index: index, url: url, startOffset: 42 + Double(index) * seconds, duration: seconds)
        }
        let samples = try await WatchLanguageAudio.samples(chunks)
        XCTAssertGreaterThan(samples.count, 1_000)
        XCTAssertLessThanOrEqual(samples.count, 480_000)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
        XCTAssertTrue(samples.contains { abs($0) > 0.01 }, "Actual decoded speech, not empty padding")
        let reader = WatchSpeakerAudio(chunks: chunks)
        let window = try await reader.next()
        XCTAssertEqual(try XCTUnwrap(window).start, 42, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(window).samples.count, 16_000)
        let end = try await reader.next()
        XCTAssertNil(end)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testUnreadableAndCancelledAudioAnalysisPreservesSource() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("bad.m4a")
        let original = Data("not audio".utf8)
        try original.write(to: url)
        let chunks = [WatchAudioChunk(index: 0, url: url, startOffset: 0, duration: 5)]
        do {
            _ = try await WatchLanguageAudio.samples(chunks)
            XCTFail("Unreadable audio must report a failure")
        } catch { XCTAssertFalse(error is CancellationError) }
        let brokenReader = WatchSpeakerAudio(chunks: chunks)
        do { _ = try await brokenReader.next(); XCTFail("Unreadable speaker audio must fail") }
        catch { XCTAssertFalse(error is CancellationError) }
        let valid = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "watch-chunk-0", withExtension: "m4a"))
        let validBytes = try Data(contentsOf: valid)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await WatchLanguageAudio.samples([
                WatchAudioChunk(index: 0, url: valid, startOffset: 0, duration: 2),
            ])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let reader = WatchSpeakerAudio(chunks: [
            WatchAudioChunk(index: 0, url: valid, startOffset: 0, duration: 2),
        ])
        let speakerTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.next()
        }
        do { _ = try await speakerTask.value; XCTFail("Expected speaker cancellation") } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: valid), validBytes)
    }

    func testAudioSamplingSkipsLeadingSilenceAndCapsSpeech() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("speech.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            for second in 0..<80 {
                for sample in 0..<16_000 {
                    buffer.floatChannelData![0][sample] = second < 40 ? 0 : 0.3 * sin(Float(sample) * 0.1)
                }
                try file.write(from: buffer)
            }
        }
        let result = try await WatchLanguageAudio.samples([
            WatchAudioChunk(index: 0, url: url, startOffset: 0, duration: 80),
        ])
        XCTAssertEqual(result.count, 480_000)
        XCTAssertGreaterThan(result.map { abs($0) }.reduce(0, +) / Float(result.count), 0.1)
    }

    func testCancellationDoesNotPinFallbackOrTranscribe() async throws {
        let transcriber = FakeWatchTranscriber()
        let session = session(CachedWatchLanguageModel(), transcriber: transcriber)
        session.watchLanguageSamples = { _ in throw CancellationError() }
        let id = UUID()
        try deliver(session, id: id, index: 0)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertNil(session.watchInbox.ledger(id)?.transcriptionLocale)
        XCTAssertTrue(transcriber.locales.isEmpty)
    }

    func testDetectedLocalePersistsAcrossSessionAndSettingsChanges() async throws {
        let id = UUID(), model = CachedWatchLanguageModel()
        let first = FakeWatchTranscriber()
        first.script[0] = [.init(text: "你好", start: 0, end: 300)]
        let initial = session(model, transcriber: first)
        try deliver(initial, id: id, index: 0)
        initial.importWatchInbox()
        await initial.watchDrainTask?.value
        XCTAssertEqual(first.locales.first?.identifier, "zh-CN")
        XCTAssertEqual(initial.history.first?.language, "zh-CN")
        XCTAssertEqual(initial.watchInbox.ledger(id)?.transcriptionLocale, "zh-CN")

        let second = FakeWatchTranscriber()
        let resumed = session(model, transcriber: second)
        resumed.languageChoice = "es-ES"
        try deliver(resumed, id: id, index: 1)
        resumed.importWatchInbox()
        await resumed.watchDrainTask?.value
        XCTAssertEqual(second.locales.first?.identifier, "zh-CN")
        let calls = await model.detections
        XCTAssertEqual(calls, 1)
    }

    func testMissingModelSkipsAudioAndNeverDownloads() async throws {
        let model = CachedWatchLanguageModel(available: false)
        let transcriber = FakeWatchTranscriber()
        let session = session(model, transcriber: transcriber)
        session.watchLanguageSamples = { _ in XCTFail("Missing model must skip decoding"); return [] }
        try deliver(session, id: UUID(), index: 0)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(transcriber.locales.first?.identifier, Locale.current.identifier)
        let calls = await model.detections
        XCTAssertEqual(calls, 0)
    }

    func testLowConfidenceKeepsDeviceLocale() async throws {
        let transcriber = FakeWatchTranscriber()
        let session = session(CachedWatchLanguageModel(confidence: 0.2), transcriber: transcriber)
        try deliver(session, id: UUID(), index: 0)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(transcriber.locales.first?.identifier, Locale.current.identifier)
    }

    func testFixedLanguageSkipsDetection() async throws {
        let model = CachedWatchLanguageModel()
        let transcriber = FakeWatchTranscriber()
        let session = session(model, transcriber: transcriber)
        session.languageChoice = "fr-CA"
        try deliver(session, id: UUID(), index: 0)
        session.importWatchInbox()
        await session.watchDrainTask?.value
        XCTAssertEqual(transcriber.locales.first?.identifier, "fr-CA")
        let calls = await model.detections
        XCTAssertEqual(calls, 0)
    }
}

private actor CachedWatchLanguageModel: MobileLanguageIdentifying {
    let available: Bool
    let confidence: Double
    private(set) var detections = 0
    init(available: Bool = true, confidence: Double = 0.99) {
        self.available = available
        self.confidence = confidence
    }
    func prepare() async throws { XCTFail("Watch imports must never initiate downloads") }
    func prepareIfDownloaded() async throws -> Bool { available }
    func detect(samples: [Float]) async throws -> LanguageGuess {
        detections += 1
        return LanguageGuess(language: "zh", probability: confidence)
    }
    func supportedLocales() async -> [String] { ["en-US", "zh-CN"] }
}
