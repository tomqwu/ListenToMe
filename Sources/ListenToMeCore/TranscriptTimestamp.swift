import Foundation

/// The one place transcript times are judged and written, shared by Save to folder (`MarkdownVault`)
/// and every export format (`SessionExporter`), so a note and an export never disagree.
///
/// Only some engines report where a line sits in the recording: the iOS live recorder and Apple Watch
/// files (the recognizer's audio range, cumulative across resumed recordings) and WhisperKit on macOS.
/// Apple's engines on macOS report `0…0` until issue #68 lands; such lines carry no time at all, and no
/// time is ever estimated for them.
public enum TranscriptTimestamp {
    /// True when the line carries a time from its engine.
    public static func isTimed(_ segment: TranscriptSegment) -> Bool {
        segment.start > 0 || segment.end > 0
    }

    /// True when at least one line of the conversation carries a time.
    public static func hasTimes(_ segments: [TranscriptSegment]) -> Bool {
        segments.contains(where: isTimed)
    }

    /// `12:05`, or `1:02:05` past an hour. Seconds are truncated, so a line never appears to start later
    /// than it did.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// `01:02:05,250` (SRT, `separator: ","`) or `01:02:05.250` (WebVTT). Hours are always written, so
    /// recordings longer than an hour (or than 99 minutes) stay valid. Rounded to the millisecond.
    public static func subtitle(_ seconds: TimeInterval, separator: Character) -> String {
        let millis = max(0, Int((seconds * 1000).rounded()))
        let hours = millis / 3_600_000, minutes = millis % 3_600_000 / 60_000
        let secs = millis % 60_000 / 1000, rest = millis % 1000
        return String(format: "%02d:%02d:%02d", hours, minutes, secs) + String(separator)
            + String(format: "%03d", rest)
    }

    /// The span from the first line's start to the last line's end, or nil without times.
    public static func duration(of segments: [TranscriptSegment]) -> TimeInterval? {
        let timed = segments.filter(isTimed)
        guard let first = timed.map(\.start).min(), let last = timed.map(\.end).max(),
              last > first else { return nil }
        return last - first
    }
}
