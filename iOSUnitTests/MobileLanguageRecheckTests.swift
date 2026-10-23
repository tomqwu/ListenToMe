import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #199: in Automatic, the language is re-checked during a recording. A confirmed change switches
/// the transcriber again and transcribes only the part since the change; Undo is for the latest switch.
/// The fake Whisper hears the language each second of fed audio was marked with (0: the device's
/// language, 1: Mandarin, 2: Spanish), so windows that straddle a change are as uncertain as real ones.
@MainActor
final class MobileLanguageRecheckTests: MobileLanguageTestCase {
    private let mandarin: Float = 1
    private let spanish: Float = 2

    /// One line every five seconds from `start` to `end`, in recorder time.
    private func speak(_ text: String, from start: TimeInterval, to end: TimeInterval) {
        var time = start
        while time < end {
            recorder.send("\(text) \(Int(time))", time, min(end, time + 4.5))
            time += 5
        }
    }

    private func settle(_ session: MobileSession) async {
        await session.languageDetection.check?.value
    }

    /// The first check hears the device's language at 12 s and keeps it.
    private func startInTheDevicesLanguage() async throws -> MobileSession {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Good morning", 1, 5)
        recorder.send("let's begin", 5, 9.5)
        await settle(session)
        XCTAssertTrue(session.quickDiagnostics.contains("kept (same language)"), session.quickDiagnostics)
        return session
    }

    /// English to 60 s, then Mandarin, as the issue's acceptance case: the 72 s re-check hears mostly
    /// English, the 130 s one hears Mandarin, and the 150 s one confirms it.
    private func switchToMandarinAtOneMinute() async throws -> MobileSession {
        let session = try await startInTheDevicesLanguage()
        speak("English", from: 10, to: 60)
        speak("ni hao", from: 60, to: 130)
        recorder.feedAudio(seconds: 48)
        recorder.feedAudio(seconds: 70, marker: mandarin)
        recorder.send("ni hao trigger", 130, 132)
        await settle(session)
        XCTAssertTrue(recorder.switches.isEmpty, "One check hearing Mandarin is not enough")
        XCTAssertTrue(session.quickDiagnostics.contains("checking again before switching to zh-CN"),
                      session.quickDiagnostics)
        recorder.feedAudio(seconds: 20, marker: mandarin)
        speak("ni hao", from: 132, to: 150)
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        return session
    }

    func testAChangeMidRecordingIsConfirmedAndOnlyThatSpanIsTranscribedAgain() async throws {
        let session = try await switchToMandarinAtOneMinute()
        XCTAssertEqual(recorder.switches.first?.from, 60 * 16_000, "Transcribed again from the change, not the start")
        XCTAssertEqual(recorder.switches.first?.replayed, true)
        let english = session.segments.filter { $0.start < 60 }.map(\.text)
        XCTAssertEqual(english.count, 12)
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) from 1:00 · switched")
        XCTAssertTrue(session.quickDiagnostics.contains("Language re-check: 1 switch · zh 100% → switched to zh-CN"),
                      session.quickDiagnostics)

        recorder.send("你好", 60, 64.5)
        recorder.send("我们开始开会", 65, 149)
        XCTAssertEqual(session.segments.filter { $0.start >= 60 }.first?.text, "ni hao 60",
                       "The Mandarin span's old lines stay until the replay catches up")
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("现在", 151, 153)
        XCTAssertEqual(session.segments.map(\.text), english + ["你好", "我们开始开会", "现在"],
                       "The English part is never transcribed again")
        await session.stop()
    }

    func testUndoOfAMidRecordingSwitchHearsOnlyThatSpanAgain() async throws {
        let session = try await switchToMandarinAtOneMinute()
        let english = session.segments.filter { $0.start < 60 }.map(\.text)
        recorder.send("你好", 60, 64.5)
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("现在", 151, 153)
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN", Locale.current.identifier])
        XCTAssertEqual(recorder.switches.last?.from, 60 * 16_000, "Undo hears the same span again")
        recorder.send("knee how", 60, 150)
        recorder.send("she en zai", 151, 153)
        recorder.feedAudio(seconds: 2)
        recorder.send("back in English", 156, 157)
        XCTAssertEqual(session.segments.map(\.text), english + ["knee how", "she en zai", "back in English"])
        XCTAssertFalse(session.languageDetection.automatic, "Undo pins the language from before the switch")
        XCTAssertEqual(session.languageChoice, Locale.current.identifier)
        XCTAssertTrue(session.quickDiagnostics.contains("; undone"), session.quickDiagnostics)
        await session.stop()
    }

    func testUndoAfterStopRestoresOnlyTheSpanTheSwitchReplaced() async throws {
        let session = try await switchToMandarinAtOneMinute()
        let before = session.segments.map(\.text)
        recorder.send("你好", 60, 149)
        recorder.feedAudio(seconds: 5, marker: mandarin)
        recorder.send("现在", 151, 153)
        await session.stop()
        session.undoLanguageSwitch()
        XCTAssertEqual(session.segments.map(\.text), before + ["现在"],
                       "The old lines come back for the span; the English before it and the line after stay")
        XCTAssertEqual(makeSession().segments.map(\.text), session.segments.map(\.text), "The restore is saved")
    }

    /// A second confirmed change switches again. The notice and Undo are for the latest switch; the
    /// first switch's lines stay.
    func testASecondChangeSwitchesAgainAndUndoIsForTheLatestSwitch() async throws {
        await model.listenToAudio()
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12, marker: mandarin)
        recorder.send("wo men", 1, 5)
        recorder.send("kai hui", 5, 9.5)
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        recorder.send("我们开会", 1, 9.5)
        speak("中文", from: 12, to: 60)
        speak("bwenos", from: 60, to: 150)
        XCTAssertEqual(session.segments.first?.text, "我们开会", "The first replay was committed")
        recorder.feedAudio(seconds: 48, marker: mandarin)
        recorder.feedAudio(seconds: 72, marker: spanish)
        recorder.send("bwenos trigger", 131, 132)
        await settle(session)
        recorder.feedAudio(seconds: 20, marker: spanish)
        recorder.send("bwenos again", 150, 152)
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN", "es-ES"])
        XCTAssertEqual(recorder.switches.last?.from, 60 * 16_000,
                       "The change found in a chunk moves back to the start of the line spanning it")
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("es")) from 1:00 · switched")
        XCTAssertEqual(session.languageDetection.notice?.from, "zh-CN")

        recorder.send("buenos días", 60, 150)
        recorder.feedAudio(seconds: 2, marker: spanish)
        recorder.send("hola", 153, 154)
        let mandarinLines = session.segments.filter { $0.start < 60 }.map(\.text)
        XCTAssertEqual(mandarinLines.first, "我们开会")
        await session.stop()
        session.undoLanguageSwitch()
        XCTAssertEqual(session.languageChoice, "zh-CN", "Undo goes back one switch, to Mandarin")
        XCTAssertEqual(session.segments.filter { $0.start < 60 }.map(\.text), mandarinLines,
                       "The earlier switch is kept")
        XCTAssertTrue(session.segments.contains { $0.text == "bwenos 60" }, "The latest switch's lines come back")
    }

    func testReChecksPauseInLowPowerModeAndDuringSilence() async throws {
        let session = try await startInTheDevicesLanguage()
        conditions.lowPower = true
        speak("English", from: 10, to: 72)
        recorder.feedAudio(seconds: 60)
        recorder.send("still English", 72, 73)
        await settle(session)
        var detections = await model.detections()
        XCTAssertEqual(detections, 1, "No re-check in Low Power Mode")
        XCTAssertTrue(session.quickDiagnostics.contains("Language re-check: 0 switches · skipped (Low Power Mode)"),
                      session.quickDiagnostics)

        conditions.lowPower = false
        recorder.feedAudio(seconds: 60)
        recorder.send("a short phrase", 130, 131)
        await settle(session)
        detections = await model.detections()
        XCTAssertEqual(detections, 1, "A window that is mostly silence is not checked")
        XCTAssertTrue(session.quickDiagnostics.contains("skipped (too little speech)"), session.quickDiagnostics)

        recorder.feedAudio(seconds: 15)
        speak("English", from: 131, to: 145)
        await settle(session)
        detections = await model.detections()
        XCTAssertEqual(detections, 2, "Once people speak again the re-check runs")
        XCTAssertTrue(session.quickDiagnostics.contains("kept (same language)"))
        await session.stop()
    }

    func testAFixedLanguageAfterUndoStopsReChecks() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        recorder.feedAudio(seconds: 120, marker: mandarin)
        speak("ni hao", from: 150, to: 270)
        await settle(session)
        XCTAssertEqual(recorder.switches.count, 2, "A pinned language is never switched again")
        await session.stop()
    }
}
