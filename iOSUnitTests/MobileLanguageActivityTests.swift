import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileLanguageActivityTests: MobileLanguageTestCase {
    override func makeSession(withModel: Bool = true) -> MobileSession {
        let session = super.makeSession(withModel: withModel)
        session.applicationIsActive = { true }
        return session
    }

    private func waitForDetections(_ count: Int) async throws {
        for _ in 0..<400 {
            if await model.detections() >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Audio activity did not trigger the expected language check")
    }

    func testRealPeriodicLoopChecksAudioWithNoRecognizerResults() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        session.startLanguageActivityLoop(interval: .milliseconds(10))
        recorder.feedAudio(seconds: 12, marker: 0.1)
        try await waitForDetections(1)
        await settle(session)
        recorder.feedAudio(seconds: 60, marker: 0.1)
        try await waitForDetections(2)
        await settle(session)
        XCTAssertEqual(session.speechEventCount, 0)
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertEqual(session.languageDetection.run?.tracker.lastCheck, 72)
        await session.stop()
        XCTAssertNil(session.languageDetection.activityLoop)
    }

    func testSilenceNeverDownloadsAndScansOnlyNewCompleteFrames() async throws {
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 180)
        await session.checkLanguageAudioActivity()
        let through = session.languageDetection.run?.activityThrough
        XCTAssertEqual(through, 180 * 16_000)
        await session.checkLanguageAudioActivity()
        XCTAssertEqual(session.languageDetection.run?.activityThrough, through)
        XCTAssertNil(session.languageDetection.run?.tracker.speechStart)
        let prepares = await model.prepares()
        XCTAssertEqual(prepares, 0)
        await session.stop()
    }

    func testBriefSoundDoesNotDownloadAndSpeechAfterLongSilenceUsesRecentAudio() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 1, marker: 0.1)
        await session.checkLanguageAudioActivity()
        var prepares = await model.prepares()
        XCTAssertEqual(prepares, 0)
        recorder.feedAudio(seconds: 179)
        await session.checkLanguageAudioActivity()
        prepares = await model.prepares()
        XCTAssertEqual(prepares, 0)
        recorder.feedAudio(seconds: 12, marker: 0.1)
        await session.checkLanguageAudioActivity(); await settle(session)
        let detections = await model.detections()
        XCTAssertEqual(detections, 1)
        XCTAssertEqual(session.languageDetection.run?.tracker.lastCheck, 192)
        await session.stop()
    }

    func testFirstRecognizedSpeechStillPreparesAfterAnEarlierBriefSound() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 1, marker: 0.1)
        await session.checkLanguageAudioActivity()
        recorder.feedAudio(seconds: 179)
        recorder.send("First real words", 180, 182)
        for _ in 0..<200 {
            if await model.prepares() > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let prepares = await model.prepares()
        XCTAssertGreaterThan(prepares, 0)
        XCTAssertNil(session.languageDetection.check)
        recorder.feedAudio(seconds: 12, marker: 0.1)
        recorder.send("More speech", 182, 190)
        await settle(session)
        let detections = await model.detections()
        XCTAssertEqual(detections, 1)
        await session.stop()
    }

    func testLowPowerAndSilenceStillPauseAudioDrivenRechecks() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12, marker: 0.1)
        await session.checkLanguageAudioActivity(); await settle(session)
        conditions.lowPower = true
        recorder.feedAudio(seconds: 60, marker: 0.1)
        await session.checkLanguageAudioActivity(); await settle(session)
        var detections = await model.detections()
        XCTAssertEqual(detections, 1)
        conditions.lowPower = false
        recorder.feedAudio(seconds: 60)
        await session.checkLanguageAudioActivity(); await settle(session)
        detections = await model.detections()
        XCTAssertEqual(detections, 1)
        recorder.feedAudio(seconds: 12, marker: 0.1)
        await session.checkLanguageAudioActivity(); await settle(session)
        detections = await model.detections()
        XCTAssertEqual(detections, 2)
        await session.stop()
    }

    func testStopDoesNotWaitForAudioTriggeredModelAndOldRunCannotReturn() async throws {
        await model.hold()
        let session = makeSession()
        try await record(session)
        let oldToken = try XCTUnwrap(session.languageDetection.run?.token)
        recorder.feedAudio(seconds: 12, marker: 0.1)
        await session.checkLanguageAudioActivity()
        for _ in 0..<200 {
            if await model.prepares() > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let check = session.languageDetection.check
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.languageDetection.activityLoop)
        XCTAssertNil(session.languageDetection.noteAudioActivity([0..<60], through: 960_000, token: oldToken))
        await model.release()
        await check?.value
        let detections = await model.detections()
        XCTAssertEqual(detections, 0)
        XCTAssertTrue(recorder.switches.isEmpty)
    }
}
