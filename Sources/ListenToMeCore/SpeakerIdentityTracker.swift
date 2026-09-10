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

    public mutating func reconcile(_ segments: [DiarizedSegment]) -> [String: SpeakerIdentity] {
        let valid = segments.filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 }
        let groups = Dictionary(grouping: valid, by: \.speakerId)
        let previousEnd = previous.map { $0.start + $0.duration }.max() ?? 0
        var overlaps: [String: [String: Double]] = [:]
        var oldTotals: [String: Double] = [:]
        for old in previous { oldTotals[old.speakerId, default: 0] += old.duration }
        for current in valid {
            for old in previous {
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
        previous = valid.compactMap { segment in
            guard let identity = mapping[segment.speakerId] else { return nil }
            return DiarizedSegment(speakerId: identity.id, start: segment.start, duration: segment.duration)
        }
        return mapping
    }
}
