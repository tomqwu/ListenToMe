import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileLanguageReplayProgressTests: MobileLanguageTestCase {
    func testCrossingUtteranceShowsLivePartialThenCommitsOneFinalAndRechecks() async throws {
        let session = try await switchToMandarinAtOneMinute()
        let original = session.segments
        let english = original.filter { $0.start < 60 }
        recorder.send("重播的前半句", 60, 140)
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("仍在继续的句子", 140, 154, final: false)
        XCTAssertEqual(session.partial?.text, "仍在继续的句子", "A growing utterance past the replay cut must be visible")
        XCTAssertEqual(session.segments, original, "Keep finalized originals until their replacements are final")
        recorder.send("仍在继续的完整句子", 140, 155)
        XCTAssertNil(session.partial)
        XCTAssertNil(session.languageDetection.replay)
        XCTAssertEqual(session.segments.map(\.text), english.map(\.text) + ["重播的前半句", "仍在继续的完整句子"])
        XCTAssertEqual(session.segments.filter { $0.text == "仍在继续的完整句子" }.count, 1)
        XCTAssertEqual(session.segments.last?.language, "zh-CN")
        recorder.feedAudio(seconds: 60, marker: mandarin)
        recorder.send("后面的发言", 195, 214)
        await settle(session)
        XCTAssertEqual(session.languageDetection.run?.tracker.lastCheck, 215, "Replay must release later language checks")
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.segments.contains { $0.text == "仍在继续的完整句子" })
    }

    func testUndoReplayAlsoPublishesCrossingFinalWithoutDuplicateOrNameChange() async throws {
        let session = try await switchToMandarinAtOneMinute()
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("这句话跨过切换点", 140, 155)
        session.undoLanguageSwitch()
        for _ in 0..<400 where recorder.switches.count < 2 || session.languageDetection.undoing {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(recorder.switches.count, 2)
        recorder.send("The original language continues", 140, 157)
        XCTAssertNil(session.languageDetection.replay)
        XCTAssertEqual(session.segments.filter { $0.text == "The original language continues" }.count, 1)
        XCTAssertEqual(session.segments.last?.speakerName, MobileSession.microphoneLabel)
        XCTAssertFalse(session.languageDetection.automatic)
        await session.stop()
        XCTAssertEqual(session.state, .idle)
    }

    func testInactivePreparationCannotDetectOrSwitchAndForegroundCanRetry() async throws {
        await model.hold()
        await model.answer("zh", 0.99)
        let session = makeSession()
        var active = true
        session.applicationIsActive = { active }
        try await record(session)
        let token = session.languageDetection.run?.token
        recorder.feedAudio(seconds: 12)
        recorder.send("Old words", 1, 5)
        recorder.send("Keep these words", 5, 10)
        for _ in 0..<400 {
            if await model.prepares() > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = session.languageDetection.check
        active = false
        await session.handleScenePhase(.inactive)
        await model.release()
        await pending?.value
        let staleDetections = await model.detections()
        XCTAssertEqual(staleDetections, 0, "No new inference may follow preparation completed while inactive")
        XCTAssertTrue(recorder.switches.isEmpty, "An inactive completion must not replace the live transcriber")
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.languageDetection.run?.token, token, "Suspension must preserve recording and Undo identity")
        active = true
        await session.handleScenePhase(.active)
        recorder.feedAudio(seconds: 12)
        recorder.send("Speech continues", 12, 24)
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"], "Foreground must permit a fresh check")
        await session.stop()
        XCTAssertEqual(session.state, .idle)
    }

    func testLongSuspensionRetainsBoundedAudioAndForegroundChecksRecentSpeech() async throws {
        await model.hold()
        await model.answer("zh", 0.99)
        let session = makeSession()
        var active = true
        session.applicationIsActive = { active }
        try await record(session)
        let token = session.languageDetection.run?.token
        recorder.feedAudio(seconds: 12)
        recorder.send("Original finalized words", 1, 10)
        for _ in 0..<400 {
            if await model.prepares() > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let oldCheck = session.languageDetection.check
        session.pauseLanguageForBackground()
        active = false
        recorder.feedAudio(seconds: 180, marker: mandarin)
        recorder.send("Background captured words", 180, 191)
        await model.release()
        await oldCheck?.value
        let detections = await model.detections()
        XCTAssertEqual(detections, 0)
        XCTAssertTrue(recorder.switches.isEmpty)
        XCTAssertEqual(session.languageDetection.run?.token, token)
        let retained = try XCTUnwrap(session.languageDetection.run?.buffer.retainedSampleCount)
        XCTAssertLessThanOrEqual(retained, 130 * 16_000, "Only the trailing120s plus one storage block is retained")
        XCTAssertTrue(session.segments.contains { $0.text == "Background captured words" })
        active = true
        session.resumeLanguageAfterForeground()
        await session.checkLanguageAudioActivity()
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"], "Retry must use recent retained speech, not an expired opening window")
        await session.stop()
        XCTAssertEqual(session.state, .idle)
    }

    func testSuspendingBeforeQueuedPreparationNeverStartsModelWork() async throws {
        let session = makeSession()
        session.applicationIsActive = { true }
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Speech schedules preparation", 1, 10)
        session.pauseLanguageForBackground()
        for _ in 0..<30 { await Task.yield() }
        let prepares = await model.prepares()
        XCTAssertEqual(prepares, 0, "A cancelled queued preparation must not start a model download or load")
        XCTAssertTrue(recorder.switches.isEmpty)
        await session.stop()
    }

    func testHeldDetectionCannotReplaceFreshForegroundRequest() async throws {
        await model.answer("zh", 0.99)
        await model.holdDetections()
        let session = makeSession()
        session.applicationIsActive = { true }
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Words before suspension", 1, 10)
        for _ in 0..<400 {
            if await model.detections() == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let oldCheck = session.languageDetection.check
        session.pauseLanguageForBackground()
        session.resumeLanguageAfterForeground()
        recorder.feedAudio(seconds: 12)
        recorder.send("Fresh foreground words", 12, 24)
        for _ in 0..<400 {
            if await model.detections() == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await model.releaseDetections()
        await oldCheck?.value
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"], "Only the fresh request may switch")
        XCTAssertEqual(session.languageDetection.run?.tracker.switches, 1)
        await session.stop()
    }

    func testStaleSwitchErrorAfterResumeCannotPublishFailure() async throws {
        await model.answer("zh", 0.99)
        recorder.holdSwitch = true
        let session = makeSession()
        session.applicationIsActive = { true }
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Old words", 1, 10)
        for _ in 0..<400 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingSwitch)
        let oldCheck = session.languageDetection.check
        session.pauseLanguageForBackground()
        session.resumeLanguageAfterForeground()
        recorder.releaseSwitch(failing: RecordingError.message("Old cancelled switch failure"))
        await oldCheck?.value
        XCTAssertNil(session.languageDetection.lastError)
        XCTAssertTrue(recorder.switches.isEmpty)
        XCTAssertEqual(session.state, .recording)
        await session.stop()
    }

    func testNoResultReplayRecoversOnceAfterActivityAndReleasesLaterChecks() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        let original = session.segments
        let saveAudio = session.savedAudio.enabled
        recorder.feedAudio(seconds: 31, marker: mandarin)
        await session.checkLanguageAudioActivity()
        XCTAssertEqual(recorder.replayRecoveries, ["zh-CN"])
        XCTAssertNil(session.languageDetection.replay)
        XCTAssertEqual(session.segments, original, "Uncovered originals must survive recovery")
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.savedAudio.enabled, saveAudio, "Recovery must not enable saved audio")
        XCTAssertTrue(session.languageDetection.noticeText?.contains("may be missing") == true)
        recorder.send("Recovered live words", 181, 185)
        XCTAssertEqual(session.segments.last?.text, "Recovered live words")
        recorder.feedAudio(seconds: 60, marker: mandarin)
        await session.checkLanguageAudioActivity(); await settle(session)
        XCTAssertEqual(session.languageDetection.run?.tracker.lastCheck, 241)
        XCTAssertEqual(recorder.replayRecoveries.count, 1, "No blind recovery loop")
        XCTAssertTrue(session.canUndoLanguageSwitch, "Undo remains available after the restart settles")
        await session.stop()
    }

    func testSilenceCannotTriggerRecoveryAndAdvancingReplayResetsActivityBudget() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        recorder.feedAudio(seconds: 120)
        await session.checkLanguageAudioActivity()
        XCTAssertTrue(recorder.replayRecoveries.isEmpty, "Silence is not a stalled speech result")
        recorder.feedAudio(seconds: 20, marker: mandarin)
        await session.checkLanguageAudioActivity()
        recorder.send("Replay is advancing", 60, 100)
        recorder.feedAudio(seconds: 29, marker: mandarin)
        await session.checkLanguageAudioActivity()
        XCTAssertTrue(recorder.replayRecoveries.isEmpty, "New result progress resets the budget")
        recorder.feedAudio(seconds: 1, marker: mandarin)
        await session.checkLanguageAudioActivity()
        XCTAssertEqual(recorder.replayRecoveries.count, 1)
        await session.stop()
    }

    func testRecoveryFailureKeepsCaptureAndOriginalsAndFutureChecksAreNotGated() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        let original = session.segments
        recorder.failReplayRecovery = "Synthetic restart failure"
        recorder.feedAudio(seconds: 31, marker: mandarin)
        await session.checkLanguageAudioActivity()
        XCTAssertEqual(recorder.replayRecoveries.count, 1)
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.segments, original)
        XCTAssertTrue(session.languageDetection.lastError?.contains("Synthetic restart failure") == true)
        recorder.feedAudio(seconds: 60, marker: mandarin)
        await session.checkLanguageAudioActivity(); await settle(session)
        XCTAssertEqual(session.languageDetection.run?.tracker.lastCheck, 241)
        XCTAssertEqual(recorder.replayRecoveries.count, 1)
        await session.stop()
    }

    func testStopCancelsHeldRecoveryWithoutReplacingTextOrPublishingStatus() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        let original = session.segments
        recorder.holdReplayRecovery = true
        recorder.feedAudio(seconds: 31, marker: mandarin)
        let scan = Task { await session.checkLanguageAudioActivity() }
        for _ in 0..<400 where !recorder.isHoldingReplayRecovery { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingReplayRecovery)
        XCTAssertFalse(session.canUndoLanguageSwitch, "Do not overlap Undo with an in-flight native replacement")
        await session.stop()
        recorder.releaseReplayRecovery()
        await scan.value
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.segments, original)
        XCTAssertEqual(recorder.replayRecoveryCommits, 0)
        XCTAssertNil(session.languageDetection.replayRecoveryMessage)
        XCTAssertNil(session.languageDetection.recovery)
    }

    func testRecoveredResultCancelsHeldRestartBeforeItCanReplaceHealthyAnalyzer() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        recorder.holdReplayRecovery = true
        recorder.feedAudio(seconds: 31, marker: mandarin)
        let scan = Task { await session.checkLanguageAudioActivity() }
        for _ in 0..<400 where !recorder.isHoldingReplayRecovery { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingReplayRecovery)
        recorder.send("The current analyzer recovered", 140, 185)
        recorder.releaseReplayRecovery()
        await scan.value
        XCTAssertNil(session.languageDetection.replay)
        XCTAssertEqual(session.segments.last?.text, "The current analyzer recovered")
        XCTAssertEqual(recorder.replayRecoveryCommits, 0, "A healthy analyzer must not be replaced by stale recovery")
        XCTAssertNil(session.languageDetection.replayRecoveryMessage)
        await session.stop()
    }

    func testNoReplacementResultsKeepOriginalsAndStopRemainsAvailable() async throws {
        let session = try await switchToMandarinAtOneMinute()
        let original = session.segments
        recorder.feedAudio(seconds: 60, marker: mandarin)
        XCTAssertEqual(session.segments, original)
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.segments, original, "A silent replacement must never erase captured text")
    }
}
