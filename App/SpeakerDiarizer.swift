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

    enum DiarizationError: LocalizedError {
        case notEnoughAudio

        var errorDescription: String? {
            switch self {
            case .notEnoughAudio:
                return "Need at least about 3 seconds of system audio to identify speakers."
            }
        }
    }

    /// Runs diarization over the captured 16 kHz mono samples and summarizes per-speaker talk time.
    /// Throws `DiarizationError.notEnoughAudio` for buffers shorter than ~3 s; propagates any
    /// FluidAudio model-load/processing error.
    func summarize(samples: [Float]) async throws -> SpeakerSummary {
        guard samples.count >= Self.minSamples else { throw DiarizationError.notEnoughAudio }
        if !prepared {
            try await box.manager.prepareModels()
            prepared = true
        }
        let result = try await box.manager.process(audio: samples)
        let segments = result.segments.map {
            DiarizedSegment(speakerId: $0.speakerId,
                            start: TimeInterval($0.startTimeSeconds),
                            duration: TimeInterval($0.durationSeconds))
        }
        return SpeakerStats.summarize(segments)
    }
}
