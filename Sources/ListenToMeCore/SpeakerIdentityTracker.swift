import Foundation

public struct SpeakerIdentity: Sendable, Equatable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Reconciles full-buffer diarization passes by shared audio time, never by unstable model IDs.
/// Ambiguous splits/merges receive new identities rather than inheriting someone's edited name.
public struct SpeakerIdentityTracker: Sendable {
    private var previous: [DiarizedSegment] = []
    private var identities: [String: SpeakerIdentity] = [:]
    private var nextNumber = 1
    private let namespace: String
    private let prefix: String

    public init(namespace: String = UUID().uuidString, prefix: String = "Speaker") {
        self.namespace = namespace
        self.prefix = prefix
    }

    public mutating func rename(id: String, name: String) {
        identities[id]?.name = name
    }

    /// Reconciles a diarization pass against the previous one.
    ///
    /// `windowStart` supports incremental passes (issue #109): when a periodic pass re-analyzes only
    /// a trailing window of the buffer, matching considers just the part of the previous timeline
    /// that lies inside that window, and the history before it is preserved so a later full pass can
    /// still recognize speakers from earlier in the meeting. `windowStart <= 0` is a full pass and
    /// behaves exactly as before.
    public mutating func reconcile(_ segments: [DiarizedSegment],
                                   since windowStart: TimeInterval = 0) -> [String: SpeakerIdentity] {
        let valid = segments.filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 }
        let groups = Dictionary(grouping: valid, by: \.speakerId)
        // Split the retained timeline at the window boundary: `history` is kept verbatim, `inWindow`
        // is what this pass may match against.
        let history = windowStart > 0 ? SpeakerStats.clip(previous, endingAt: windowStart) : []
        let inWindow = windowStart > 0 ? previous.compactMap { segment -> DiarizedSegment? in
            let start = max(segment.start, windowStart)
            let duration = segment.start + segment.duration - start
            guard duration > 0 else { return nil }
            return DiarizedSegment(speakerId: segment.speakerId, start: start, duration: duration)
        } : previous
        let previousEnd = inWindow.map { $0.start + $0.duration }.max() ?? 0
        var overlaps: [String: [String: Double]] = [:]
        var oldTotals: [String: Double] = [:]
        for old in inWindow { oldTotals[old.speakerId, default: 0] += old.duration }
        for current in valid {
            for old in inWindow {
                let duration = min(current.start + current.duration, old.start + old.duration)
                    - max(current.start, old.start)
                if duration > 0 { overlaps[current.speakerId, default: [:]][old.speakerId, default: 0] += duration }
            }
        }
        var mapping: [String: SpeakerIdentity] = [:]
        var used = Set<String>()
        let ordered = groups.keys.sorted {
            let left = groups[$0]!.map(\.start).min()!
            let right = groups[$1]!.map(\.start).min()!
            return left == right ? $0 < $1 : left < right
        }
        for raw in ordered {
            let sharedDuration = groups[raw]!.reduce(0.0) {
                $0 + max(0, min($1.start + $1.duration, previousEnd) - $1.start)
            }
            let candidates = (overlaps[raw] ?? [:]).sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            if let best = candidates.first,
               best.value > sharedDuration * 0.6,
               best.value > (oldTotals[best.key] ?? 0) * 0.6,
               !used.contains(best.key), let identity = identities[best.key] {
                mapping[raw] = identity
                used.insert(best.key)
            } else {
                let identity = SpeakerIdentity(id: "\(namespace)-\(nextNumber)", name: "\(prefix) \(nextNumber)")
                identities[identity.id] = identity
                mapping[raw] = identity
                nextNumber += 1
            }
        }
        previous = history + valid.compactMap { segment in
            guard let identity = mapping[segment.speakerId] else { return nil }
            return DiarizedSegment(speakerId: identity.id, start: segment.start, duration: segment.duration)
        }
        return mapping
    }
}
