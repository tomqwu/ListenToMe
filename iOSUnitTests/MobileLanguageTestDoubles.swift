import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// A recorder that copies audio for language detection and records each language switch. The real
/// switch needs Apple's speech assets, which the simulator does not have.
@MainActor
final class LanguageTestRecorder: MobileRecording {
    private(set) var languageAudio: SpeakerAudioBuffer?
    private(set) var startLocale: Locale?
    struct Switch { let locale: String; let replayed: Bool; let from: Int }
    private(set) var switches: [Switch] = []
    var failSwitch: String?
    /// False makes a switch continue the timeline without replay, as when its audio is no longer held.
    var replayAvailable = true
    /// Holds Stop (the recorder still finalizing) or a switch until the test releases it.
    var holdStop = false
    var holdSwitch = false
    private var heldStop: CheckedContinuation<Void, Never>?
    private var heldSwitch: CheckedContinuation<(any Error)?, Never>?
    private var generation = 0
    private var fed: TimeInterval = 0
    private var receive: (@MainActor (TranscriptSegment) -> Void)?

    var isHoldingStop: Bool { heldStop != nil }
    var isHoldingSwitch: Bool { heldSwitch != nil }
    func releaseStop() { heldStop?.resume(); heldStop = nil }
    func releaseSwitch(failing error: (any Error)? = nil) { heldSwitch?.resume(returning: error); heldSwitch = nil }

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
    func stop() async throws {
        if holdStop { await withCheckedContinuation { heldStop = $0 } }
        receive = nil
    }
    func reconfigure() async throws {}

    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?, replayFrom: @MainActor () -> Int?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws {
        if holdSwitch, let error = await withCheckedContinuation({ heldSwitch = $0 }) { throw error }
        if let failSwitch { throw RecordingError.message(failSwitch) }
        // Asked at the switch, as `MobileRecorder` does; the audio from there to now must still be held.
        let from = replay == nil ? 0 : (replayFrom() ?? -1)
        let replayed = replayAvailable && from >= 0 && (replay.map {
            !$0.didTruncate && from < $0.sampleCount && from >= $0.sampleCount - $0.retainedSampleCount
        } ?? false)
        switches.append(Switch(locale: locale.identifier, replayed: replayed, from: from))
        willReplace(replayed, fed)
    }

    /// Audio the transcriber accepted, copied for detection and trimmed to the trailing two minutes, as
    /// `AnalyzerSink` does. Fed a second at a time, as the microphone delivers it.
    func feedAudio(seconds: Int, marker: Float = 0) {
        for _ in 0..<seconds {
            languageAudio?.append(samples: [Float](repeating: marker, count: 16_000), sampleRate: 16_000,
                                  timestamp: 0, generation: generation)
            languageAudio?.keepTrailingLanguageAudio()
        }
        fed += TimeInterval(seconds)
    }

    /// A line, in the recorder's own (per-recording) time; final unless `final` is false.
    func send(_ text: String, _ start: TimeInterval, _ end: TimeInterval, final: Bool = true) {
        receive?(TranscriptSegment(source: .you, text: text, isFinal: final, start: start, end: end,
                                   speakerName: MobileSession.microphoneLabel))
    }
}

actor FakeLanguageModel: MobileLanguageIdentifying {
    private var guess = LanguageGuess(language: "en", probability: 0.99)
    /// Whether answers come from the audio itself (see `MobileLanguageTestCase.marker`), not `guess`.
    private var listens = false
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
    /// From now on, hear the language each second of fed audio was marked with: the most common one,
    /// with its share of the samples as the probability, as Whisper hears a window's main language.
    func listenToAudio() { listens = true }
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
        guard listens, !samples.isEmpty else { return guess }
        var counts: [Float: Int] = [:]
        for sample in samples { counts[sample, default: 0] += 1 }
        let top = counts.max { $0.value < $1.value } ?? (0, 0)
        return LanguageGuess(language: MobileLanguageTestCase.language(of: top.key),
                             probability: Double(top.value) / Double(samples.count))
    }

    func supportedLocales() async -> [String] { supported }
}

/// Shared setup for the Automatic-language tests (issue #197): a fake recorder and a fake Whisper,
/// with the language settings saved and restored around each test.
@MainActor
class MobileLanguageTestCase: XCTestCase {
    var root: URL!
    var recorder: LanguageTestRecorder!
    var model: FakeLanguageModel!
    var savedLanguage: Any?
    var savedAutomatic: Any?

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

    /// Fed audio is marked with the language it stands for: 0 is the device's language.
    nonisolated static let markers: [Float: String] = [1: "zh", 2: "es"]
    nonisolated static func language(of marker: Float) -> String {
        markers[marker] ?? Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Re-checks see these device conditions instead of the simulator's own.
    var conditions = LanguageRecheckPolicy.Conditions()

    func makeSession(withModel: Bool = true) -> MobileSession {
        let recorder = recorder!, model = model!
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder },
                                    makeLanguageModel: withModel ? { model } : nil)
        session.languageDetection.conditions = { [weak self] in self?.conditions ?? .init() }
        return session
    }

    func record(_ session: MobileSession) async throws {
        // The real workspace refreshes metadata after a language choice before enabling Start.
        await session.refreshRecordingSupport()
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
    }

    // MARK: Re-check scenarios (issue #199)

    let mandarin: Float = 1
    let spanish: Float = 2

    /// One line every five seconds from `start` to `end`, in recorder time.
    func speak(_ text: String, from start: TimeInterval, to end: TimeInterval) {
        var time = start
        while time < end {
            recorder.send("\(text) \(Int(time))", time, min(end, time + 4.5))
            time += 5
        }
    }

    func settle(_ session: MobileSession) async {
        await session.languageDetection.check?.value
    }

    /// The first check hears the device's language at 12 s and keeps it.
    func startInTheDevicesLanguage() async throws -> MobileSession {
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
    /// English, the 130 s one hears Mandarin, and the 150 s one confirms it. With `holding`, the recorder
    /// holds the switch (its assets still downloading) and the session is returned while it waits.
    func switchToMandarinAtOneMinute(holding: Bool = false) async throws -> MobileSession {
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
        recorder.holdSwitch = holding
        recorder.feedAudio(seconds: 20, marker: mandarin)
        speak("ni hao", from: 132, to: 150)
        if holding {
            for _ in 0..<400 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertTrue(session.languageDetection.isSwitching)
            return session
        }
        await settle(session)
        XCTAssertEqual(recorder.switches.map(\.locale), ["zh-CN"])
        return session
    }

    /// Ten seconds of speech in a language the transcriber does not know, then the check.
    func speakChinese(_ session: MobileSession) async {
        recorder.feedAudio(seconds: 12)
        recorder.send("Wo men jin tian", 1, 4)
        recorder.send("kai hui tao lun", 4, 9.5)
        await session.languageDetection.check?.value
    }
}
