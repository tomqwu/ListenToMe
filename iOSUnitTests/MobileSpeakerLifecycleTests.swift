import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Shared setup for the speaker-identification tests (issue #180): a fake recorder that also feeds
/// the speaker buffer, and a fake diarizer, because the simulator cannot run the speaker models.
@MainActor
class MobileSpeakerTestCase: XCTestCase {
    var root: URL!
    var recorder: SpeakerTestRecorder!
    var diarizer: FakeDiarizer!
    /// The stored setting, or `nil` when the user never touched it (which now means on).
    var savedEnabled: Any?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        recorder = SpeakerTestRecorder()
        diarizer = FakeDiarizer()
        savedEnabled = UserDefaults.standard.object(forKey: MobileSpeakers.enabledKey)
    }

    override func tearDown() async throws {
        if let savedEnabled {
            UserDefaults.standard.set(savedEnabled, forKey: MobileSpeakers.enabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: MobileSpeakers.enabledKey)
        }
        try? FileManager.default.removeItem(at: root)
        recorder = nil; diarizer = nil
    }

    func makeSession(provider: (any LLMProvider)? = nil) -> MobileSession {
        let recorder = recorder!, diarizer = diarizer!
        return MobileSession(storageDirectory: root, summaryProvider: provider, autoInterval: .milliseconds(80),
                             makeRecorder: { recorder }, makeDiarizer: { diarizer })
    }

    func record(_ session: MobileSession) async throws {
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
    }

    /// Two voices: 0–4 s and 4–8 s of a 10 s recording.
    func recordTwoVoices(_ session: MobileSession) async throws {
        try await record(session)
        recorder.feedAudio(seconds: 10)
        recorder.send("Shall we start?", 0, 4)
        recorder.send("Yes, the budget first.", 4, 8)
        recorder.send("Mm.", 9.2, 9.6)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 4),
                                DiarizedSegment(speakerId: "y", start: 4, duration: 4)])
    }

    /// A first pass has loaded the models; then one more line arrives before Stop.
    func recordPastTheFirstPass(_ session: MobileSession) async throws {
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        recorder.feedAudio(seconds: 4)
        recorder.send("One last thing.", 10, 13)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 4),
                                DiarizedSegment(speakerId: "y", start: 4, duration: 4),
                                DiarizedSegment(speakerId: "x", start: 10, duration: 3)])
    }

    func waitUntilHoldingPrepare() async throws {
        for _ in 0..<300 where !(await diarizer.holdingPrepare()) { try await Task.sleep(for: .milliseconds(10)) }
        let holding = await diarizer.holdingPrepare()
        XCTAssertTrue(holding)
    }

    func waitUntilHolding() async throws {
        for _ in 0..<300 where !(await diarizer.holding()) { try await Task.sleep(for: .milliseconds(10)) }
        let holding = await diarizer.holding()
        XCTAssertTrue(holding)
    }
}

/// Stop, backgrounding and memory: identification must never hold the session or grow without bound.
@MainActor
final class MobileSpeakerLifecycleTests: MobileSpeakerTestCase {
    func testStopRunsAFinalPassSoTheLastWordsAreLabeled() async throws {
        let session = makeSession()
        try await recordPastTheFirstPass(session)
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.map(\.speakerName), ["Speaker 1", "Speaker 2", "Microphone", "Speaker 1"])
        let calls = await diarizer.calls()
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(session.speakers.isRunning)
    }

    func testStopNeverStartsTheFirstModelDownload() async throws {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await diarizer.holdNextPrepare()
        try await recordTwoVoices(session)   // Start begins preparing; the download is still running
        try await waitUntilHoldingPrepare()
        await session.stop()
        XCTAssertNil(session.speakerFinalPass, "Models not ready at Stop: no final pass")
        XCTAssertFalse(session.speakers.isRunning)
        await diarizer.releasePrepare()
        await session.speakers.preparation?.value
        let calls = await diarizer.calls(), prepares = await diarizer.prepares()
        XCTAssertEqual(calls, 0, "Nothing is analyzed after Stop")
        XCTAssertEqual(prepares, 1, "Only Start prepared the models; Stop did not")
        XCTAssertEqual(Set(session.segments.compactMap(\.speakerName)), ["Microphone"])
    }

    func testStopAfterAFailedDownloadDoesNotTryAgain() async throws {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await diarizer.failModels("offline")
        try await recordTwoVoices(session)
        await session.speakers.preparation?.value
        XCTAssertTrue(session.speakers.isUnavailable)
        XCTAssertEqual(session.state, .recording, "A failed download never stops the recording")
        await session.stop()
        XCTAssertNil(session.speakerFinalPass)
        let calls = await diarizer.calls(), prepares = await diarizer.prepares()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(prepares, 1)
    }

    func testStopReturnsToIdleWhileAPassIsStillRunning() async throws {
        let session = makeSession()
        try await recordPastTheFirstPass(session)
        await diarizer.holdNext()
        let periodic = Task { await session.periodicSpeakerPass() }
        try await waitUntilHolding()
        await session.stop()
        XCTAssertEqual(session.state, .idle, "Stop does not wait for the diarizer")
        XCTAssertFalse(session.busy)
        await diarizer.release()
        _ = await periodic.value
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.last?.speakerName, "Speaker 1", "The pass in flight still lands")
        let calls = await diarizer.calls()
        XCTAssertEqual(calls, 2, "The final pass queued behind it found nothing new")
    }

    func testALateResultForAnEndedRunIsDiscarded() async throws {
        let session = makeSession()
        try await recordPastTheFirstPass(session)
        await diarizer.holdNext()
        let periodic = Task { await session.periodicSpeakerPass() }
        try await waitUntilHolding()
        await session.stop()
        try await record(session)   // a new recording begins a new run
        await diarizer.release()
        _ = await periodic.value
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.last?.speakerName, "Microphone")
        let calls = await diarizer.calls()
        XCTAssertEqual(calls, 2, "The old run's final pass does not analyze the new run")
        XCTAssertTrue(session.speakers.isRunning)
        await session.stop()
    }

    func testBackgroundingWithAPassInFlightDoesNotWait() async throws {
        let session = makeSession()
        try await recordPastTheFirstPass(session)
        await diarizer.holdNext()
        let periodic = Task { await session.periodicSpeakerPass() }
        try await waitUntilHolding()
        await session.handleScenePhase(.background)
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.speakers.isRunning, "The run ends at once; its audio is released")
        await diarizer.release()
        _ = await periodic.value
        XCTAssertEqual(session.segments.last?.speakerName, "Microphone")
    }

    func testBackgroundingSkipsTheFinalPass() async throws {
        let session = makeSession()
        try await recordPastTheFirstPass(session)
        await session.handleScenePhase(.background)
        XCTAssertNil(session.speakerFinalPass)
        let calls = await diarizer.calls()
        XCTAssertEqual(calls, 1, "Speaker models do not run while the app is in the background")
        XCTAssertEqual(session.segments.last?.speakerName, "Microphone")
    }

    func testAResumedRecordingNumbersNewVoicesAfterTheEarlierOnes() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        await session.stop()
        try await record(session)
        recorder.feedAudio(seconds: 5)
        recorder.send("Sorry I'm late.", 0, 4)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 4)])
        await session.stop()
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.last?.speakerName, "Speaker 3")
        XCTAssertEqual(session.segments.last?.start ?? 0, 9.6, accuracy: 0.001,
                       "Times continue after the first recording")
    }

    // MARK: Bounded memory

    func testPeriodicTicksReleaseAudioAlreadyAnalyzed() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await record(session)
        let audio = try XCTUnwrap(recorder.speakerAudio)
        recorder.feedAudio(seconds: 200)
        recorder.send("A long talk.", 0, 200)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 200)])
        _ = await session.periodicSpeakerPass()
        _ = await session.periodicSpeakerPass()
        XCTAssertLessThanOrEqual(audio.retainedSampleCount, 70 * 16_000, "Only the overlap is kept")
        await session.stop()
    }

    func testRepeatedlyFailingPassesStillCapRetainedAudio() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await record(session)
        let audio = try XCTUnwrap(recorder.speakerAudio)
        recorder.feedAudio(seconds: 700)
        await diarizer.failAlways()
        _ = await session.periodicSpeakerPass()
        _ = await session.periodicSpeakerPass()
        XCTAssertFalse(session.speakers.isUnavailable, "Not a model failure, so no latch")
        XCTAssertLessThanOrEqual(audio.retainedSampleCount,
                                 Int(SpeakerAnalysisPolicy.maximumWindow) * 16_000 + SpeakerAudioBuffer.blockSize,
                                 "At most the longest window is held while nothing is analyzed")
        await session.stop()
    }
}
