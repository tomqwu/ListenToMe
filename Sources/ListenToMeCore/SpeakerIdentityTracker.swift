import Foundation

public struct SpeakerIdentity: Sendable, Equatable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Reconciles diarization passes into stable identities, never by unstable model IDs: by voice first
/// (each identity's running embedding, issue #171), then by shared audio time. Ambiguous splits and
/// merges receive new identities rather than inheriting someone's edited name.
public struct SpeakerIdentityTracker: Sendable {
    private var previous: [DiarizedSegment] = []
    private var identities: [String: SpeakerIdentity] = [:]
    /// Identity id → running voice embedding, for this recording only (issue #171). Never persisted.
    private var voiceprints: [String: SpeakerVoiceprint] = [:]
    private var nextNumber = 1
    private let namespace: String
    private let prefix: String

    /// `firstNumber` lets a later recording in the same conversation continue the numbering, so its
    /// new voices never reuse a "Speaker N" an earlier recording already put on the transcript.
    public init(namespace: String = UUID().uuidString, prefix: String = "Speaker", firstNumber: Int = 1) {
        self.namespace = namespace
        self.prefix = prefix
        self.nextNumber = max(1, firstNumber)
    }

    public mutating func rename(id: String, name: String) {
        identities[id]?.name = name
    }

    /// How many identities have a voiceprint, for tests and diagnostics.
    public var voiceprintCount: Int { voiceprints.count }

    /// The part of `segments` at or after `windowStart` (the whole timeline for a full pass).
    private static func trimmed(_ segments: [DiarizedSegment],
                                from windowStart: TimeInterval) -> [DiarizedSegment] {
        guard windowStart > 0 else { return segments }
        return segments.compactMap { segment in
            let start = max(segment.start, windowStart)
            let duration = segment.start + segment.duration - start
            guard duration > 0 else { return nil }
            return DiarizedSegment(speakerId: segment.speakerId, start: start, duration: duration)
        }
    }

    /// Shared time between each current speakerId and each previous identity.
    private static func overlapTable(current: [DiarizedSegment],
                                     previous: [DiarizedSegment]) -> [String: [String: Double]] {
        var overlaps: [String: [String: Double]] = [:]
        for segment in current {
            for old in previous {
                let shared = min(segment.start + segment.duration, old.start + old.duration)
                    - max(segment.start, old.start)
                if shared > 0 { overlaps[segment.speakerId, default: [:]][old.speakerId, default: 0] += shared }
            }
        }
        return overlaps
    }

    /// Reconciles a diarization pass against the previous ones.
    ///
    /// `windowStart` supports incremental passes (issue #109): when a periodic pass re-analyzes only
    /// a trailing window of the buffer, matching considers just the part of the previous timeline
    /// that lies inside that window, and the history before it is preserved so a later full pass can
    /// still recognize speakers from earlier in the meeting. `windowStart <= 0` is a full pass.
    ///
    /// `embeddings` (one voice embedding per diarized `speakerId`, issue #171) are matched first,
    /// against each identity's running voiceprint (`SpeakerVoiceMatching.match`, one to one), so a
    /// person who was silent through the shared audio keeps their identity and edited name. Clusters
    /// no voice matches fall back to the shared-time rule; without embeddings that rule is all there is.
    public mutating func reconcile(_ segments: [DiarizedSegment],
                                   since windowStart: TimeInterval = 0,
                                   embeddings: [String: [Float]] = [:]) -> [String: SpeakerIdentity] {
        let valid = segments.filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 }
        let groups = Dictionary(grouping: valid, by: \.speakerId)
        let timed = timedMatches(valid: valid, groups: groups, windowStart: windowStart)
        let voiced = SpeakerVoiceMatching.match(clusters: embeddings.filter { groups[$0.key] != nil },
                                                voiceprints: voiceprints, preferred: timed)
        var mapping: [String: SpeakerIdentity] = [:]
        var used = Set(voiced.values)
        let ordered = groups.keys.sorted {
            let left = groups[$0]!.map(\.start).min()!
            let right = groups[$1]!.map(\.start).min()!
            return left == right ? $0 < $1 : left < right
        }
        for raw in ordered {
            if let id = voiced[raw], let identity = identities[id] {
                mapping[raw] = identity
            } else if let id = timed[raw], !used.contains(id), let identity = identities[id] {
                mapping[raw] = identity
                used.insert(id)
            } else {
                let identity = SpeakerIdentity(id: "\(namespace)-\(nextNumber)", name: "\(prefix) \(nextNumber)")
                identities[identity.id] = identity
                mapping[raw] = identity
                nextNumber += 1
            }
        }
        learnVoices(mapping: mapping, groups: groups, embeddings: embeddings)
        let mapped: [DiarizedSegment] = valid.compactMap { segment in
            guard let identity = mapping[segment.speakerId] else { return nil }
            return DiarizedSegment(speakerId: identity.id, start: segment.start, duration: segment.duration)
        }
        // A full pass replaces the timeline; a windowed pass splices, keeping what it did not hear.
        previous = windowStart > 0
            ? SpeakerStats.splice(history: previous, window: mapped, windowStart: windowStart)
            : mapped
        return mapping
    }

    /// Each cluster's confident shared-time match: the previous identity it shares the most audio
    /// with, when that covers over 60% of both the cluster's audio inside the previous timeline and
    /// the identity's audio in the window. Ambiguous splits and merges have none.
    private func timedMatches(valid: [DiarizedSegment], groups: [String: [DiarizedSegment]],
                              windowStart: TimeInterval) -> [String: String] {
        // Only the part of the retained timeline inside the window may be matched against; what lies
        // before it is history this pass knows nothing about (it is preserved by the splice).
        let inWindow = Self.trimmed(previous, from: windowStart)
        let previousEnd = inWindow.map { $0.start + $0.duration }.max() ?? 0
        let overlaps = Self.overlapTable(current: valid, previous: inWindow)
        var oldTotals: [String: Double] = [:]
        for old in inWindow { oldTotals[old.speakerId, default: 0] += old.duration }
        var result: [String: String] = [:]
        for (raw, group) in groups {
            let sharedDuration = group.reduce(0.0) {
                $0 + max(0, min($1.start + $1.duration, previousEnd) - $1.start)
            }
            let best = (overlaps[raw] ?? [:]).max {
                $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value
            }
            if let best, best.value > sharedDuration * 0.6, best.value > (oldTotals[best.key] ?? 0) * 0.6 {
                result[raw] = best.key
            }
        }
        return result
    }

    /// Folds each mapped cluster's embedding into its identity's voiceprint. A cluster with too little
    /// speech is skipped, and so is a shared-time match whose voice disagrees with a settled voiceprint,
    /// so one muddled window cannot drag a voice toward someone else's.
    private mutating func learnVoices(mapping: [String: SpeakerIdentity], groups: [String: [DiarizedSegment]],
                                      embeddings: [String: [Float]]) {
        for (raw, identity) in mapping {
            guard let embedding = embeddings[raw] else { continue }
            let seconds = groups[raw]?.reduce(0.0) { $0 + $1.duration } ?? 0
            guard seconds >= SpeakerVoiceMatching.minimumSeconds else { continue }
            guard var voiceprint = voiceprints[identity.id] else {
                voiceprints[identity.id] = SpeakerVoiceprint(embedding: embedding, seconds: seconds)
                continue
            }
            let similarity = SpeakerVoiceMatching.cosineSimilarity(embedding, voiceprint.centroid) ?? -1
            guard similarity >= SpeakerVoiceMatching.similarityThreshold
                    || voiceprint.weight < SpeakerVoiceMatching.settledWeight else { continue }
            voiceprint.absorb(embedding, seconds: seconds)
            voiceprints[identity.id] = voiceprint
        }
    }
}
