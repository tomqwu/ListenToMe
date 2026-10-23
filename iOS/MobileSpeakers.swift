import Foundation
import ListenToMeCore
import Observation

/// The diarizer seam. The real one is FluidAudio's on-device pipeline (`SpeakerDiarizer`); tests
/// substitute a fake because the simulator cannot run the speaker models meaningfully.
protocol MobileSpeakerDiarizing: Sendable {
    /// Speaker segments for 16 kHz mono `samples`, in times relative to `samples[0]`.
    func diarize(samples: [Float]) async throws -> [DiarizedSegment]
    /// Clears a latched model-load failure so the next call tries to load the models again.
    func retryModelLoad() async
}

extension SpeakerDiarizer: MobileSpeakerDiarizing {
    func diarize(samples: [Float]) async throws -> [DiarizedSegment] {
        try await analyze(samples: samples).segments
    }
}

/// Opt-in, on-device speaker identification for one shared microphone (issue #180).
///
/// One `Run` per recording: the recorder copies the audio it transcribes into `Run.buffer`, and
/// each pass diarizes a trailing window of it (`SpeakerAnalysisPolicy`), reconciles the window's
/// speakers with earlier passes by shared audio time (`SpeakerIdentityTracker`) and keeps the
/// cumulative timeline the session maps onto transcript lines. A model-load failure is latched:
/// no further passes run until the user retries.
@MainActor @Observable
final class MobileSpeakers {
    static let enabledKey = "mobileIdentifySpeakers"
    /// Share of a line one speaker's speech must cover before the line is labeled with that speaker.
    /// One microphone hears everyone, so a line the diarizer barely heard keeps "Microphone".
    static let minimumCoverage = 0.3

    enum Status: Equatable {
        case idle
        case analyzing
        /// The speaker models could not be loaded; `reason` is the underlying message.
        case unavailable(String)
    }

    /// One trailing-window pass, ready to be mapped onto the transcript.
    struct Pass {
        /// Cumulative speaker timeline in identity-id space, in buffer time.
        let timeline: [DiarizedSegment]
        let identities: [String: SpeakerIdentity]
        /// Transcript time of the buffer's first sample.
        let offset: TimeInterval
        /// Index of this recording's first line in the conversation's segments.
        let firstLine: Int
    }

    private struct Run {
        let buffer: SpeakerAudioBuffer
        let offset: TimeInterval
        let firstLine: Int
        let token: Int
        var tracker: SpeakerIdentityTracker
        var identities: [String: SpeakerIdentity] = [:]
        var timeline: [DiarizedSegment] = []
        var analyzedSamples = 0
    }

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    private(set) var status = Status.idle
    /// The last non-model failure, for the status line. Cleared by the next successful pass.
    private(set) var lastError: String?
    /// Diarizer calls made, for diagnostics and tests.
    private(set) var passCount = 0
    private var run: Run?
    private var runToken = 0
    private var diarizer: (any MobileSpeakerDiarizing)?
    private let makeDiarizer: () -> any MobileSpeakerDiarizing

    init(makeDiarizer: @escaping () -> any MobileSpeakerDiarizing) {
        self.makeDiarizer = makeDiarizer
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isRunning: Bool { run != nil }
    var isUnavailable: Bool { if case .unavailable = status { true } else { false } }

    /// Starts a recording's run and returns the buffer the recorder should copy audio into, or `nil`
    /// when Identify speakers is off. `existing` is the conversation so far: new voices are numbered
    /// after every speaker it already names, because voices are not matched across recordings.
    func beginRun(offset: TimeInterval, existing: [TranscriptSegment]) -> SpeakerAudioBuffer? {
        endRun()
        guard enabled else { return nil }
        // A new recording is also a retry: the model download may well succeed now (#109).
        if isUnavailable {
            status = .idle
            if let diarizer { Task { await diarizer.retryModelLoad() } }
        }
        lastError = nil
        let buffer = SpeakerAudioBuffer()
        runToken &+= 1
        let first = SpeakerLabeling.nextSpeakerNumber(after: existing)
        run = Run(buffer: buffer, offset: offset, firstLine: existing.count, token: runToken,
                  tracker: SpeakerIdentityTracker(firstNumber: first))
        return buffer
    }

    /// Ends the run and releases its audio. A pass still in flight is discarded.
    func endRun() {
        run?.buffer.reset()
        run = nil
        runToken &+= 1
        if status == .analyzing { status = .idle }
    }

    /// Keeps a rename made during a recording for the rest of that recording's passes.
    func rename(id: String, name: String) {
        run?.tracker.rename(id: id, name: name)
        run?.identities[id]?.name = name
    }

    /// The user's retry gesture after a latched model failure.
    func retry() async {
        guard isUnavailable else { return }
        status = .idle
        lastError = nil
        await diarizer?.retryModelLoad()
    }

    /// Releases audio the next pass can no longer need: everything before the overlap the next
    /// window rewinds into. While the models are unavailable no pass consumes the audio, so only the
    /// last overlap's worth is kept for a retry. Memory then stays flat for a long meeting.
    func releaseAnalyzedAudio() {
        guard let run else { return }
        let overlap = Int(SpeakerAnalysisPolicy.windowOverlap) * SpeakerAnalysisPolicy.sampleRate
        let consumed = isUnavailable ? run.buffer.sampleCount : run.analyzedSamples
        run.buffer.discardAudio(before: consumed - overlap)
    }

    /// One trailing-window pass. `nil` when there is nothing to do (no run, nothing new, too little
    /// audio, a pass already running, models unavailable) or the pass failed or was superseded.
    func analyze() async -> Pass? {
        guard let current = run, status != .analyzing, !isUnavailable else { return nil }
        let buffer = current.buffer
        let captured = buffer.sampleCount
        guard SpeakerAnalysisPolicy.hasNewAudio(totalSamples: captured, analyzedSamples: current.analyzedSamples) else {
            return nil
        }
        let from = SpeakerAnalysisPolicy.windowStartSample(totalSamples: captured,
                                                           analyzedSamples: current.analyzedSamples)
        let snapshot = await Task.detached { buffer.snapshot(fromSample: from) }.value
        guard run?.token == current.token,
              snapshot.samples.count >= SpeakerAnalysisPolicy.minimumSamples else { return nil }
        status = .analyzing
        passCount += 1
        let diarizer = diarizer ?? makeDiarizer()
        self.diarizer = diarizer
        do {
            let segments = try await diarizer.diarize(samples: snapshot.samples)
            guard var updated = run, updated.token == current.token else { return nil }
            status = .idle
            lastError = nil
            fold(segments, windowStart: snapshot.startTime, into: &updated)
            updated.analyzedSamples = snapshot.startSample + snapshot.samples.count
            run = updated
            return Pass(timeline: updated.timeline, identities: updated.identities,
                        offset: updated.offset + snapshot.startOffset, firstLine: updated.firstLine)
        } catch {
            guard run?.token == current.token else { return nil }
            if let reason = (error as? SpeakerDiarizer.DiarizationError)?.modelFailureReason {
                status = .unavailable(reason)
            } else {
                status = .idle
                lastError = error.localizedDescription
            }
            return nil
        }
    }

    /// Folds one window's speakers into the run: window-relative times are shifted into buffer time,
    /// reconciled with earlier passes, and spliced onto the cumulative timeline.
    private func fold(_ segments: [DiarizedSegment], windowStart: TimeInterval, into run: inout Run) {
        let window = segments.map {
            DiarizedSegment(speakerId: $0.speakerId, start: $0.start + windowStart, duration: $0.duration)
        }
        let mapping = run.tracker.reconcile(window, since: windowStart)
        for identity in mapping.values { run.identities[identity.id] = identity }
        let identified = window.compactMap { segment in
            mapping[segment.speakerId].map {
                DiarizedSegment(speakerId: $0.id, start: segment.start, duration: segment.duration)
            }
        }
        run.timeline = SpeakerStats.splice(history: run.timeline, window: identified, windowStart: windowStart)
    }

    /// One line for the meeting status area, or `nil` when there is nothing to say.
    var statusLine: String? {
        switch status {
        case .analyzing: return "Identifying speakers on this device…"
        case .unavailable(let reason):
            var trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            while trimmed.hasSuffix(".") { trimmed.removeLast() }
            let detail = trimmed.isEmpty ? "speaker models could not be loaded" : trimmed
            return "Speaker identification paused: \(detail). Lines keep the Microphone label until you retry."
        case .idle:
            return lastError.map { "Speaker identification skipped a pass: \($0)" }
        }
    }
}
