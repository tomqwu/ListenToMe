import Foundation

/// Pure alignment of diarized speaker segments onto the OTHERS transcript lines. No I/O, no ML.
/// Diarization runs on the system-audio buffer and yields times relative to that buffer's sample 0;
/// the transcript carries capture-time stamps. `offset` bridges the two frames (see `label`).
public enum SpeakerLabeling {
    /// Assigns each OTHERS transcript line a stable "Speaker N" label by maximum time-overlap with
    /// the diarized speaker segments. `offset` is added to every diarized segment's time to convert
    /// buffer-relative time into the transcript's capture-time frame. Speakers are numbered by the
    /// capture-time of their first labeled appearance. Returns a map from transcript-line id to label;
    /// only OTHERS lines that overlap a segment are included (YOU lines and unmatched lines are absent).
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

    public static func label(transcript: [TranscriptSegment],
                             diarized: [DiarizedSegment],
                             offset: TimeInterval) -> [UUID: String] {
        // Shift diarized segments into capture-time and drop empty/degenerate ones.
        let shifted = diarized.compactMap { seg -> Shifted? in
            guard seg.duration > 0 else { return nil }
            let start = seg.start + offset
            return Shifted(speakerId: seg.speakerId, start: start, end: start + seg.duration)
        }
        guard !shifted.isEmpty else { return [:] }

        // For each OTHERS line with real timestamps, pick the segment with the greatest overlap;
        // ties resolve to the earliest segment (by its already-stable input order).
        var chosen: [Match] = []
        for line in transcript where line.source == .others && line.end > line.start {
            var bestIndex: Int?
            var bestOverlap: TimeInterval = 0
            for (index, seg) in shifted.enumerated() {
                let overlap = min(line.end, seg.end) - max(line.start, seg.start)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestIndex = index
                }
            }
            if let bestIndex {
                chosen.append(Match(lineStart: line.start, lineID: line.id,
                                    speakerId: shifted[bestIndex].speakerId))
            }
        }
        guard !chosen.isEmpty else { return [:] }

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

        var result: [UUID: String] = [:]
        for entry in chosen {
            result[entry.lineID] = labelForSpeaker[entry.speakerId]
        }
        return result
    }
}
