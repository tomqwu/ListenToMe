import Foundation
import FluidAudio
import ListenToMeCore

/// On-device speaker diarization of the `.others` (system-audio) channel via FluidAudio's CoreML
/// Pyannote pipeline. Lazily prepares the models once (auto-downloaded on first use), runs the
/// offline diarizer over 16 kHz mono samples, maps its segments to Core's pure `DiarizedSegment`,
/// and returns a `SpeakerSummary`. An `actor` so the (non-Sendable, mutable) manager is isolated.
actor SpeakerDiarizer {
    /// FluidAudio expects 16 kHz mono; the diarizer needs at least a few seconds to be meaningful.
    private static let sampleRate = 16_000
    private static let minSamples = sampleRate * 3   // ~3 s

    /// FluidAudio's `OfflineDiarizerManager` is a non-Sendable `final class` whose async methods are
    /// `nonisolated`; it manages its own internal safety (models are written only at init, then read
    /// only). The actor already serializes every call into it, so we box it as `@unchecked Sendable`
    /// to satisfy Swift 6's sending check when awaiting its `async` methods.
    private final class ManagerBox: @unchecked Sendable {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
    }
    private let box = ManagerBox()
    /// True once `prepareModels()` has succeeded, so models are loaded only once per app run.
    private var prepared = false
    /// Tail of a serial task chain around the (non-Sendable) manager. Swift actors are REENTRANT at
    /// `await`, so without this an old `analyze` suspended inside `prepareModels()`/`process()` could
    /// be overlapped by a new one touching the same manager concurrently. Each link awaits the prior
    /// tail before running, so only one `prepareModels`/`process` is ever in flight. Mirrors the
    /// `transcriptionChain` pattern in `WhisperKitTranscriber`.
    private var chainTail: Task<Void, Never>?

    /// Result of a diarization run: the whole-session `summary` plus the raw `segments` (buffer-
    /// relative times, as FluidAudio returns them) so callers can align them onto the transcript.
    struct DiarizationOutcome: Sendable {
        let summary: SpeakerSummary
        let segments: [DiarizedSegment]
    }

    enum DiarizationError: LocalizedError {
        case notEnoughAudio

        var errorDescription: String? {
            switch self {
            case .notEnoughAudio:
                return "Need at least about 3 seconds of system audio to identify speakers."
            }
        }
    }

    /// Runs diarization over the captured 16 kHz mono samples, returning both the per-speaker talk-
    /// time summary and the raw (buffer-relative) segments for transcript alignment. Throws
    /// `DiarizationError.notEnoughAudio` for buffers shorter than ~3 s; propagates any FluidAudio
    /// model-load/processing error.
    ///
    /// The manager work is enqueued on a serial chain: each call awaits the prior tail before touching
    /// the (non-Sendable) manager, so even under actor reentrancy only one `prepareModels`/`process`
    /// runs at a time. The caller awaits `work.value` so errors propagate normally; the tail swallows
    /// them so a failed run can't break the chain for the next caller.
    func analyze(samples: [Float]) async throws -> DiarizationOutcome {
        guard samples.count >= Self.minSamples else { throw DiarizationError.notEnoughAudio }
        let previous = chainTail
        let work = Task { () throws -> DiarizationOutcome in
            await previous?.value   // wait for any in-flight manager call to finish first
            if !self.prepared {
                try await self.box.manager.prepareModels()
                self.prepared = true
            }
            let result = try await self.box.manager.process(audio: samples)
            let segments = result.segments.map {
                DiarizedSegment(speakerId: $0.speakerId,
                                start: TimeInterval($0.startTimeSeconds),
                                duration: TimeInterval($0.durationSeconds))
            }
            return DiarizationOutcome(summary: SpeakerStats.summarize(segments), segments: segments)
        }
        chainTail = Task { _ = try? await work.value }   // keep the chain alive regardless of outcome
        return try await work.value
    }
}
