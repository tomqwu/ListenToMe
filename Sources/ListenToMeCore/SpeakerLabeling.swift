import Foundation

/// Pure alignment of diarized speaker segments onto the OTHERS transcript lines. No I/O, no ML.
/// Diarization runs on the system-audio buffer and yields times relative to that buffer's sample 0;
/// the transcript carries capture-time stamps. `offset` bridges the two frames (see `label`).
public enum SpeakerLabeling {
    /// The outcome of labeling: the per-transcript-line map plus the canonical speakerId→label map.
    /// `order` is the single source of truth for "Speaker N" numbering (by first appearance), so the
    /// transcript and the breakdown sheet can agree on which number means which diarized speaker.
    public struct Labeling: Sendable, Equatable {
        /// Transcript-line id → "Speaker N" for OTHERS lines that overlap a diarized speaker.
        public let lineLabels: [UUID: String]
        /// Diarized `speakerId` → its canonical "Speaker N" label (numbered by first appearance).
        public let order: [String: String]

        public init(lineLabels: [UUID: String], order: [String: String]) {
            self.lineLabels = lineLabels
            self.order = order
        }
    }

    /// A diarized segment shifted into capture-time.
    private struct Shifted {
        let speakerId: String
        let start: TimeInterval
        let end: TimeInterval
    }

    /// An OTHERS transcript line matched to a diarized speaker.
    private struct Match {
        let lineStart: TimeInterval
        let lineID: UUID
        let speakerId: String
    }

    /// Assigns each OTHERS transcript line a stable "Speaker N" label by maximum total time-overlap
    /// with the diarized speaker segments. `offset` is added to every diarized segment's time to
    /// convert buffer-relative time into the transcript's capture-time frame. For each line, overlap
    /// is summed *per speaker* across all that speaker's segments (so one utterance split around a
    /// pause isn't out-voted by a single longer segment from another speaker); the speaker with the
    /// greatest summed overlap wins (ties → the speaker whose earliest overlapping segment starts
    /// first, then speakerId). Speakers are numbered by the capture-time of their first labeled
    /// appearance. Only OTHERS lines that overlap a segment are labeled (YOU/unmatched lines absent).
    public static func label(transcript: [TranscriptSegment],
                             diarized: [DiarizedSegment],
                             offset: TimeInterval) -> Labeling {
        // Shift diarized segments into capture-time and drop empty/degenerate ones.
        let shifted = diarized.compactMap { seg -> Shifted? in
            guard seg.duration > 0 else { return nil }
            let start = seg.start + offset
            return Shifted(speakerId: seg.speakerId, start: start, end: start + seg.duration)
        }
        guard !shifted.isEmpty else { return Labeling(lineLabels: [:], order: [:]) }

        let chosen = matches(transcript: transcript, shifted: shifted)
        guard !chosen.isEmpty else { return Labeling(lineLabels: [:], order: [:]) }

        // Number speakers by the earliest line-start at which each first appears.
        var firstSeen: [String: TimeInterval] = [:]
        for entry in chosen {
            firstSeen[entry.speakerId] = min(firstSeen[entry.speakerId] ?? .infinity, entry.lineStart)
        }
        let ordering = firstSeen
            .sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .map(\.key)
        var labelForSpeaker: [String: String] = [:]
        for (index, speakerId) in ordering.enumerated() {
            labelForSpeaker[speakerId] = "Speaker \(index + 1)"
        }

        var lineLabels: [UUID: String] = [:]
        for entry in chosen {
            lineLabels[entry.lineID] = labelForSpeaker[entry.speakerId]
        }
        return Labeling(lineLabels: lineLabels, order: labelForSpeaker)
    }

    /// For each OTHERS line with real timestamps, sums overlap per speaker across all that speaker's
    /// shifted segments and picks the speaker with the greatest summed overlap. Ties break to the
    /// speaker whose earliest overlapping segment starts first, then by speakerId for determinism.
    private static func matches(transcript: [TranscriptSegment], shifted: [Shifted]) -> [Match] {
        var chosen: [Match] = []
        for line in transcript where line.source == .others && line.end > line.start {
            var totalOverlap: [String: TimeInterval] = [:]
            var earliestStart: [String: TimeInterval] = [:]
            for seg in shifted {
                let overlap = min(line.end, seg.end) - max(line.start, seg.start)
                guard overlap > 0 else { continue }
                totalOverlap[seg.speakerId, default: 0] += overlap
                earliestStart[seg.speakerId] = min(earliestStart[seg.speakerId] ?? .infinity, seg.start)
            }
            let winner = totalOverlap.max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                let lStart = earliestStart[lhs.key] ?? .infinity
                let rStart = earliestStart[rhs.key] ?? .infinity
                if lStart != rStart { return lStart > rStart }   // earlier start wins (is "greater")
                return lhs.key > rhs.key                          // then speakerId for determinism
            }
            if let winner {
                chosen.append(Match(lineStart: line.start, lineID: line.id, speakerId: winner.key))
            }
        }
        return chosen
    }
}
