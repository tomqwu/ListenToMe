import Foundation
import Observation

@MainActor @Observable
public final class LiveAudioLevels {
    public struct Sample: Equatable, Sendable {
        public let decibels: Double
        public let measuredAt: TimeInterval
        public var fraction: Double { min(1, max(0, (decibels + 60) / 60)) }
    }
    private var samples: [SpeakerSource: Sample] = [:]
    public init() {}
    public func reset() { samples = [:] }
    public func sample(for source: SpeakerSource, now: TimeInterval) -> Sample? {
        guard let sample = samples[source], abs(now - sample.measuredAt) <= 0.5 else { return nil }
        return sample
    }
    public func ingest(_ chunk: AudioChunk, now: TimeInterval) {
        let captured = chunk.capturedAtUptime ?? now
        guard !chunk.samples.isEmpty, captured.isFinite else { return }
        if let last = samples[chunk.source], captured - last.measuredAt < 0.05 { return }
        let power = chunk.samples.reduce(0.0) { sum, value in
            let value = value.isFinite ? Double(value) : 0
            return sum + value * value
        } / Double(chunk.samples.count)
        samples[chunk.source] = Sample(decibels: power > 0 ? 10 * log10(power) : -120, measuredAt: captured)
    }
}
