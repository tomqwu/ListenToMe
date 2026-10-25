import Foundation

/// Chooses among already-filtered meetings (no all-day, declined, free or cancelled entries).
public enum MeetingSelection {
    public static func currentOrNextIndex(in times: [(start: Date?, end: Date?)], now: Date) -> Int? {
        let current = times.indices.filter {
            guard let start = times[$0].start, let end = times[$0].end else { return false }
            return start <= now && now < end
        }.max { (times[$0].start ?? .distantPast) < (times[$1].start ?? .distantPast) }
        if let current { return current }
        return times.indices.filter { (times[$0].start ?? .distantPast) > now }
            .min { (times[$0].start ?? .distantFuture) < (times[$1].start ?? .distantFuture) }
    }
}
