import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// A recorder that copies audio for language detection and records each language switch. The real
/// switch needs Apple's speech assets, which the simulator does not have.
@MainActor
final class LanguageTestRecorder: MobileRecording {
    private(set) var languageAudio: SpeakerAudioBuffer?
    private(set) var startLocale: Locale?
    private(set) var switches: [(locale: String, replayed: Bool)] = []
    var failSwitch: String?
    private var generation = 0
    private var fed: TimeInterval = 0
    private var receive: (@MainActor (TranscriptSegment) -> Void)?

    func attachLanguageAudio(_ buffer: SpeakerAudioBuffer?) {
        languageAudio = buffer
        generation = buffer?.currentGeneration() ?? 0
    }
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        startLocale = locale
        receive = onSegment
        fed = 0
    }
    func stop() async throws { receive = nil }
    func reconfigure() async throws {}

    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws {
        if let failSwitch { throw RecordingError.message(failSwitch) }
        let replayed = replay.map { !$0.didTruncate && $0.sampleCount > 0 } ?? false
        switches.append((locale.identifier, replayed))
        willReplace(replayed, fed)
    }

    func feedAudio(seconds: Int) {
        languageAudio?.append(samples: [Float](repeating: 0, count: seconds * 16_000), sampleRate: 16_000,
                              timestamp: 0, generation: generation)
        fed += TimeInterval(seconds)
    }

    /// A final line, in the recorder's own (per-recording) time.
    func send(_ text: String, _ start: TimeInterval, _ end: TimeInterval) {
        receive?(TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end,
                                   speakerName: MobileSession.microphoneLabel))
    }
}

actor FakeLanguageModel: MobileLanguageIdentifying {
    private var guess = LanguageGuess(language: "en", probability: 0.99)
    private var supported = ["en-US", "en-GB", "zh-CN", "zh-TW", "es-ES"]
    private var failure: String?
    private var holdPrepare = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var prepareCount = 0
    private var detectCount = 0
    private var sampleCount = 0

    func answer(_ language: String, _ probability: Double) {
        guess = LanguageGuess(language: language, probability: probability)
    }
    func fail(_ reason: String) { failure = reason }
    func hold() { holdPrepare = true }
    func release() { holdPrepare = false; held.forEach { $0.resume() }; held = [] }
    func prepares() -> Int { prepareCount }
    func detections() -> Int { detectCount }
    func lastSampleCount() -> Int { sampleCount }

    func prepare() async throws {
        prepareCount += 1
        if holdPrepare { await withCheckedContinuation { held.append($0) } }
        if let failure { throw RecordingError.message(failure) }
    }

    func detect(samples: [Float]) async throws -> LanguageGuess {
        detectCount += 1
        sampleCount = samples.count
        return guess
    }

    func supportedLocales() async -> [String] { supported }
}

/// Issue #197: Automatic detects the spoken language on the device, switches once, and transcribes the
/// recording so far again. Whisper and the speech assets are fakes; the policy, wiring and Undo are real.
@MainActor
final class MobileLanguageTests: XCTestCase {
    private var root: URL!
    private var recorder: LanguageTestRecorder!
    private var model: FakeLanguageModel!
    private var savedLanguage: Any?
    private var savedAutomatic: Any?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        recorder = LanguageTestRecorder()
        model = FakeLanguageModel()
        savedLanguage = UserDefaults.standard.object(forKey: MobileSession.languageKey)
        savedAutomatic = UserDefaults.standard.object(forKey: MobileLanguageDetection.automaticKey)
        UserDefaults.standard.set(true, forKey: MobileLanguageDetection.automaticKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedLanguage, forKey: MobileSession.languageKey)
        UserDefaults.standard.set(savedAutomatic, forKey: MobileLanguageDetection.automaticKey)
        try? FileManager.default.removeItem(at: root)
        recorder = nil; model = nil
    }

    private func makeSession(withModel: Bool = true) -> MobileSession {
        let recorder = recorder!, model = model!
        return MobileSession(storageDirectory: root, makeRecorder: { recorder },
                             makeLanguageModel: withModel ? { model } : nil)
    }

    private func record(_ session: MobileSession) async throws {
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
    }

    /// Ten seconds of speech in a language the transcriber does not know, then the check.
    private func speakChinese(_ session: MobileSession) async {
        recorder.feedAudio(seconds: 12)
        recorder.send("Wo men jin tian", 1, 4)
        recorder.send("kai hui tao lun", 4, 9.5)
        await session.languageDetection.check?.value
    }

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
        XCTAssertTrue(session.segments.isEmpty, "The wrong-language lines make way for the replay")
        let samples = await model.lastSampleCount()
        XCTAssertEqual(samples, 184_000, "The window starts half a second before the first speech")

        recorder.send("我们今天开会", 1, 4)
        XCTAssertEqual(session.segments.map(\.text), ["我们今天开会"])
        XCTAssertEqual(session.languageDetection.noticeText,
                       "Detected \(MobileLanguageDetection.languageName("zh")) · switched")
        XCTAssertTrue(session.quickDiagnostics.contains("Language check: zh 97% → switched to zh-CN"))
        XCTAssertTrue(session.quickDiagnostics.contains("Recording language: zh-CN"))

        recorder.send("讨论", 20, 30)
        await session.languageDetection.check?.value
        XCTAssertEqual(recorder.switches.count, 1, "A recording switches once")
        await session.stop()
        XCTAssertNotNil(session.languageDetection.notice, "Undo stays offered after Stop")
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
        XCTAssertEqual(session.segments.map(\.text), ["An English recording."])
        recorder.send("Buenos días", 0.5, 2)
        XCTAssertEqual(session.segments.last?.start, 3.5, "Replayed lines keep the recording's offset")
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

    // MARK: Undo

    func testUndoWhileRecordingSwitchesBackAndPinsTheOriginalLanguage() async throws {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们", 1, 4)
        session.undoLanguageSwitch()
        for _ in 0..<200 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN", Locale.current.identifier])
        XCTAssertEqual(recorder.switches.last?.replayed, true, "The audio is still held, so it is heard again")
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertNil(session.languageDetection.notice)
        XCTAssertFalse(session.languageDetection.automatic, "Undo pins the language")
        XCTAssertEqual(session.languageChoice, Locale.current.identifier)
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
}
