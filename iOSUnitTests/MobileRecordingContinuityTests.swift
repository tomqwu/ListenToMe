import AVFoundation
import Speech
import SwiftUI
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Real session/sink boundaries; the recorder and provider avoid microphone, model and network use.
@MainActor
final class MobileRecordingContinuityTests: XCTestCase {
    private var root: URL!
    private var defaults: [String: Any] = [:]

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = UserDefaults.standard.dictionaryRepresentation().filter { tracked($0.key) }
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        UserDefaults.standard.set(false, forKey: "autoQuickSummary")
        UserDefaults.standard.set(false, forKey: MobileLanguageDetection.automaticKey)
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where tracked(key) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in defaults { UserDefaults.standard.set(value, forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    private func tracked(_ key: String) -> Bool { key.hasPrefix("mobile") || key == "autoQuickSummary" }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 where !predicate() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }

    private func session(_ recorder: ContinuityRecorder, provider: (any LLMProvider)? = nil,
                         audio: MobileSavedAudio? = nil) -> MobileSession {
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    autoInterval: .milliseconds(30), makeRecorder: { recorder }, savedAudio: audio)
        session.applicationIsActive = { true }
        return session
    }

    func testInactiveCancelsQueuedManualAndSelectionBeforeAnyProviderRequest() async throws {
        for selection in [false, true] {
            let provider = ContinuityProvider()
            let active = session(ContinuityRecorder(), provider: provider)
            active.newConversation() // Each case starts clean despite the shared temporary archive.
            var isActive = true
            active.applicationIsActive = { isActive }
            active.autoQuick = false
            active.notes = "Private meeting notes for a manual summary."
            active.segments = [TranscriptSegment(source: .you, text: "Ship Friday after QA signs off.",
                                                 isFinal: true, start: 0, end: 3)]
            let task: Task<Void, Never>?
            if selection {
                let request = MobileSelectionRequest(lines: active.segments)
                active.prepareSelectionSummary(request)
                active.startSelectionSummary(request)
                task = active.selectionRun.task
            } else {
                active.requestSummary()
                task = nil
            }
            isActive = false
            await active.handleScenePhase(.inactive)
            await task?.value
            try await Task.sleep(for: .milliseconds(40))
            let calls = await provider.count()
            XCTAssertEqual(calls, 0, "Queued \(selection ? "selection" : "manual") must not send after inactive cancellation")
            XCTAssertTrue(active.summary.isEmpty)
            XCTAssertTrue(active.selectionSummaries.isEmpty)
            // A fresh direct request while inactive is equally blocked.
            if selection { await active.summarizeSelection(active.segments) }
            else { await active.summarize() }
            let inactiveCalls = await provider.count()
            XCTAssertEqual(inactiveCalls, 0)
            isActive = true
            await active.handleScenePhase(.active)
            if selection { await active.summarizeSelection(active.segments) }
            else { await active.summarize() }
            let resumedCalls = await provider.count()
            XCTAssertEqual(resumedCalls, 1, "Active requests still use the user's selected provider")
        }
    }

    func testLockBackgroundKeepsTheSameRecordingAndAcceptsSpeechUntilExplicitStop() async throws {
        let recorder = ContinuityRecorder()
        // Construct with the observed recorder, rather than merely assigning the recording state.
        let active = self.session(recorder)
        active.start(); try await wait { active.state == .recording }
        let began = active.recordingStartedAt
        recorder.send("Before locking", start: 0)
        await active.handleScenePhase(.inactive)
        await active.handleScenePhase(.background)
        XCTAssertEqual(active.state, .recording)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertEqual(active.recordingStartedAt, began)
        recorder.send("While locked", start: 2)
        XCTAssertEqual(active.segments.map(\.text), ["Before locking", "While locked"])
        XCTAssertEqual(try active.archive.read().records.first?.segments?.count, 2)
        await active.handleScenePhase(.active)
        XCTAssertEqual(recorder.starts, 1, "Foreground return must not open a second microphone run")
        await active.stop()
        XCTAssertEqual(active.state, .idle); XCTAssertEqual(recorder.stops, 1)
        await active.handleScenePhase(.background)
        await active.handleScenePhase(.active)
        XCTAssertEqual(recorder.starts, 1, "Stop is terminal across later scene events")
    }

    func testBackgroundCannotStartAnIdleRecorderAndWatchStopStillStopsTheExistingRun() async throws {
        let recorder = ContinuityRecorder()
        let recording = session(recorder)
        await recording.handleScenePhase(.background)
        recording.start()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(recorder.starts, 0)
        await recording.handleScenePhase(.active)
        recording.start(); try await wait { recording.state == .recording }
        await recording.handleScenePhase(.background)
        let before = recording.phoneRecorderStatus
        XCTAssertEqual(before.state, .recording)
        XCTAssertNotNil(before.startedAt)
        _ = await recording.handleWatchCommand(.stop)
        try await wait { recording.state == .idle }
        XCTAssertEqual(recorder.stops, 1)
        await recording.handleInterruption(.ended, options: .shouldResume)
        XCTAssertEqual(recorder.starts, 1)
    }

    func testBackgroundCancelsPendingStartAndLatePreparationCannotOpenTheMicrophone() async throws {
        let recorder = ContinuityRecorder(); recorder.holdStart = true
        let active = session(recorder)
        active.start(); try await wait { recorder.pendingStart != nil }
        let background = Task { await active.handleScenePhase(.background) }
        try await Task.sleep(for: .milliseconds(20))
        recorder.pendingStart?.resume(); recorder.pendingStart = nil
        await background.value
        XCTAssertEqual(active.state, .idle)
        XCTAssertEqual(recorder.stops, 1)
        XCTAssertTrue(recorder.cancelledBeforeAcquisition)
        XCTAssertEqual(recorder.acquisitions, 0, "Cancelled preparation cannot cross the capture-acquisition boundary")
        XCTAssertNil(active.recordingStartFailure)
        await active.handleScenePhase(.active)
        XCTAssertEqual(active.state, .idle)
    }

    func testLockedSpeechDoesNotStartAutomaticProviderRequestsAndForegroundCatchesUp() async throws {
        let recorder = ContinuityRecorder(), provider = ContinuityProvider()
        let active = session(recorder, provider: provider)
        active.autoQuick = true
        active.start(); try await wait { active.state == .recording }
        await active.handleScenePhase(.background)
        recorder.send("The budget is one hundred twenty dollars", start: 0)
        await active.updateQuickAutomatically()
        try await Task.sleep(for: .milliseconds(120))
        let backgroundCalls = await provider.count()
        XCTAssertEqual(backgroundCalls, 0)
        XCTAssertEqual(active.state, .recording)
        await active.handleScenePhase(.active)
        await active.updateQuickAutomatically()
        for _ in 0..<100 where await provider.count() == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let foregroundCalls = await provider.count()
        XCTAssertGreaterThan(foregroundCalls, 0)
        await active.stop()
    }

    func testSavedAudioOptInContinuesAcrossLockAndOffNeverCreatesAWriter() async throws {
        for enabled in [false, true] {
            let factory = FakeWriterFactory()
            let suiteName = "continuity-audio-\(UUID().uuidString)"
            let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { preferences.removePersistentDomain(forName: suiteName) }
            let audio = MobileSavedAudio(root: root.appendingPathComponent(UUID().uuidString),
                                        defaults: preferences, makeWriter: factory.factory)
            audio.enabled = enabled
            let recorder = ContinuityRecorder(), active = session(recorder, audio: audio)
            active.start(); try await wait { active.state == .recording }
            recorder.send("Before lock", start: 0); recorder.audio()
            await active.handleScenePhase(.background)
            recorder.send("After lock", start: 1); recorder.audio()
            XCTAssertEqual(active.state, .recording)
            XCTAssertEqual(factory.writers.count, enabled ? 1 : 0)
            if enabled {
                XCTAssertFalse(try XCTUnwrap(factory.writers.first).finished)
                XCTAssertEqual(factory.writers.first?.appendCount, 2)
            }
            await active.stop()
            if enabled { XCTAssertTrue(try XCTUnwrap(factory.writers.first).finished) }
        }
    }

    func testNativeSinkBoundsRetainedSpeakerAudioWithoutPeriodicModelPasses() async {
        let speakers = SpeakerAudioBuffer()
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                  channels: 1, interleaved: true)!
        let sink = AnalyzerSink(input: input, destination: format, speakerAudio: speakers,
                                speakerGeneration: speakers.currentGeneration(), languageAudio: nil, languageGeneration: 0)
        let chunk = AudioChunk(samples: [Float](repeating: 0.1, count: 16_000), sampleRate: 16_000,
                               source: .you, timestamp: 0)
        for _ in 0..<630 { XCTAssertEqual(sink.deliver(chunk), .accepted) }
        XCTAssertEqual(speakers.sampleCount, 630 * 16_000)
        XCTAssertLessThanOrEqual(speakers.retainedSampleCount, 610 * 16_000,
                                 "Bound the trailing window plus one storage block while labeling is paused")
        input.finish()
        var delivered = 0
        for await _ in stream { delivered += 1 }
        XCTAssertEqual(delivered, 630, "Memory bounding must not discard transcription audio")
    }

    func testInstalledAppDeclaresAudioBackgroundMode() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.tomwu.ListenToMe.ios")
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("audio"))
    }

    func testInactiveSceneBlocksNewQuickAndCorrectionRequestsWithoutStoppingCapture() async throws {
        let provider = ContinuityProvider(), recorder = ContinuityRecorder()
        let active = MobileSession(storageDirectory: root, summaryProvider: provider, autoInterval: .milliseconds(20),
                                   correctionProvider: provider, makeRecorder: { recorder })
        var foreground = true
        active.applicationIsActive = { foreground }
        active.autoQuick = true; active.ai.correctTranscript = true
        active.start(); try await wait { active.state == .recording }
        foreground = false
        await active.handleScenePhase(.inactive)
        recorder.send("No provider should receive this locked speech", start: 0)
        await active.updateQuickAutomatically()
        try await Task.sleep(for: .milliseconds(150))
        let calls = await provider.count()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(active.state, .recording)
        await active.stop()
    }

    func testInactiveCancelsHeldQuickAndCorrectionAndRejectsTheirLateResults() async throws {
        for correction in [false, true] {
            let provider = ContinuityHeldProvider(reply: correction
                ? "{\"text\":\"We need a name tomorrow.\"}"
                : "{\"reviews\":[],\"action\":\"publish\",\"context\":\"Name\",\"bullets\":[\"Obsolete response\"]}")
            let recorder = ContinuityRecorder()
            let active = MobileSession(storageDirectory: root.appendingPathComponent(UUID().uuidString),
                                       summaryProvider: provider, autoInterval: .milliseconds(20),
                                       correctionProvider: provider, makeRecorder: { recorder })
            var foreground = true
            active.applicationIsActive = { foreground }
            active.autoQuick = !correction; active.ai.correctTranscript = correction
            active.start(); try await wait { active.state == .recording }
            recorder.send("We need a naem tomorrow.", start: 0)
            for _ in 0..<400 where !(await provider.pending()) { try await Task.sleep(for: .milliseconds(5)) }
            let pending = await provider.pending(); XCTAssertTrue(pending)
            foreground = false
            await active.handleScenePhase(.inactive)
            for _ in 0..<100 where !(await provider.cancelled()) { try await Task.sleep(for: .milliseconds(5)) }
            let cancelled = await provider.cancelled(); XCTAssertTrue(cancelled)
            await provider.release()
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(active.state, .recording)
            XCTAssertEqual(active.segments.last?.text, "We need a naem tomorrow.")
            XCTAssertTrue(active.quickSummary.isEmpty)
            XCTAssertNil(active.segments.last?.originalText)
            await active.stop()
        }
    }
}

@MainActor
final class MobileBackgroundSpeakerTests: MobileSpeakerTestCase {
    func testInactiveFencesHeldSpeakerPassWithoutEndingRecordingAndForegroundResumes() async throws {
        let active = makeSession()
        active.applicationIsActive = { true }
        try await recordPastTheFirstPass(active)
        let run = active.speakers.runToken
        await diarizer.holdNext()
        let held = Task { await active.runSpeakerPass() }
        try await waitUntilHolding()
        await active.handleScenePhase(.inactive)
        await diarizer.release(); _ = await held.value
        XCTAssertEqual(active.state, .recording)
        XCTAssertEqual(active.speakers.runToken, run)
        XCTAssertTrue(active.speakers.isRunning)
        XCTAssertEqual(active.segments.last?.speakerName, "Microphone", "A pre-pause result cannot publish after suspension")
        await active.handleScenePhase(.active)
        await active.runSpeakerPass()
        XCTAssertEqual(active.segments.last?.speakerName, "Speaker 1")
        await active.stop(); await active.speakerFinalPass?.value
    }

    func testInactivePreparationCannotMarkModelsReadyAndForegroundCanRetry() async throws {
        let active = makeSession()
        active.applicationIsActive = { true }
        active.speakers.enabled = true
        await diarizer.holdNextPrepare()
        try await recordTwoVoices(active)
        try await waitUntilHoldingPrepare()
        let preparation = try XCTUnwrap(active.speakers.preparation)
        await active.handleScenePhase(.inactive)
        await diarizer.releasePrepare(); await preparation.value
        XCTAssertFalse(active.speakers.modelsReady)
        XCTAssertEqual(active.state, .recording)
        await active.handleScenePhase(.active)
        await active.speakers.preparation?.value
        XCTAssertTrue(active.speakers.modelsReady)
        await active.stop(); await active.speakerFinalPass?.value
    }
}

@MainActor
private final class ContinuityRecorder: MobileRecording {
    var starts = 0, stops = 0
    var acquisitions = 0, cancelledBeforeAcquisition = false
    var holdStart = false
    var pendingStart: CheckedContinuation<Void, Never>?
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    private var writer: (any SavedAudioWriting)?
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        starts += 1; receive = onSegment
        if holdStart { await withCheckedContinuation { pendingStart = $0 } }
        cancelledBeforeAcquisition = Task.isCancelled
        if !Task.isCancelled { acquisitions += 1 }
    }
    func send(_ text: String, start: Double) {
        receive?(TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: start + 1))
    }
    func attachSavedAudio(_ writer: (any SavedAudioWriting)?) { self.writer = writer }
    func audio() { writer?.append(samples: [Float](repeating: 0.1, count: 16_000), sampleRate: 16_000, timestamp: nil) }
    func stop() async throws { stops += 1; receive = nil; await writer?.finish() }
    func reconfigure() async throws {}
}

private actor ContinuityProvider: LLMProvider {
    nonisolated let id = "continuity-no-network"
    private var calls = 0
    func count() -> Int { calls }
    private func respond(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        calls += 1
        continuation.yield("{\"reviews\":[],\"action\":\"publish\",\"context\":\"Budget\",\"bullets\":[\"Budget confirmed\"]}")
        continuation.finish()
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(continuation) } }
    }
}

private actor ContinuityHeldProvider: LLMProvider {
    nonisolated let id = "held-continuity-no-network"
    private let reply: String
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var wasCancelled = false
    init(reply: String) { self.reply = reply }
    func pending() -> Bool { continuation != nil }
    func cancelled() -> Bool { wasCancelled }
    private func terminated() { wasCancelled = true }
    private func hold(_ value: AsyncThrowingStream<String, Error>.Continuation) {
        continuation = value
        value.onTermination = { reason in
            if case .cancelled = reason { Task { await self.terminated() } }
        }
    }
    func release() { continuation?.yield(reply); continuation?.finish(); continuation = nil }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await hold(continuation) } }
    }
}
