import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #195: the speaker models are prepared before the first recording needs them — when the user
/// turns Identify speakers on, at a foreground launch with the setting on, and at Start — so a short
/// first recording is labeled at Stop, and the recording screen always says what the labels are doing.
@MainActor
final class MobileSpeakerPreparationTests: MobileSpeakerTestCase {
    // MARK: Default

    func testIdentifySpeakersIsOnUnlessTheUserTurnedItOff() {
        UserDefaults.standard.removeObject(forKey: MobileSpeakers.enabledKey)
        XCTAssertTrue(makeSession().speakers.enabled, "Never touched: on")
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        XCTAssertFalse(makeSession().speakers.enabled, "Turned off: stays off")
        UserDefaults.standard.set("NO", forKey: MobileSpeakers.enabledKey)
        XCTAssertFalse(makeSession().speakers.enabled, "A launch-argument NO is off too")
    }

    // MARK: When the models are prepared

    func testTurningTheSettingOnPreparesTheModelsWithoutRecording() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        session.speakers.enabled = true
        await session.speakers.preparation?.value
        let prepares = await diarizer.prepares(), calls = await diarizer.calls()
        XCTAssertEqual(prepares, 1)
        XCTAssertEqual(calls, 0, "Preparing analyzes no audio")
        XCTAssertTrue(session.speakers.modelsReady)
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(recorder.speakerAudio, "Nothing was recorded")
    }

    func testAForegroundLaunchWithTheSettingOnPreparesTheModels() async throws {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        var prepares = await diarizer.prepares()
        XCTAssertEqual(prepares, 0, "Creating the session (possibly in the background) downloads nothing")
        await session.handleScenePhase(.active)
        await session.speakers.preparation?.value
        prepares = await diarizer.prepares()
        XCTAssertEqual(prepares, 1)
        XCTAssertTrue(session.speakers.modelsReady)

        await session.handleScenePhase(.active)
        await session.speakers.preparation?.value
        prepares = await diarizer.prepares()
        XCTAssertEqual(prepares, 1, "Ready models are not prepared again")
    }

    func testTheBackgroundNeverPreparesTheModels() async throws {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await session.handleScenePhase(.background)
        session.prepareSpeakerModelsIfNeeded()
        await session.speakers.preparation?.value
        let prepares = await diarizer.prepares()
        XCTAssertEqual(prepares, 0)
        XCTAssertFalse(session.speakers.modelsReady)
    }

    func testTheSettingOffPreparesNothing() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await session.handleScenePhase(.active)
        try await record(session)
        await session.stop()
        let prepares = await diarizer.prepares()
        XCTAssertEqual(prepares, 0)
    }

    func testAShortRecordingWithTheModelsReadyIsLabeledAtStop() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        session.speakers.enabled = true
        await session.speakers.preparation?.value
        try await recordTwoVoices(session)   // 10 s: shorter than the first periodic pass
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.map(\.speakerName), ["Speaker 1", "Speaker 2", "Microphone"])
        let calls = await diarizer.calls()
        XCTAssertEqual(calls, 1, "One pass, at Stop")
    }

    func testRecordingNeverWaitsForTheModels() async throws {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await diarizer.holdNextPrepare()
        try await record(session)
        XCTAssertEqual(session.state, .recording, "Start does not wait for the download")
        try await waitUntilHoldingPrepare()
        await diarizer.releasePrepare()
        await session.speakers.preparation?.value
        XCTAssertTrue(session.speakers.modelsReady)
        await session.stop()
    }

    func testRetryAfterAFailedDownloadPreparesAgain() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        await diarizer.failModels("The Internet connection appears to be offline.")
        session.speakers.enabled = true
        await session.speakers.preparation?.value
        XCTAssertTrue(session.speakers.isUnavailable)
        XCTAssertTrue(session.speakers.showsRetry)
        await diarizer.recover()
        session.retrySpeakerIdentification()
        try await waitFor { session.speakers.modelsReady }
        let prepares = await diarizer.prepares(), retries = await diarizer.retries()
        XCTAssertEqual(prepares, 2)
        XCTAssertEqual(retries, 1)
        XCTAssertFalse(session.speakers.isUnavailable)
    }

    // MARK: Status line on the recording screen

    func testStatusLineForEachState() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        let speakers = session.speakers
        XCTAssertNil(speakers.statusLine, "Off: nothing to say")

        await diarizer.holdNextPrepare()
        speakers.enabled = true
        try await waitUntilHoldingPrepare()
        XCTAssertEqual(speakers.statusLine, "Speaker labels: preparing models…")
        XCTAssertFalse(speakers.showsRetry)
        await diarizer.releasePrepare()
        await speakers.preparation?.value
        XCTAssertEqual(speakers.statusLine, "Speaker labels ready")

        try await recordTwoVoices(session)
        XCTAssertEqual(speakers.statusLine, "Speaker labels appear about 20 s in and at Stop")
        await diarizer.holdNext()
        let pass = Task { await session.runSpeakerPass() }
        try await waitUntilHolding()
        XCTAssertEqual(speakers.statusLine, "Speaker labels: identifying speakers…")
        await diarizer.release()
        _ = await pass.value

        await diarizer.failModels("The Internet connection appears to be offline.")
        recorder.feedAudio(seconds: 5)
        await session.runSpeakerPass()
        XCTAssertEqual(speakers.statusLine, "Speaker labels unavailable: The Internet connection appears to be offline")
        XCTAssertTrue(speakers.showsRetry)
        await session.stop()
    }

    func testStatusLineBeforeTheModelsHaveLoaded() {
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        XCTAssertEqual(session.speakers.statusLine, "Speaker labels: models not loaded")
        XCTAssertTrue(session.speakers.showsRetry)
    }

    func testAnotherPassErrorIsReported() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await diarizer.failOnce()
        await session.runSpeakerPass()
        let reason = SpeakerDiarizer.DiarizationError.notEnoughAudio.localizedDescription
        XCTAssertEqual(session.speakers.statusLine, "Speaker labels: a pass was skipped (\(reason))")
        await session.stop()
    }

    // MARK: Status details

    func testStatusDetailsDescribeSpeakerIdentification() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        XCTAssertTrue(session.quickDiagnostics.contains("Identify speakers: off"), session.quickDiagnostics)
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker models ready: no"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker passes run: 0"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker last error: none"))

        await diarizer.failModels("offline")
        session.speakers.enabled = true
        await session.speakers.preparation?.value
        XCTAssertTrue(session.quickDiagnostics.contains("Identify speakers: on"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker models ready: no (failed)"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker last error: offline"))

        await diarizer.recover()
        session.retrySpeakerIdentification()
        try await waitFor { session.speakers.modelsReady }
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker models ready: yes"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker passes run: 1"))
        XCTAssertTrue(session.quickDiagnostics.contains("Speaker last error: offline"), "Kept for diagnosis")
        await session.stop()
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}
