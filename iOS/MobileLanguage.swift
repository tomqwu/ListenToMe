import Foundation
import ListenToMeCore
import Observation
import Speech
import WhisperKit

/// Whisper's most likely language for some audio, and how sure it is.
struct LanguageGuess: Sendable, Equatable {
    /// Whisper's language code, such as "zh" or "es".
    let language: String
    /// Probability of `language` among Whisper's languages, 0–1.
    let probability: Double
}

/// The spoken-language seam (issue #197). The real one is a small multilingual Whisper model run on this
/// device; tests substitute a fake because the simulator has no microphone and no speech assets.
protocol MobileLanguageIdentifying: Sendable {
    /// Downloads the model on first use and loads it. Throws when it cannot.
    func prepare() async throws
    /// The most likely language of 16 kHz mono `samples`.
    func detect(samples: [Float]) async throws -> LanguageGuess
    /// Locale identifiers on-device transcription supports.
    func supportedLocales() async -> [String]
}

/// Spoken-language identification with WhisperKit's multilingual "tiny" model (about 75 MB, downloaded
/// once from huggingface.co). Only the model is downloaded; audio never leaves the device. The model's
/// folder is kept out of iCloud and Finder backups because it can always be downloaded again.
actor WhisperLanguageIdentifier: MobileLanguageIdentifying {
    static let modelName = "tiny"
    /// About 73 MB of Core ML models plus a 3 MB tokenizer, measured for issue #197.
    static let downloadDescription = "about 75 MB"

    private let directory: URL
    private var kit: KitBox?
    private var loading: Task<KitBox, any Error>?

    init(directory: URL) {
        self.directory = directory
    }

    /// The app's identifier, with its model folder in Application Support and out of backups.
    static func onDevice() -> WhisperLanguageIdentifier {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("LanguageModels", isDirectory: true)
        try? PrivateStorage.createDirectory(at: directory)
        try? PrivateStorage.setExcludedFromBackup(true, at: directory)
        return WhisperLanguageIdentifier(directory: directory)
    }

    func prepare() async throws {
        _ = try await loadedKit()
    }

    func detect(samples: [Float]) async throws -> LanguageGuess {
        let box = try await loadedKit()
        let result = try await box.kit.detectLangauge(audioArray: samples)
        let logProbability = result.langProbs[result.language] ?? -.infinity
        return LanguageGuess(language: result.language, probability: Double(exp(logProbability)))
    }

    func supportedLocales() async -> [String] {
        await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    }

    /// One load at a time; a failure is not kept, so the next recording tries again.
    private func loadedKit() async throws -> KitBox {
        if let kit { return kit }
        if let loading { return try await loading.value }
        let directory = directory
        let task = Task { try await Self.load(from: directory) }
        loading = task
        defer { loading = nil }
        let box = try await task.value
        kit = box
        return box
    }

    /// Loads the model already on this device without touching the network, or downloads it first.
    private static func load(from directory: URL) async throws -> KitBox {
        let local = directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
        let parts = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
        let tokenizer = directory.appendingPathComponent("models/openai/whisper-\(modelName)/tokenizer.json")
        let downloaded = FileManager.default.fileExists(atPath: tokenizer.path)
            && parts.allSatisfy { FileManager.default.fileExists(atPath: local.appendingPathComponent($0).path) }
        let folder = downloaded ? local : try await WhisperKit.download(variant: modelName, downloadBase: directory)
        // The tokenizer is fetched beside the model (downloadBase), never into Documents.
        let config = WhisperKitConfig(downloadBase: directory, modelFolder: folder.path, tokenizerFolder: directory,
                                      verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
        return KitBox(kit: try await WhisperKit(config))
    }

    /// `WhisperKit` is a non-Sendable class; this actor is its only user. Mirrors the macOS box.
    private final class KitBox: @unchecked Sendable {
        let kit: WhisperKit
        init(kit: WhisperKit) { self.kit = kit }
    }
}

/// Automatic transcription language (issue #197): state of the current recording's language check and
/// of the last switch, for the status line, the notice and its Undo.
///
/// One `Run` per recording in Automatic mode. The recorder copies the audio it transcribes into
/// `Run.buffer` (at most `LanguageDetectionPolicy.maximumBuffered`); once enough speech is heard, the
/// first window is checked once. A recording switches at most once. The session does the switching.
@MainActor @Observable
final class MobileLanguageDetection {
    /// Set once the user picks Automatic or a fixed language. Before that, a user who had chosen a
    /// language (the session's `languageKey` exists) keeps it fixed, and everyone else is Automatic.
    static let automaticKey = "mobileTranscriptionLanguageAutomatic"

    enum Status: Equatable {
        case idle
        /// Downloading or loading the model.
        case preparing
        /// Running Whisper over the first window.
        case checking
        /// Restarting transcription in the detected language.
        case switching(String)
        /// The model could not be prepared; `reason` is the underlying message.
        case unavailable(String)
    }

    /// A switch, kept for the notice and its Undo.
    struct Switch: Equatable {
        /// Whisper's language code.
        let detected: String
        let from: String
        let to: String
        /// The conversation, and the index of the recording's first line in it.
        let conversation: String
        let firstLine: Int
        /// Transcript time at which the old transcriber stopped.
        let cut: TimeInterval
        /// The recording's lines before the switch, for an Undo after its audio is released.
        let originals: [TranscriptSegment]
    }

    struct Run {
        let buffer: SpeakerAudioBuffer
        let token: Int
        let offset: TimeInterval
        let firstLine: Int
        var locale: String
        var speechStart: TimeInterval?
        var speechEnd: TimeInterval = 0
        var started = false
        var switched = false
    }

    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Self.automaticKey) }
    }
    private(set) var status = Status.idle
    private(set) var notice: Switch?
    /// The last check's outcome, for Status details.
    private(set) var lastResult: String?
    /// The last problem worth a status line, such as a switch that failed. Cleared by the next recording.
    private(set) var lastError: String?
    /// True once the model has loaded in this app run.
    private(set) var modelReady = false
    private(set) var run: Run?
    private var runToken = 0
    private var identifier: (any MobileLanguageIdentifying)?
    /// `nil` when this build has no language model: unit tests, which must never download one.
    private let makeIdentifier: (() -> any MobileLanguageIdentifying)?
    /// The model preparation started by the run's first speech, and the run's check.
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored var check: Task<Void, Never>?

    init(makeIdentifier: (() -> any MobileLanguageIdentifying)?) {
        self.makeIdentifier = makeIdentifier
        let defaults = UserDefaults.standard
        automatic = defaults.object(forKey: Self.automaticKey) as? Bool
            ?? (defaults.string(forKey: MobileSession.languageKey) == nil)
    }

    var hasModel: Bool { makeIdentifier != nil }

    var model: (any MobileLanguageIdentifying)? {
        if let identifier { return identifier }
        identifier = makeIdentifier?()
        return identifier
    }

    /// Starts a recording's check and returns the buffer the recorder should copy audio into, or `nil`
    /// when the language is fixed. A model that failed to load is tried again.
    func beginRun(locale: String, offset: TimeInterval, firstLine: Int) -> SpeakerAudioBuffer? {
        endRun()
        notice = nil
        lastError = nil
        guard automatic, hasModel else { return nil }
        if isUnavailable { status = .idle }
        runToken &+= 1
        let buffer = SpeakerAudioBuffer(maxSamples: Int(LanguageDetectionPolicy.maximumBuffered)
                                        * LanguageDetectionPolicy.sampleRate)
        run = Run(buffer: buffer, token: runToken, offset: offset, firstLine: firstLine, locale: locale)
        return buffer
    }

    /// Downloads (first use) and loads the model in the background. Started by a recording's first
    /// speech, so a recording that never starts (the simulator, a denied microphone) downloads nothing.
    private func prepareModel(token: Int) {
        guard !modelReady, preparation == nil, let model else { return }
        status = .preparing
        preparation = Task { [weak self] in
            do {
                try await model.prepare()
                self?.modelLoaded(token: token)
            } catch {
                self?.modelFailed(error.localizedDescription, token: token)
            }
        }
    }

    /// Ends the recording's check and releases its audio. A check or preparation still running is dropped.
    func endRun() {
        preparation?.cancel()
        preparation = nil
        check?.cancel()
        check = nil
        run?.buffer.reset()
        run = nil
        runToken &+= 1
        if status != .idle, !isUnavailable { status = .idle }
    }

    var isUnavailable: Bool { if case .unavailable = status { true } else { false } }

    /// Notes a speech event in recording time. Returns the run's token when the check should start now.
    func noteSpeech(start: TimeInterval, end: TimeInterval) -> Int? {
        guard var current = run, !current.started, !isUnavailable else { return nil }
        if current.speechStart == nil {
            current.speechStart = start
            prepareModel(token: current.token)
        }
        current.speechEnd = max(current.speechEnd, end)
        let captured = TimeInterval(current.buffer.sampleCount) / TimeInterval(LanguageDetectionPolicy.sampleRate)
        let ready = LanguageDetectionPolicy.isReady(speechStart: current.speechStart, speechEnd: current.speechEnd,
                                                    captured: captured)
        if ready { current.started = true }
        run = current
        return ready ? current.token : nil
    }

    /// The first window of the run's audio, read off the main actor.
    func window(token: Int) async -> [Float]? {
        guard let current = run, current.token == token, let start = current.speechStart else { return nil }
        let buffer = current.buffer
        let range = LanguageDetectionPolicy.window(speechStart: start, totalSamples: buffer.sampleCount)
        let samples = await Task.detached { () -> [Float] in
            let snapshot = buffer.snapshot(fromSample: range.lowerBound)
            let lower = max(0, range.lowerBound - snapshot.startSample)
            let upper = min(snapshot.samples.count, range.upperBound - snapshot.startSample)
            return lower < upper ? Array(snapshot.samples[lower..<upper]) : []
        }.value
        return samples.isEmpty ? nil : samples
    }

    func isCurrent(_ token: Int) -> Bool { run?.token == token }

    func beginChecking() { status = .checking }

    /// The check kept the language: its audio is not needed for a replay, so it is released now.
    func kept(_ guess: LanguageGuess?, reason: String, token: Int) {
        guard isCurrent(token) else { return }
        lastResult = guess.map { "\(Self.describe($0)) → kept (\(reason))" } ?? "Not checked (\(reason))"
        if status == .checking { status = .idle }
        run?.buffer.reset()
    }

    func beginSwitch(to locale: String) { status = .switching(locale) }

    func switched(_ change: Switch, guess: LanguageGuess, token: Int) {
        guard isCurrent(token) else { return }
        run?.switched = true
        run?.locale = change.to
        notice = change
        lastResult = "\(Self.describe(guess)) → switched to \(change.to)"
        status = .idle
    }

    func switchFailed(_ reason: String, guess: LanguageGuess, to locale: String, token: Int) {
        guard isCurrent(token) else { return }
        lastResult = "\(Self.describe(guess)) → could not switch to \(locale)"
        lastError = "Could not switch transcription to \(Self.displayName(locale)): \(reason). " +
            "Still transcribing in \(Self.displayName(run?.locale ?? ""))."
        status = .idle
        run?.buffer.reset()
    }

    /// The user undid the switch, or the notice no longer applies.
    func clearNotice() { notice = nil }

    /// Undo switched the recording back to `locale`.
    func undone(to locale: String, token: Int) {
        guard isCurrent(token) else { return }
        run?.locale = locale
        lastResult = (lastResult ?? "") + "; undone"
    }

    private func modelLoaded(token: Int) {
        modelReady = true
        if isCurrent(token), status == .preparing { status = .idle }
    }

    private func modelFailed(_ reason: String, token: Int) {
        guard isCurrent(token) else { return }
        status = .unavailable(reason)
        lastResult = "Not checked (model unavailable)"
        run?.buffer.reset()
    }

    static func describe(_ guess: LanguageGuess) -> String {
        "\(guess.language) \(Int((guess.probability * 100).rounded()))%"
    }

    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    static func languageName(_ whisperCode: String) -> String {
        let code = LanguageDetectionPolicy.languageCode(forWhisper: whisperCode)
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// One line for the meeting status area, or `nil` when there is nothing to say.
    var statusLine: String? {
        switch status {
        case .preparing where run != nil:
            return "Getting language detection ready on this device (one-time download, " +
                "\(WhisperLanguageIdentifier.downloadDescription))…"
        case .checking: return "Checking the spoken language on this device…"
        case .switching(let locale): return "Switching transcription to \(Self.displayName(locale))…"
        case .unavailable(let reason):
            var trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            while trimmed.hasSuffix(".") { trimmed.removeLast() }
            let detail = trimmed.isEmpty ? "the language model could not be loaded" : trimmed
            return "Language detection paused: \(detail). Transcribing in " +
                "\(Self.displayName(run?.locale ?? Locale.current.identifier)); the next recording tries again."
        case .idle, .preparing: return lastError
        }
    }

    /// "Detected Chinese · switched", for the notice beside Undo.
    var noticeText: String? {
        notice.map { "Detected \(Self.languageName($0.detected)) · switched" }
    }
}
