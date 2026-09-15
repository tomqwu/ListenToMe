import Foundation

/// How a periodic speaker-identification pass ended.
public enum SpeakerAnalysisOutcome: Sendable, Equatable {
    /// The pass ran (possibly with a per-source hiccup) and periodic identification continues.
    case completed
    /// The diarizer's models could not be loaded — identification is off until the user retries.
    case modelsUnavailable
}

/// Pure scheduling/windowing policy for periodic on-device speaker identification (issue #109).
///
/// Two rules live here so they can be tested without CoreML or a capture session:
/// 1. **Trailing window.** A periodic pass re-analyzes only the audio since the previous pass, plus
///    a short overlap so identities can be merged by shared audio time; it never re-processes more
///    than `maximumWindow` seconds, so cost stays flat instead of growing with the meeting.
/// 2. **Failure latch.** When the models are unavailable (offline first run, captive Wi-Fi, blocked
///    host) the next pass is NOT scheduled, so a failed download is not retried every ~20 s for the
///    rest of the meeting; the UI shows one line instead, and pressing Speakers retries.
public enum SpeakerAnalysisPolicy {
    /// Diarization sample rate (16 kHz mono) — the format `SpeakerAudioBuffer` accumulates.
    public static let sampleRate = 16_000
    /// Shortest rest between two periodic passes.
    public static let minimumRest: TimeInterval = 20
    /// Longest stretch of trailing audio a single pass re-analyzes.
    public static let maximumWindow: TimeInterval = 600
    /// How much already-analyzed audio each window re-covers, so `SpeakerIdentityTracker` has enough
    /// shared time to carry identities (and edited names) across passes.
    public static let windowOverlap: TimeInterval = 60
    /// Below this, diarization is not meaningful (FluidAudio's floor is ~3 s).
    public static let minimumSamples = sampleRate * 3

    /// When the next periodic pass may run, or `nil` to stop scheduling until the user retries.
    /// A completed pass rests at least `minimumRest`, and at least as long as the pass itself took,
    /// so analysis can never occupy the machine back-to-back as the meeting grows.
    public static func nextAnalysis(passStarted: Date,
                                    finished: Date,
                                    outcome: SpeakerAnalysisOutcome) -> Date? {
        guard outcome == .completed else { return nil }
        let elapsed = max(0, finished.timeIntervalSince(passStarted))
        return finished.addingTimeInterval(max(minimumRest, elapsed))
    }

    /// First sample a pass should analyze, given the buffer's total sample count and how much of it
    /// a previous pass already covered. Rewinds by `windowOverlap` for identity merging and clamps
    /// the window to `maximumWindow`.
    public static func windowStartSample(totalSamples: Int, analyzedSamples: Int) -> Int {
        let total = max(0, totalSamples)
        let analyzed = min(max(0, analyzedSamples), total)
        let overlap = Int(windowOverlap) * sampleRate
        let cap = Int(maximumWindow) * sampleRate
        return max(max(0, analyzed - overlap), max(0, total - cap))
    }

    /// One-line rail status for the pass outcome (`nil` when nothing needs saying).
    public static func statusLine(for outcome: SpeakerAnalysisOutcome, detail: String?) -> String? {
        guard outcome == .modelsUnavailable else { return nil }
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var reason = trimmed.isEmpty ? "speaker models could not be loaded" : trimmed
        while reason.hasSuffix(".") { reason = String(reason.dropLast()) }
        return "Speaker identification paused — \(reason). Press Speakers to retry."
    }
}
