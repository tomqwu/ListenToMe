import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Review of #212: Undo while a re-check switches, a replay whose start was released during a slow
/// download, an honest notice, Apple Watch lines during a replay, and Undo in a resumed recording.
@MainActor
final class MobileLanguageSwitchReviewTests: MobileLanguageTestCase {
    /// Finding 1: while a re-check replaces the transcriber, Undo of the earlier switch is not offered
    /// (it would fail and then be lost to the new notice). Once the switch settles, Undo is for it.
    func testUndoWaitsWhileARecheckSwitches() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12, marker: mandarin)
        recorder.send("wo men", 1, 5)
        recorder.send("kai hui", 5, 9.5)
        await settle(session)
        recorder.send("我们开会", 1, 9.5)
        speak("中文", from: 12, to: 60)
        speak("bwenos", from: 60, to: 130)
        recorder.feedAudio(seconds: 48, marker: mandarin)
        recorder.feedAudio(seconds: 72, marker: spanish)
        recorder.send("bwenos trigger", 131, 132)
        await settle(session)
        recorder.holdSwitch = true
        recorder.feedAudio(seconds: 20, marker: spanish)
        recorder.send("bwenos again", 145, 152)
        for _ in 0..<400 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(session.languageDetection.isSwitching)
        XCTAssertEqual(session.languageDetection.notice?.to, "zh-CN")
        XCTAssertFalse(session.canUndoLanguageSwitch, "Undo is not offered while the transcriber is replaced")
        session.undoLanguageSwitch()
        XCTAssertFalse(session.languageDetection.undoing)
        XCTAssertNil(session.message)

        recorder.holdSwitch = false
        recorder.releaseSwitch()
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN", "es-ES"])
        XCTAssertTrue(session.canUndoLanguageSwitch)
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 3 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.switches.last?.locale, "zh-CN", "Undo goes back one switch, from the latest")
        XCTAssertEqual(session.languageChoice, "zh-CN")
        await session.stop()
    }

    /// Findings 2 and 4: the new locale's assets took long enough that the planned start was released.
    /// The replay starts from the audio still held at the switch, and the notice says from when.
    func testASlowSwitchReplaysFromTheAudioStillHeldAndSaysFromWhen() async throws {
        let session = try await switchToMandarinAtOneMinute(holding: true)
        recorder.feedAudio(seconds: 100, marker: mandarin)
        XCTAssertEqual(recorder.languageAudio?.heldFrom, 130, "60 s, the change, is no longer held")
        recorder.holdSwitch = false
        recorder.releaseSwitch()
        await settle(session)
        let made = try XCTUnwrap(recorder.switches.last)
        XCTAssertTrue(made.replayed, "Not a lost replay")
        XCTAssertEqual(made.from, Int(141.5 * 16_000),
                       "Past the block about to be released, and past the line it would cut (137–141.5 s)")
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) from 2:21 · switched")
        XCTAssertTrue(session.segments.contains { $0.text == "ni hao 137" }, "Lines before the start stay")
        await session.stop()
    }

    /// Finding 4: the first switch, when the recording's start is no longer held, says from when.
    func testAFirstSwitchThatCannotStartAtTheBeginningSaysFromWhen() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 130)
        recorder.send("Late speech", 125, 135)
        await settle(session)
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) from 0:20 · switched")
        await session.stop()
    }

    /// Finding 5: an Apple Watch line merged into the conversation during a replay is kept; only the
    /// recording's own lines from the change are replaced.
    func testAReplayKeepsLinesThatAreNotTheRecordingsOwn() async throws {
        let session = try await switchToMandarinAtOneMinute()
        let watch = TranscriptSegment(source: .you, text: "From the watch", isFinal: true, start: 70, end: 72,
                                      speakerName: MobileFileTranscriber.speakerName)
        session.segments.append(watch)
        recorder.send("你好", 60, 149)
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("现在", 151, 153)
        XCTAssertTrue(session.segments.contains { $0.id == watch.id }, "The watch line survives the commit")
        XCTAssertEqual(session.segments.filter { $0.start >= 60 && !MobileSession.isWatchLine($0) }.map(\.text),
                       ["你好", "现在"])
        XCTAssertEqual(makeSession().segments.map(\.text), session.segments.map(\.text), "And is saved")
        await session.stop()
    }

    /// Finding 6: Undo in a recording that resumed a switched conversation restores the earlier
    /// recording's lines (changing the line count), then hears this recording again from its own first
    /// line: none of its lines is left behind twice.
    func testUndoInAResumedRecordingHearsAllOfItAgainOnce() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Wo men jin tian kai hui", 1, 9.5)
        await settle(session)
        recorder.send("我们", 1, 4)
        recorder.send("今天开会", 4, 9.5)
        recorder.send("好", 13, 15)
        XCTAssertEqual(session.segments.map(\.text), ["我们", "今天开会", "好"])
        await session.handleInterruption(.began)
        await session.handleInterruption(.ended, options: .shouldResume)
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        recorder.feedAudio(seconds: 12)
        recorder.send("继续", 1, 3)
        recorder.send("讨论", 3, 6)
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian kai hui", "好", "继续", "讨论"],
                       "The first recording's line comes back; this one's wait for the replay")
        recorder.send("ji xu", 1, 3)
        recorder.send("tao lun", 3, 6)
        recorder.feedAudio(seconds: 2)
        recorder.send("now in English", 12.5, 13.5)
        XCTAssertEqual(session.segments.map(\.text),
                       ["Wo men jin tian kai hui", "好", "ji xu", "tao lun", "now in English"])
        await session.stop()
    }
}
