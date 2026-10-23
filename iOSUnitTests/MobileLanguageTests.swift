import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #197: Automatic detects the spoken language on the device, switches once, and transcribes the
/// recording so far again. Whisper and the speech assets are fakes; the policy, wiring and Undo are real.
@MainActor
final class MobileLanguageTests: MobileLanguageTestCase {
    // MARK: Setting

    func testExistingUsersWhoChoseALanguageKeepItFixed() {
        UserDefaults.standard.removeObject(forKey: MobileLanguageDetection.automaticKey)
        UserDefaults.standard.set("zh-CN", forKey: MobileSession.languageKey)
        let pinned = makeSession()
        XCTAssertFalse(pinned.languageDetection.automatic)
        XCTAssertEqual(pinned.languageChoice, "zh-CN")
        XCTAssertEqual(pinned.transcriptionLanguage, "zh-CN")

        UserDefaults.standard.removeObject(forKey: MobileLanguageDetection.automaticKey)
        UserDefaults.standard.removeObject(forKey: MobileSession.languageKey)
        let fresh = makeSession()
        XCTAssertTrue(fresh.languageDetection.automatic, "Automatic is the default")
        XCTAssertEqual(fresh.languageChoice, MobileSession.automaticLanguageTag)
        XCTAssertEqual(fresh.transcriptionLanguage, Locale.current.identifier)
    }

    func testThePickerStoresAutomaticAndFixedLanguages() {
        let session = makeSession()
        session.languageChoice = "fr-FR"
        XCTAssertFalse(session.languageDetection.automatic)
        XCTAssertEqual(makeSession().transcriptionLanguage, "fr-FR", "A fixed language survives relaunch")
        session.languageChoice = MobileSession.automaticLanguageTag
        XCTAssertEqual(makeSession().languageChoice, MobileSession.automaticLanguageTag,
                       "Automatic survives relaunch even though a language was chosen before")
        XCTAssertEqual(session.language, "fr-FR", "The fixed choice is remembered for when Automatic is turned off")
    }

    // MARK: Detection

    func testAFixedLanguageNeverListensOrDownloads() async throws {
        let session = makeSession()
        session.languageChoice = "en-GB"
        try await record(session)
        XCTAssertNil(recorder.languageAudio, "No audio is kept for detection")
        XCTAssertEqual(recorder.startLocale, Locale(identifier: "en-GB"))
        recorder.send("Hello there, everyone, and welcome.", 1, 10)
        await session.stop()
        let prepares = await model.prepares()
        XCTAssertEqual(prepares, 0)
    }

    func testTheUnitTestHostNeverDownloadsTheLanguageModel() async {
        let model = WhisperLanguageIdentifier.deviceModel()
        XCTAssertFalse(model is WhisperLanguageIdentifier)
        do {
            try await model.prepare()
            XCTFail("The stand-in never loads")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The language model is not downloaded while unit tests run")
        }
    }

    func testABuildWithoutAModelKeepsTodaysBehavior() async throws {
        let session = makeSession(withModel: false)
        try await record(session)
        XCTAssertNil(recorder.languageAudio)
        XCTAssertTrue(session.quickDiagnostics.contains("Language model: not in this build"))
        await session.stop()
    }

    func testAConfidentOtherLanguageSwitchesAndTranscribesTheRecordingAgain() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        XCTAssertEqual(recorder.startLocale, Locale(identifier: Locale.current.identifier),
                       "Automatic starts in the device's language")
        await speakChinese(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        XCTAssertEqual(recorder.switches.map(\.replayed), [true])
        let samples = await model.lastSampleCount()
        XCTAssertEqual(samples, 184_000, "The window starts half a second before the first speech")

        recorder.send("我们今天开会", 1, 4)
        XCTAssertEqual(session.segments.map(\.text), ["Wo men jin tian", "kai hui tao lun"],
                       "Replayed lines are held until the replay catches up; the earlier lines stay meanwhile")
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) · switched")
        XCTAssertTrue(session.quickDiagnostics.contains("Language check: zh 97% → switched to zh-CN"))
        XCTAssertTrue(session.quickDiagnostics.contains("Recording language: zh-CN"))
        XCTAssertEqual(session.conversationLanguage, "zh-CN", "Apple Intelligence checks the switched language")

        recorder.send("讨论", 20, 30)
        XCTAssertEqual(session.segments.map(\.text), ["我们今天开会", "讨论"],
                       "Live speech after the switch commits the replay in one step")
        await session.languageDetection.check?.value
        XCTAssertEqual(recorder.switches.count, 1, "A recording switches once")
        await session.stop()
        XCTAssertNotNil(session.languageDetection.notice, "Undo stays offered after Stop")
    }

    /// Review of #201, finding 9.
    func testSpeechThatStartsAfterTheBufferedTwoMinutesIsReportedAsNotChecked() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 130)
        recorder.send("Late speech", 125, 135)
        await session.languageDetection.check?.value
        XCTAssertTrue(session.quickDiagnostics.contains(
            "Language check: Not checked (no speech in the first two minutes)"))
        let detections = await model.detections()
        XCTAssertEqual(detections, 0)
        XCTAssertTrue(recorder.switches.isEmpty)
        await session.stop()
    }

    func testEarlierRecordingsKeepTheirLinesAndOffsetsStayOnOneTimeline() async throws {
        await model.answer("es", 0.95)
        let session = makeSession()
        session.languageChoice = "en-US"
        try await record(session)
        recorder.send("An English recording.", 0, 3)
        await session.stop()

        session.languageChoice = MobileSession.automaticLanguageTag
        try await record(session)
        recorder.feedAudio(seconds: 10)
        recorder.send("Bueno sdias", 0.5, 9)
        await session.languageDetection.check?.value
        XCTAssertEqual(recorder.switches.map(\.locale), ["es-ES"])
        recorder.send("Buenos días", 0.5, 2)
        recorder.send("y ahora", 11, 12)
        XCTAssertEqual(session.segments.map(\.text), ["An English recording.", "Buenos días", "y ahora"])
        XCTAssertEqual(session.segments[1].start, 3.5, "Replayed lines keep the recording's offset")
        await session.stop()
    }

    func testLowConfidenceKeepsTheLanguageAndReleasesTheAudio() async throws {
        await model.answer("zh", 0.5)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        XCTAssertTrue(recorder.switches.isEmpty)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(recorder.languageAudio?.sampleCount, 0, "Audio no switch can use is released at once")
        XCTAssertTrue(session.quickDiagnostics.contains("zh 50% → kept (not confident)"))
        XCTAssertNil(session.languageDetection.noticeText)
        await session.stop()
    }

    func testTheSameLanguageIsKept() async throws {
        await model.answer(Locale.current.language.languageCode?.identifier ?? "en", 0.99)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        XCTAssertTrue(recorder.switches.isEmpty)
        XCTAssertTrue(session.quickDiagnostics.contains("kept (same language)"))
        await session.stop()
    }

    func testDetectionWaitsForEnoughSpeechAndStartsTheModelOnFirstSpeech() async throws {
        let session = makeSession()
        try await record(session)
        var prepares = await model.prepares()
        XCTAssertEqual(prepares, 0, "Nothing downloads before anyone speaks")
        recorder.feedAudio(seconds: 4)
        recorder.send("Short.", 1, 3)
        XCTAssertNil(session.languageDetection.check)
        for _ in 0..<200 where prepares == 0 {
            try await Task.sleep(for: .milliseconds(5))
            prepares = await model.prepares()
        }
        XCTAssertEqual(prepares, 1, "The first speech starts the model download in the background")
        let detections = await model.detections()
        XCTAssertEqual(detections, 0)
        await session.stop()
    }

    func testRecordingNeverWaitsForTheModel() async throws {
        await model.hold()
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        recorder.feedAudio(seconds: 12)
        recorder.send("Wo men", 1, 4)
        recorder.send("kai hui", 4, 9.5)
        XCTAssertEqual(session.languageDetection.status, .preparing)
        XCTAssertNotNil(session.languageDetection.statusLine)
        recorder.send("hai zai lu yin", 10, 12)
        XCTAssertEqual(session.segments.count, 3, "Lines keep arriving while the model loads")
        await model.release()
        await session.languageDetection.check?.value
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        await session.stop()
    }

    func testAnUnavailableModelKeepsRecordingWithAStatusLine() async throws {
        await model.fail("The Internet connection appears to be offline.")
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        for _ in 0..<200 where !session.languageDetection.isUnavailable { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        XCTAssertTrue(recorder.switches.isEmpty)
        XCTAssertEqual(session.segments.count, 2)
        let line = try XCTUnwrap(session.languageDetection.statusLine)
        XCTAssertTrue(line.hasPrefix("Language detection paused: The Internet connection appears to be offline. "
                                     + "Transcribing in"), line)
        await session.stop()

        try await record(session)
        XCTAssertFalse(session.languageDetection.isUnavailable, "The next recording tries again")
        await session.stop()
    }

    func testASwitchThatCannotStartKeepsTheLanguage() async throws {
        await model.answer("zh", 0.97)
        recorder.failSwitch = "Assets unavailable"
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        XCTAssertEqual(session.segments.count, 2, "The lines are kept")
        XCTAssertNil(session.languageDetection.notice)
        let line = try XCTUnwrap(session.languageDetection.statusLine)
        XCTAssertTrue(line.hasPrefix("Could not switch transcription to"), line)
        XCTAssertEqual(recorder.languageAudio?.sampleCount, 0)
        await session.stop()
    }
}
