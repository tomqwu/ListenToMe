import Foundation
import ListenToMeCore
import Observation

/// Automatic transcription language (issues #197 and #199): state of the current recording's language
/// checks, of a replay in progress, and of the latest switch, for the status line, the notice and its Undo.
///
/// One `Run` per recording in Automatic mode. The recorder copies the audio it transcribes into
/// `Run.buffer`, which keeps only the trailing `LanguageRecheckPolicy.retained` seconds. Once enough
/// speech is heard the first window is checked, then a trailing window about once a minute while people
/// speak; `Run.tracker` decides when, and what a result means. A recording can switch more than once: the
/// notice and its Undo are for the latest switch, and earlier switches are kept. A later recording in the
/// same conversation starts in the language it switched to. The session does the switching.
@MainActor @Observable
final class MobileLanguageDetection {
    /// Set once the user picks Automatic or a fixed language. Before that, a user who had chosen a
    /// language (the session's `languageKey` exists) keeps it fixed, and everyone else is Automatic.
    static let automaticKey = "mobileTranscriptionLanguageAutomatic"

    enum Status: Equatable {
        case idle
        /// Downloading or loading the model.
        case preparing
        /// Running Whisper over the first window. Re-checks run without a status line.
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
        /// The conversation, the recording that switched, and the index of the first line the switch
        /// replaced (the recording's first line, unless a re-check found the change part-way through).
        let conversation: String
        let runToken: Int
        let firstLine: Int
        /// Transcript time from which the recording was transcribed again.
        let since: TimeInterval
        /// Transcript time at which the old transcriber stopped.
        let cut: TimeInterval
        /// Where transcribing again started in the run's audio, in 16 kHz samples, for an Undo's replay.
        let replayFrom: Int
        /// The lines the switch replaced (the unfinished line included), for an Undo after the replay
        /// audio is gone.
        let originals: [TranscriptSegment]
        /// False when the recording so far could not be transcribed again (its audio was not held): only
        /// new speech is in the new language, and nothing was replaced.
        let replayed: Bool
        /// A re-check found the change part-way through the recording (issue #199).
        let midRecording: Bool
        /// The switched recording's own lines, by id, recorded when it ends.
        var recordingLines: Set<UUID>?
    }

    /// The new transcriber is hearing the recording again. Its lines for the audio before `cut`
    /// (transcript time) are held here and replace the recording's lines from `firstLine` in one step,
    /// once it reaches live speech or the recording stops, so the earlier lines are never removed before
    /// their replacements exist, on screen or on disk.
    struct Replay {
        let token: Int
        let firstLine: Int
        let cut: TimeInterval
        var lines: [TranscriptSegment] = []
        /// A later switch without replay superseded this one: the rest of its lines are dropped.
        var discarded = false
    }

    /// A check the run asked for: the recorded audio to read, and whether it is the first check.
    struct Request: Equatable {
        let token: Int
        let window: Range<TimeInterval>
        /// The recording's first check (issue #197), rather than a re-check (issue #199).
        let first: Bool
    }

    struct Run {
        let buffer: SpeakerAudioBuffer
        let token: Int
        let offset: TimeInterval
        let firstLine: Int
        var tracker: LanguageTracker
        /// A check is running; the next one waits for it.
        var checking = false
        var locale: String { tracker.locale }
    }

    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Self.automaticKey) }
    }
    private(set) var status = Status.idle
    private(set) var notice: Switch?
    /// The first check's outcome, and the latest re-check's or why one was skipped, for Status details.
    private(set) var lastResult: String?
    private(set) var lastRecheck: String?
    /// The last problem worth a status line, such as a switch that failed. Cleared by the next recording.
    private(set) var lastError: String?
    /// True once the model has loaded in this app run.
    private(set) var modelReady = false
    private(set) var run: Run?
    var replay: Replay?
    /// An Undo is switching the live transcriber back; another tap waits for it.
    var undoing = false
    /// Undo was tapped while recording was stopping; it applies once the recording has ended.
    var pendingUndo = false
    private var runToken = 0
    private var identifier: (any MobileLanguageIdentifying)?
    /// `nil` when this build has no language model: unit tests, which must never download one.
    private let makeIdentifier: (() -> any MobileLanguageIdentifying)?
    /// The model preparation started by the run's first speech, and the run's latest check.
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored var check: Task<Void, Never>?
    /// Low Power Mode, the app's state and the device's temperature, read before each re-check.
    @ObservationIgnored var conditions: @MainActor () -> LanguageRecheckPolicy.Conditions =
        MobileLanguageDetection.deviceConditions

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

    /// Starts a recording's run and returns the buffer the recorder should copy audio into, or `nil`
    /// when the language is fixed. A recording that resumes a conversation which already switched
    /// (after a call, or Stop and Listen) starts in that language, keeps the notice and its Undo, and
    /// goes straight to re-checks. A model that failed to load is tried again.
    func beginRun(conversation: String, locale: String, offset: TimeInterval, firstLine: Int) -> SpeakerAudioBuffer? {
        endRun(recordingLines: nil)
        lastError = nil
        lastRecheck = nil
        let carried = automatic && notice?.conversation == conversation ? notice : nil
        notice = carried
        guard automatic, hasModel else { return nil }
        if isUnavailable { status = .idle }
        runToken &+= 1
        // Unbounded in total; the recorder keeps only the trailing seconds (`keepTrailingLanguageAudio`).
        let buffer = SpeakerAudioBuffer(maxSamples: .max)
        run = Run(buffer: buffer, token: runToken, offset: offset, firstLine: firstLine,
                  tracker: LanguageTracker(locale: carried?.to ?? locale, resumed: carried != nil))
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

    /// Ends the recording's run and releases its audio. A check or preparation still running is
    /// dropped. `recordingLines` are the run's own lines, kept for an Undo of its switch.
    func endRun(recordingLines: Set<UUID>?) {
        if let current = run, notice?.runToken == current.token, notice?.recordingLines == nil {
            notice?.recordingLines = recordingLines
        }
        preparation?.cancel()
        preparation = nil
        check?.cancel()
        check = nil
        replay = nil
        run?.buffer.reset()
        run = nil
        runToken &+= 1
        if status != .idle, !isUnavailable { status = .idle }
    }

    var isUnavailable: Bool { if case .unavailable = status { true } else { false } }

    /// Notes a speech event in recording time and returns the check to run now, if one is due. The
    /// first speech starts the model download. A check waits while another, a replay or an Undo runs.
    func noteSpeech(start: TimeInterval, end: TimeInterval) -> Request? {
        guard var current = run, !isUnavailable else { return nil }
        if current.tracker.speechStart == nil { prepareModel(token: current.token) }
        current.tracker.noteSpeech(start: start, end: end)
        defer { run = current }
        guard !current.checking, replay == nil, !undoing else { return nil }
        let captured = TimeInterval(current.buffer.sampleCount) / TimeInterval(LanguageDetectionPolicy.sampleRate)
        switch current.tracker.gate(now: captured, pinned: !automatic, conditions: conditions()) {
        case .wait:
            return nil
        case .skip(let reason):
            lastRecheck = "skipped (\(Self.describe(reason)))"
            return nil
        case .check(let window):
            current.checking = true
            return Request(token: current.token, window: window, first: current.tracker.phase == .first)
        }
    }

    /// The run's audio for each of `ranges` (recording time), read off the main actor from one
    /// snapshot. `nil` for a range whose audio is no longer held.
    func audio(_ ranges: [Range<TimeInterval>], token: Int) async -> [[Float]?] {
        guard let current = run, current.token == token, let lowest = ranges.map(\.lowerBound).min() else {
            return ranges.map { _ in nil }
        }
        let buffer = current.buffer
        return await Task.detached { () -> [[Float]?] in
            let total = buffer.sampleCount
            let first = LanguageRecheckPolicy.samples(lowest..<lowest, total: total).lowerBound
            let snapshot = buffer.snapshot(fromSample: first)
            return ranges.map { range in
                let wanted = LanguageRecheckPolicy.samples(range, total: total)
                // A block released since `wanted` was computed makes the snapshot start later.
                guard wanted.lowerBound >= snapshot.startSample else { return nil }
                let lower = wanted.lowerBound - snapshot.startSample
                let upper = min(snapshot.samples.count, wanted.upperBound - snapshot.startSample)
                return lower < upper ? Array(snapshot.samples[lower..<upper]) : nil
            }
        }.value
    }

    func isCurrent(_ token: Int) -> Bool { run?.token == token }

    /// The run's check has finished, whatever its result; the next one can be scheduled.
    func finishedCheck(_ token: Int) {
        guard isCurrent(token) else { return }
        run?.checking = false
    }

    /// Only the first check shows a status line; re-checks run quietly.
    func beginChecking(_ request: Request) {
        if request.first { status = .checking }
    }

    /// Records a check's result in the run's tracker and says what to do. While an Undo is switching
    /// back, the language counts as fixed: Undo pins it.
    func record(_ guess: LanguageGuess, for request: Request, supported: [String]) -> LanguageTracker.Outcome? {
        guard isCurrent(request.token) else { return nil }
        return run?.tracker.record(detected: guess.language, probability: guess.probability, window: request.window,
                                   supported: supported, region: Locale.current.region?.identifier,
                                   pinned: !automatic || undoing)
    }

    /// The check kept the language. The trailing audio stays for the next re-check.
    func kept(_ guess: LanguageGuess?, reason: String, request: Request) {
        guard isCurrent(request.token) else { return }
        let result = guess.map { "\(Self.describe($0)) → kept (\(reason))" } ?? "Not checked (\(reason))"
        if request.first { lastResult = result } else { lastRecheck = result }
        if status == .checking { status = .idle }
    }

    /// The check could not run (its audio was gone, or Whisper failed). It counts as a check, so a
    /// failing model is not run again on every speech event.
    func missed(_ reason: String, request: Request) {
        guard isCurrent(request.token) else { return }
        run?.tracker.missed(at: request.window.upperBound)
        kept(nil, reason: reason, request: request)
    }

    /// A re-check heard another language once; the next one must agree before switching.
    func confirming(_ guess: LanguageGuess, locale: String, request: Request) {
        guard isCurrent(request.token) else { return }
        lastRecheck = "\(Self.describe(guess)) → checking again before switching to \(locale)"
    }

    func beginSwitch(to locale: String) { status = .switching(locale) }

    /// The switch worked from `cut` (recording time). Its notice replaces an earlier switch's, which is kept.
    func switched(_ change: Switch, guess: LanguageGuess, token: Int, cut: TimeInterval) {
        guard isCurrent(token) else { return }
        run?.tracker.didSwitch(to: change.to, at: cut)
        notice = change
        let result = "\(Self.describe(guess)) → switched to \(change.to)" + (change.replayed ? "" : " for new speech")
        if change.midRecording { lastRecheck = result } else { lastResult = result }
        status = .idle
    }

    /// The switch could not start. The recording keeps its language and does not try `locale` again.
    func switchFailed(_ reason: String, guess: LanguageGuess, to locale: String, request: Request) {
        guard isCurrent(request.token) else { return }
        run?.tracker.switchFailed(to: locale)
        let result = "\(Self.describe(guess)) → could not switch to \(locale)"
        if request.first { lastResult = result } else { lastRecheck = result }
        lastError = "Could not switch transcription to \(Self.displayName(locale)): \(reason). " +
            "Still transcribing in \(Self.displayName(run?.locale ?? ""))."
        status = .idle
    }

    /// The user undid the switch, or the notice no longer applies.
    func clearNotice() { notice = nil }

    /// Undo switched the recording back to `locale`.
    func undone(to locale: String, token: Int, midRecording: Bool) {
        guard isCurrent(token) else { return }
        run?.tracker.undone(to: locale)
        if midRecording {
            lastRecheck = (lastRecheck ?? "") + "; undone"
        } else {
            lastResult = (lastResult ?? "") + "; undone"
        }
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
}
