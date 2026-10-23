import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #197 and the review of #201: replaying a switched recording, resuming it, and Undo. Every
/// replacement happens in one step, after its new lines exist, and Undo never loses or duplicates a line.
@MainActor
final class MobileLanguageUndoTests: MobileLanguageTestCase {
    /// Review of #201, finding 4: the earlier lines are never removed, on screen or on disk, before
    /// their replacements exist.
    func testTheEarlyTranscriptIsKeptOnDiskUntilTheReplayReplacesIt() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        XCTAssertEqual(makeSession().segments.map(\.text), ["Wo men jin tian", "kai hui tao lun"],
                       "Killed mid-replay, the app relaunches with the earlier lines")
        recorder.send("开会", 13, 15)
        XCTAssertEqual(makeSession().segments.map(\.text), ["我们今天", "开会"])
        await session.stop()
    }

    func testAReplayCutShortByStopKeepsTheLinesItNeverReached() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        await session.stop()
        XCTAssertEqual(session.segments.map(\.text), ["我们今天", "kai hui tao lun"],
                       "Lines the replay did not reach stay rather than vanish")
    }

    /// Review of #201, finding 3: without the audio to replay, the switch says it applies to new speech
    /// only, replaces nothing, and Undo has nothing to restore.
    func testASwitchWithoutReplayIsHonestAboutWhatChanged() async throws {
        await model.answer("zh", 0.97)
        recorder.replayAvailable = false
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        XCTAssertEqual(recorder.switches.map(\.replayed), [false])
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) · switched for new speech")
        recorder.send("后来的话", 13, 15)
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "kai hui tao lun", "后来的话"])
        await session.stop()
        session.undoLanguageSwitch()
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "kai hui tao lun", "后来的话"])
        XCTAssertFalse(session.languageDetection.automatic, "Undo still pins the original language")
    }

    /// Review of #201, finding 7: a call, then the automatic resume, keeps the switched language.
    func testResumingAfterAnInterruptionKeepsTheSwitchedLanguageAndItsUndo() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们", 13, 15)
        await session.handleInterruption(.began)
        XCTAssertEqual(session.state, .idle)
        await session.handleInterruption(.ended, options: .shouldResume)
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.startLocale, Locale(identifier: "zh-CN"))
        XCTAssertNotNil(session.languageDetection.notice, "Undo is still offered")
        recorder.feedAudio(seconds: 12)
        recorder.send("继续", 1, 10)
        let detections = await model.detections()
        XCTAssertEqual(detections, 1, "The resumed recording is not checked again")
        XCTAssertNil(session.languageDetection.check)
        await session.stop()
    }

    func testUndoWhileRecordingSwitchesBackAndPinsTheOriginalLanguage() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们", 1, 4)
        recorder.send("开会", 13, 15)
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN", Locale.current.identifier])
        XCTAssertEqual(recorder.switches.last?.replayed, true, "The audio is still held, so it is heard again")
        XCTAssertEqual(session.segments.map(\.text), ["我们", "开会"], "Kept until the replay catches up")
        recorder.send("wo men", 1, 4)
        recorder.send("now in English", 16, 17)
        XCTAssertEqual(session.segments.map(\.text), ["wo men", "now in English"])
        XCTAssertNil(session.languageDetection.notice)
        XCTAssertFalse(session.languageDetection.automatic, "Undo pins the language")
        XCTAssertEqual(session.languageChoice, Locale.current.identifier)
        XCTAssertEqual(session.conversationLanguage, Locale.current.identifier)
        await session.stop()
    }

    func testUndoAfterStopRestoresTheOriginalLines() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        recorder.send("later words", 12.5, 14)
        await session.stop()
        session.undoLanguageSwitch()
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "kai hui tao lun", "later words"],
                       "Lines from before the switch come back; lines heard after it stay")
        XCTAssertEqual(recorder.switches.count, 1, "Nothing restarts once the recording has stopped")
        XCTAssertFalse(session.languageDetection.automatic)
        let reopened = makeSession()
        XCTAssertEqual(reopened.segments.map(\.text), session.segments.map(\.text), "The restore is saved")
    }

    /// Review of #201, finding 5: the unfinished line at the switch comes back, and the line spanning the
    /// switch, which alone holds the words after it, stays.
    func testUndoAfterStopKeepsTheSentenceThatSpansTheSwitch() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Wo men jin tian", 1, 4)
        recorder.send("kai hui tao", 4, 9.5, final: false)
        recorder.send("lun xia ge", 9.5, 11, final: false)
        await session.languageDetection.check?.value
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        recorder.send("我们今天", 1, 4)
        recorder.send("开会讨论下个季度", 9.5, 14)
        recorder.send("的计划", 14.5, 16)
        await session.stop()
        session.undoLanguageSwitch()
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "lun xia ge", "开会讨论下个季度", "的计划"])
    }

    /// Review of #201, finding 6.
    func testUndoAfterStopLeavesAppleWatchLinesAlone() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        recorder.send("later words", 12.5, 14)
        await session.stop()
        session.segments.append(TranscriptSegment(source: .you, text: "From the watch", isFinal: true, start: 2,
                                                  end: 5, speakerName: MobileFileTranscriber.speakerName))
        session.undoLanguageSwitch()
        XCTAssertEqual(session.segments.map(\.text),
                       ["Wo men jin tian", "kai hui tao lun", "later words", "From the watch"])
    }

    /// Review of #201, finding 1: an Undo while the recorder is still finalizing waits for Stop, so a
    /// late final line is neither duplicated nor left out of order.
    func testUndoWhileStoppingWaitsForStopToFinish() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        recorder.send("later words", 12.5, 14)
        recorder.holdStop = true
        let stopping = Task { await session.stop() }
        for _ in 0..<200 where !recorder.isHoldingStop { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .stopping)
        session.undoLanguageSwitch()
        XCTAssertNotNil(session.languageDetection.notice, "Nothing changes while the recorder finalizes")
        XCTAssertTrue(session.languageDetection.automatic)
        recorder.send("last words", 14.5, 15)
        recorder.releaseStop()
        await stopping.value
        XCTAssertEqual(session.segments.map(\.text),
                       ["Wo men jin tian", "kai hui tao lun", "later words", "last words"])
        XCTAssertNil(session.languageDetection.notice)
        XCTAssertFalse(session.languageDetection.automatic)
    }

    /// Review of #201, finding 2: a failed switch back keeps the notice, so Undo can be tried again.
    func testAFailedUndoWhileRecordingKeepsTheNotice() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.failSwitch = "Assets unavailable"
        session.undoLanguageSwitch()
        XCTAssertFalse(session.canUndoLanguageSwitch, "One Undo at a time")
        for _ in 0..<200 where session.languageDetection.undoing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(session.languageDetection.notice)
        XCTAssertTrue(session.languageDetection.automatic, "Nothing is pinned until the switch back worked")
        XCTAssertTrue(session.message?.hasSuffix("Tap Undo to try again.") ?? false, session.message ?? "")
        XCTAssertTrue(session.canUndoLanguageSwitch)
        await session.stop()
    }

    /// Review of #201, finding 2: a switch back cancelled by Stop still restores once stopped.
    func testAnUndoCancelledByStopIsAppliedAfterStop() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        recorder.send("later words", 12.5, 14)
        recorder.holdSwitch = true
        session.undoLanguageSwitch()
        for _ in 0..<200 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
        await session.stop()
        recorder.releaseSwitch(failing: CancellationError())
        for _ in 0..<200 where session.languageDetection.notice != nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "kai hui tao lun", "later words"])
        XCTAssertFalse(session.languageDetection.automatic)
    }
}
