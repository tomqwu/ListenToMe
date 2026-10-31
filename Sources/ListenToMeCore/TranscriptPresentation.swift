import Foundation

/// A display/export projection; canonical arrival order remains authoritative for capture ledgers.
public enum TranscriptPresentation {
    public static func ordered(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        orderedIndices(segments).map { segments[$0] }
    }

    /// The same display projection with canonical positions retained, including duplicate restored IDs.
    public static func orderedIndices(_ segments: [TranscriptSegment]) -> [Int] {
        var offset = 0
        return runs(segments).flatMap { run -> [Int] in
            let indices = Array(offset..<(offset + run.count))
            offset += run.count
            guard run.first?.recordingID != nil else { return indices }
            var result: [Int] = [], timed: [Int] = []
            func flush() {
                result += timed.sorted { (segments[$0].start, $0) < (segments[$1].start, $1) }
                timed.removeAll(keepingCapacity: true)
            }
            for index in indices {
                let segment = segments[index]
                if segment.start.isFinite && segment.end.isFinite && segment.start >= 0
                    && segment.end >= segment.start && TranscriptTimestamp.isTimed(segment) {
                    timed.append(index)
                } else {
                    flush()
                    result.append(index)
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
