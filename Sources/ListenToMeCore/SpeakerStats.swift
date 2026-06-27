import Foundation

/// One stretch of speech attributed to a single diarized speaker. Produced by an App-side diarizer
/// (FluidAudio) and mapped onto this pure value so Core can aggregate without an ML dependency.
public struct DiarizedSegment: Sendable, Equatable {
    public let speakerId: String
    public let start: TimeInterval
    public let duration: TimeInterval

    public init(speakerId: String, start: TimeInterval, duration: TimeInterval) {
        self.speakerId = speakerId
        self.start = start
        self.duration = duration
    }
}

/// Aggregate talk time for one speaker: total seconds and the fraction of all detected speech.
public struct SpeakerTalkTime: Sendable, Equatable {
    public let id: String
    public let total: TimeInterval
    public let fraction: Double

    public init(id: String, total: TimeInterval, fraction: Double) {
        self.id = id
        self.total = total
        self.fraction = fraction
    }
}

/// A whole-session breakdown of who spoke and for how long in the diarized channel.
public struct SpeakerSummary: Sendable, Equatable {
    public let speakerCount: Int
    public let totalSpeech: TimeInterval
    public let speakers: [SpeakerTalkTime]

    public init(speakerCount: Int, totalSpeech: TimeInterval, speakers: [SpeakerTalkTime]) {
        self.speakerCount = speakerCount
        self.totalSpeech = totalSpeech
        self.speakers = speakers
    }
}

/// Pure aggregation of diarized segments into per-speaker talk-time shares. No I/O, no ML.
public enum SpeakerStats {
    /// Sums durations per `speakerId` (ignoring zero/negative-duration segments), returning speakers
    /// sorted by total talk time descending. `fraction = total / totalSpeech` (0 when no speech);
    /// `speakerCount` counts distinct speakers with positive talk time.
    public static func summarize(_ segments: [DiarizedSegment]) -> SpeakerSummary {
        var totals: [String: TimeInterval] = [:]
        for segment in segments where segment.duration > 0 {
            totals[segment.speakerId, default: 0] += segment.duration
        }
        let totalSpeech = totals.values.reduce(0, +)
        let speakers = totals
            .map { SpeakerTalkTime(id: $0.key, total: $0.value,
                                   fraction: totalSpeech > 0 ? $0.value / totalSpeech : 0) }
            // Tie-break on id so the ordering is stable across runs.
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.id < $1.id }
        return SpeakerSummary(speakerCount: speakers.count, totalSpeech: totalSpeech, speakers: speakers)
    }
}
