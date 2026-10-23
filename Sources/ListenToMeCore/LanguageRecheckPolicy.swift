import Foundation

/// Re-checking the spoken language during a recording (issue #199).
///
/// Issue #197 checks the first stretch of speech once. A bilingual meeting, or a speaker who changes
/// language part-way, then kept the first language and the later lines came out as nonsense. In
/// Automatic mode the app now also checks a trailing window of speech about once a minute. A different
/// language must be heard twice in a row before the transcriber switches (hysteresis), a switch stays for
/// a minimum time, and a recording switches a limited number of times. When a switch is confirmed, short
/// chunks of the audio since the language was last confirmed are checked to find where it changed, and
/// only that span is transcribed again, from a trailing copy of the audio with a fixed memory budget.
///
/// Times are recording time: seconds since the recorder started, the timeline of its results and of the
/// audio it copies for language detection.
public enum LanguageRecheckPolicy {
    /// Recording time between re-checks once the language was last checked.
    public static let interval: TimeInterval = 60
    /// Trailing audio Whisper reads for a re-check.
    public static let window: TimeInterval = 30
    /// Speech a re-check window must hold. A quieter window is skipped, so silence costs no detection.
    public static let minimumSpeech: TimeInterval = 10
    /// A different language heard once is a candidate; a check this much later must hear it again.
    public static let confirmationDelay: TimeInterval = 20
    /// After a switch the language stays at least this long, so it never flips back and forth.
    public static let minimumDwell: TimeInterval = 90
    /// Switches per recording, the first check's included. Re-checks stop once it is reached.
    public static let maximumSwitches = 4
    /// Trailing audio kept for checks and for transcribing again after a switch: about 7.7 MB of 16 kHz
    /// mono audio (plus at most one 10-second storage block). Older audio is released as recording goes on.
    public static let retained: TimeInterval = 120
    /// Length of the chunks checked to find where the language changed.
    public static let scanChunk: TimeInterval = 10
    /// Speech a chunk must hold to be checked; Whisper's guess for silence means nothing.
    public static let minimumChunkSpeech: TimeInterval = 4
    /// At most this many chunks are checked per switch, the latest ones.
    public static let maximumScanChunks = 12
    /// A chunk counts as one of the two languages from this probability: ten seconds of speech are
    /// less certain than a full window, and a chunk only places the change, it never causes a switch.
    public static let chunkConfidence = 0.5

    /// `retained` in 16 kHz samples.
    public static var retainedSamples: Int { Int(retained) * LanguageDetectionPolicy.sampleRate }

    /// Why a re-check that is due does not run now. Each one saves battery.
    public enum Skip: Sendable, Equatable {
        case lowPower
        case background
        case thermal
        /// The trailing window holds less than `minimumSpeech` of speech.
        case silence
    }

    /// Device conditions under which re-checks pause.
    public struct Conditions: Sendable, Equatable {
        public var lowPower: Bool
        public var background: Bool
        /// The device is hot (serious or critical thermal state).
        public var thermal: Bool

        public init(lowPower: Bool = false, background: Bool = false, thermal: Bool = false) {
            self.lowPower = lowPower
            self.background = background
            self.thermal = thermal
        }
    }

    /// What a chunk heard while looking for the change.
    public enum Verdict: Sendable, Equatable {
        /// The language being transcribed before the switch.
        case current
        /// The language being switched to.
        case target
        case unclear
    }

    /// What Whisper's guess for one chunk says, given the transcribed (`current`) and the new (`target`)
    /// locale identifiers.
    public static func verdict(detected: String, probability: Double, current: String,
                               target: String) -> Verdict {
        guard probability.isFinite, probability >= chunkConfidence else { return .unclear }
        let spoken = LanguageDetectionPolicy.languageCode(forWhisper: detected)
        if spoken == LanguageDetectionPolicy.spokenLanguage(of: target) { return .target }
        if spoken == LanguageDetectionPolicy.spokenLanguage(of: current) { return .current }
        return .unclear
    }

    /// The chunks of `span` to check for the change: `scanChunk` long, each holding at least
    /// `minimumChunkSpeech` of speech (`speech` measures a range), at most `maximumScanChunks`, the latest.
    public static func scanChunks(_ span: Range<TimeInterval>,
                                  speech: (Range<TimeInterval>) -> TimeInterval) -> [Range<TimeInterval>] {
        guard span.upperBound - span.lowerBound >= minimumChunkSpeech else { return [] }
        var chunks: [Range<TimeInterval>] = []
        var start = span.lowerBound
        while start < span.upperBound {
            let chunk = start..<min(span.upperBound, start + scanChunk)
            if speech(chunk) >= minimumChunkSpeech { chunks.append(chunk) }
            start += scanChunk
        }
        return Array(chunks.suffix(maximumScanChunks))
    }

    /// Where the language changed within `span`: the start of the first chunk after the last one that
    /// still heard the current language. With no such chunk, the span's start; when the last chunk heard
    /// the current language, the span's end, so nothing heard in it is transcribed again.
    public static func changePoint(in span: Range<TimeInterval>,
                                   scanned: [(chunk: Range<TimeInterval>, verdict: Verdict)]) -> TimeInterval {
        let ordered = scanned.sorted { $0.chunk.lowerBound < $1.chunk.lowerBound }
        guard let last = ordered.lastIndex(where: { $0.verdict == .current }) else { return span.lowerBound }
        return ordered.index(after: last) < ordered.count ? ordered[last + 1].chunk.lowerBound : span.upperBound
    }

    /// Where transcribing again starts: at `desired`, never before the audio still held (`retainedFrom`),
    /// and never in the middle of a line, so no sentence is cut in two. A line spanning that point moves
    /// it back to the line's start, or past the line's end when its start is no longer held.
    public static func replayStart(desired: TimeInterval, retainedFrom: TimeInterval,
                                   lines: [Range<TimeInterval>]) -> TimeInterval {
        var start = max(desired, retainedFrom)
        // A moved start can land inside another line, so repeat until it is clear of every line.
        for _ in 0...lines.count {
            guard let spanning = lines.first(where: { $0.lowerBound < start && start < $0.upperBound }) else { break }
            start = spanning.lowerBound >= retainedFrom ? spanning.lowerBound : spanning.upperBound
        }
        return start
    }

    /// Length of the trailing buffer's storage blocks (`SpeakerAudioBuffer.blockSize`), released whole.
    public static let storageBlock: TimeInterval = 10

    /// The earliest audio a replay can safely start from, given the audio `captured` so far and the
    /// oldest audio still held. When the buffer is about to release its oldest block, that block is
    /// skipped: it may be gone by the time the new transcriber is ready to hear it.
    public static func replayFloor(captured: TimeInterval, heldFrom: TimeInterval) -> TimeInterval {
        captured - heldFrom >= retained ? heldFrom + storageBlock : heldFrom
    }

    /// The 16 kHz sample indexes of `range`, within the `total` samples captured.
    public static func samples(_ range: Range<TimeInterval>, total: Int) -> Range<Int> {
        let rate = Double(LanguageDetectionPolicy.sampleRate)
        let total = max(0, total)
        let lower = min(total, max(0, Int((range.lowerBound * rate).rounded(.down))))
        let upper = min(total, max(lower, Int((range.upperBound * rate).rounded(.down))))
        return lower..<upper
    }
}

/// The language state of one recording in Automatic mode (issue #199): when to check, what a check's
/// result means, and how many times the recording has switched. A pure value; the app feeds it speech
/// events and Whisper's guesses and acts on its answers.
public struct LanguageTracker: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Waiting for the first stretch of speech (issue #197). The first check switches at once.
        case first
        /// After the first decision: trailing windows are re-checked with hysteresis.
        case rechecking
    }

    /// A different language heard once, waiting for a second check to agree.
    public struct Candidate: Sendable, Equatable {
        public let detected: String
        public let locale: String
        public let heardAt: TimeInterval
    }

    public enum Gate: Sendable, Equatable {
        /// Nothing is due.
        case wait
        /// A re-check is due but does not run now.
        case skip(LanguageRecheckPolicy.Skip)
        /// Check this range of recorded audio.
        case check(Range<TimeInterval>)
    }

    public enum Outcome: Sendable, Equatable {
        case keep(LanguageDetectionPolicy.Reason)
        /// A different language was heard once; the next check must agree before switching to `locale`.
        case confirming(String)
        /// Switch to this locale and transcribe again from `since`.
        case switchTo(String, since: TimeInterval)
        /// A re-check confirmed this locale: find where the language changed within `span` (see
        /// `LanguageRecheckPolicy.changePoint`), then switch and transcribe again from there.
        case locate(String, span: Range<TimeInterval>)
    }

    /// The locale being transcribed.
    public private(set) var locale: String
    public private(set) var phase: Phase
    public private(set) var switches = 0
    public private(set) var lastSwitch: TimeInterval?
    /// When the last check ran (its window's end).
    public private(set) var lastCheck: TimeInterval?
    /// The end of the last window that heard the language being transcribed, or the last switch.
    public private(set) var heardThrough: TimeInterval = 0
    public private(set) var candidate: Candidate?
    /// The first speech event, and the end of the latest.
    public private(set) var speechStart: TimeInterval?
    public private(set) var speechEnd: TimeInterval = 0
    /// Locales a switch to failed in this recording (their speech model could not be prepared).
    public private(set) var unavailable: Set<String> = []
    /// Speech heard, merged, kept only as far back as the audio is.
    private var speech: [Range<TimeInterval>] = []

    /// A recording that continues a conversation which already switched (`resumed`) starts in the switched
    /// language and goes straight to re-checks, the first one an interval in.
    public init(locale: String, resumed: Bool = false) {
        self.locale = locale
        phase = resumed ? .rechecking : .first
        if resumed { lastCheck = 0 }
    }

    /// Notes a speech event. Results can arrive out of order (a replay hears the past again).
    public mutating func noteSpeech(start: TimeInterval, end: TimeInterval) {
        guard start.isFinite, end.isFinite else { return }
        speechStart = min(speechStart ?? start, start)
        speechEnd = max(speechEnd, end)
        guard end > start else { return }
        var merged = start..<end
        speech.removeAll { other in
            guard other.lowerBound <= merged.upperBound, merged.lowerBound <= other.upperBound else { return false }
            merged = min(other.lowerBound, merged.lowerBound)..<max(other.upperBound, merged.upperBound)
            return true
        }
        let index = speech.firstIndex { $0.lowerBound > merged.lowerBound } ?? speech.endIndex
        speech.insert(merged, at: index)
        let horizon = speechEnd - LanguageRecheckPolicy.retained - LanguageRecheckPolicy.window
        speech.removeAll { $0.upperBound < horizon }
    }

    /// Seconds of speech heard within `range`.
    public func speech(in range: Range<TimeInterval>) -> TimeInterval {
        speech.reduce(0) { total, heard in
            total + max(0, min(heard.upperBound, range.upperBound) - max(heard.lowerBound, range.lowerBound))
        }
    }

    /// Whether to check now, `now` being the audio captured so far. A fixed language never checks. The
    /// first check waits for enough speech; re-checks wait for their time, then pause in Low Power Mode,
    /// in the background, while the device is hot and while the trailing window is mostly silence.
    public func gate(now: TimeInterval, pinned: Bool, conditions: LanguageRecheckPolicy.Conditions) -> Gate {
        guard !pinned else { return .wait }
        switch phase {
        case .first:
            guard let start = speechStart,
                  LanguageDetectionPolicy.isReady(speechStart: start, speechEnd: speechEnd, captured: now) else {
                return .wait
            }
            let lower = max(0, start - 0.5)
            return .check(lower..<max(lower, min(now, lower + LanguageDetectionPolicy.maximumWindow)))
        case .rechecking:
            guard switches < LanguageRecheckPolicy.maximumSwitches, now >= due(now: now) else { return .wait }
            if conditions.lowPower { return .skip(.lowPower) }
            if conditions.background { return .skip(.background) }
            if conditions.thermal { return .skip(.thermal) }
            let window = max(0, now - LanguageRecheckPolicy.window)..<now
            guard speech(in: window) >= LanguageRecheckPolicy.minimumSpeech else { return .skip(.silence) }
            return .check(window)
        }
    }

    /// When the next re-check is due: a candidate's confirmation, never inside the dwell after a switch,
    /// or an interval after the last check.
    public func due(now: TimeInterval) -> TimeInterval {
        if let candidate = liveCandidate(now: now) {
            return max(candidate.heardAt + LanguageRecheckPolicy.confirmationDelay,
                       (lastSwitch ?? -.infinity) + LanguageRecheckPolicy.minimumDwell)
        }
        return (lastCheck ?? 0) + LanguageRecheckPolicy.interval
    }

    // The inputs mirror `LanguageDetectionPolicy.decide`, so each test states its case in one call.
    // swiftlint:disable function_parameter_count
    /// Records a check of `window` that heard `detected` with `probability`, and says what to do.
    /// `supported` lists the locales on-device transcription accepts; `region` is the device's.
    public mutating func record(detected: String, probability: Double, window: Range<TimeInterval>,
                                supported: [String], region: String?, pinned: Bool) -> Outcome {
        let now = window.upperBound
        lastCheck = now
        let decision = LanguageDetectionPolicy.decide(
            detected: detected, probability: probability, current: locale,
            supported: supported.filter { !unavailable.contains($0) }, pinned: pinned,
            atSwitchLimit: switches >= LanguageRecheckPolicy.maximumSwitches, region: region)
        if phase == .first {
            phase = .rechecking
            heardThrough = now
            switch decision {
            case .keep(let reason): return .keep(reason)
            case .switchTo(let target): return .switchTo(target, since: 0)
            }
        }
        let pending = liveCandidate(now: now)
        candidate = nil
        switch decision {
        case .keep(let reason):
            if reason == .sameLanguage { heardThrough = now }
            return .keep(reason)
        case .switchTo(let target):
            guard let pending, pending.locale == target,
                  now >= (lastSwitch ?? -.infinity) + LanguageRecheckPolicy.minimumDwell else {
                candidate = Candidate(detected: detected, locale: target, heardAt: now)
                return .confirming(target)
            }
            let floor = max(0, lastSwitch ?? 0, now - LanguageRecheckPolicy.retained)
            let start = min(now, max(floor, heardThrough - LanguageRecheckPolicy.window / 2))
            return .locate(target, span: start..<now)
        }
    }
    // swiftlint:enable function_parameter_count

    /// The transcriber now runs in `target`, from `cut` on.
    public mutating func didSwitch(to target: String, at cut: TimeInterval) {
        locale = target
        switches += 1
        lastSwitch = cut
        lastCheck = cut
        heardThrough = cut
        candidate = nil
        phase = .rechecking
    }

    /// A check due at `now` could not run (its audio was gone, or the model failed). It counts as a
    /// check, so the next one is an interval later and a pending candidate is dropped.
    public mutating func missed(at now: TimeInterval) {
        phase = .rechecking
        lastCheck = now
        candidate = nil
    }

    /// A switch to `target` could not start; this recording does not try that locale again.
    public mutating func switchFailed(to target: String) {
        unavailable.insert(target)
        candidate = nil
    }

    /// Undo switched the transcriber back to `previous`.
    public mutating func undone(to previous: String) {
        locale = previous
        candidate = nil
    }

    /// A candidate older than an interval is stale: its audio may be gone and the speech has moved on.
    private func liveCandidate(now: TimeInterval) -> Candidate? {
        guard let candidate, now - candidate.heardAt <= LanguageRecheckPolicy.interval else { return nil }
        return candidate
    }
}
