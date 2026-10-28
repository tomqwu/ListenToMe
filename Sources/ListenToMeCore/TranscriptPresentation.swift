import Foundation

/// A display/export projection; canonical arrival order remains authoritative for capture ledgers.
public enum TranscriptPresentation {
    public static func ordered(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        runs(segments).flatMap { run -> [TranscriptSegment] in
            guard run.first?.recordingID != nil else { return run }
            var result: [TranscriptSegment] = [], timed: [TranscriptSegment] = []
            func flush() {
                result += timed.enumerated().sorted {
                    ($0.element.start, $0.offset) < ($1.element.start, $1.offset)
                }.map(\.element)
                timed.removeAll(keepingCapacity: true)
            }
            for segment in run {
                if segment.start.isFinite && segment.end.isFinite && segment.start >= 0
                    && segment.end >= segment.start && TranscriptTimestamp.isTimed(segment) {
                    timed.append(segment)
                } else {
                    flush()
                    result.append(segment)
                }
            }
            flush()
            return result
        }
    }

    /// Only explicit IDs delimit new recordings. Nil-ID legacy blocks retain their arrival order.
    static func runs(_ segments: [TranscriptSegment]) -> [[TranscriptSegment]] {
        var result: [[TranscriptSegment]] = []
        for segment in segments {
            if result.isEmpty || result.last?.last?.recordingID != segment.recordingID {
                result.append([])
            }
            result[result.count - 1].append(segment)
        }
        return result
    }
}
