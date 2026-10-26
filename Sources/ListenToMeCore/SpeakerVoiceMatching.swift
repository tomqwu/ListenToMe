import Foundation

/// One diarization pass over a window of audio: its segments, plus one voice embedding per diarized
/// cluster (keyed by the segments' `speakerId`). The embeddings are what lets `SpeakerIdentityTracker`
/// recognize a voice that was silent through the windows' shared audio (issue #171). A diarizer that
/// exposes recording-scoped stable slots uses `stableSpeakerIDScope` instead. Legacy results with
/// neither embeddings nor a stable scope carry identities by shared time alone.
public struct DiarizedWindow: Sendable, Equatable {
    public let segments: [DiarizedSegment]
    public let embeddings: [String: [Float]]
    /// End-to-end streaming slots remain stable only within this model epoch. A reset must use a
    /// new scope so reused slot numbers cannot inherit another person's identity or edited name.
    public let stableSpeakerIDScope: String?
    /// Confirmed model time, relative to the supplied window. Nil retains the legacy whole-window
    /// splice policy; streaming consumers must preserve labels beyond their delayed output horizon.
    public let analyzedThrough: TimeInterval?

    public init(segments: [DiarizedSegment], embeddings: [String: [Float]] = [:],
                stableSpeakerIDScope: String? = nil, analyzedThrough: TimeInterval? = nil) {
        self.segments = segments
        self.embeddings = embeddings
        self.stableSpeakerIDScope = stableSpeakerIDScope
        self.analyzedThrough = analyzedThrough
    }
}

/// The running voice of one speaker identity in this recording: the L2-normalized centroid of the
/// cluster embeddings matched to it, weighted by how much speech each one covered.
///
/// Held in memory for one recording only and never saved: remembering voices across recordings would be
/// cross-run recognition, a separate privacy decision.
public struct SpeakerVoiceprint: Sendable, Equatable {
    /// Unit-length mean embedding.
    public private(set) var centroid: [Float]
    /// Seconds of speech folded in, capped at `SpeakerVoiceMatching.maximumWeight`.
    public private(set) var weight: TimeInterval

    /// `nil` for an embedding that cannot describe a voice (empty, zero or non-finite) or no speech.
    public init?(embedding: [Float], seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0, let unit = SpeakerVoiceMatching.normalized(embedding) else { return nil }
        centroid = unit
        weight = min(seconds, SpeakerVoiceMatching.maximumWeight)
    }

    /// Folds one more cluster embedding in. Ignores embeddings of another dimension or no speech. The
    /// weight cap keeps the voice adapting to a change of room or microphone late in a long meeting.
    public mutating func absorb(_ embedding: [Float], seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0, embedding.count == centroid.count,
              let unit = SpeakerVoiceMatching.normalized(embedding) else { return }
        let total = weight + seconds
        let mixed = zip(centroid, unit).map { old, new in
            Float((Double(old) * weight + Double(new) * seconds) / total)
        }
        guard let renormalized = SpeakerVoiceMatching.normalized(mixed) else { return }
        centroid = renormalized
        weight = min(total, SpeakerVoiceMatching.maximumWeight)
    }
}

/// Pure voice matching between a new window's diarized clusters and the identities a recording already
/// has (issue #171). No I/O and no ML: the embeddings come from the diarizer.
public enum SpeakerVoiceMatching {
    /// Cosine similarity at or above which a cluster may be the same person as an identity: the line
    /// FluidAudio's own clustering draws between one speaker and two (its AHC threshold of 0.6 Euclidean
    /// on unit embeddings is cosine 1 − 0.6² / 2 = 0.82). Voices the diarizer would keep apart within
    /// one window are never merged across windows; a returning voice below it becomes a new speaker,
    /// as it did before voice matching.
    public static let similarityThreshold = 0.82
    /// A cluster with less speech than this gives too noisy an embedding to claim an identity by voice
    /// or to update a voiceprint.
    public static let minimumSeconds: TimeInterval = 2
    /// Cap on a voiceprint's weight, in seconds of speech.
    public static let maximumWeight: TimeInterval = 300
    /// A voiceprint built from less speech than this is still unsettled: it keeps learning from
    /// shared-time matches even when their voice disagrees with it. A settled one learns only from
    /// clusters that sound like it.
    public static let settledWeight: TimeInterval = 20

    /// Unit-length copy of `vector`, or `nil` when it is empty, zero or not finite.
    public static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = vector.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
        guard norm > 0, norm.isFinite else { return nil }
        return vector.map { Float(Double($0) / norm) }
    }

    /// Cosine similarity in -1...1, or `nil` for vectors of different dimensions or no direction.
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, let left = normalized(lhs), let right = normalized(rhs) else { return nil }
        return dot(left, right)
    }

    /// Dot product of two vectors of the same length (the cosine of two unit vectors).
    private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var sum: Float = 0
        lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in
                for index in 0..<min(left.count, right.count) { sum += left[index] * right[index] }
            }
        }
        return Double(sum)
    }

    /// One cluster–identity pairing above the threshold.
    private struct Candidate {
        let cluster: String
        let identity: String
        let score: Double
    }

    /// Matches clusters to identities by voice, one to one, over all pairs at once: the most similar
    /// pair at or above `threshold` is taken first, then the next pair whose cluster and identity are
    /// both still free. Ties break on identity id, then cluster id, so results are deterministic.
    /// Callers pass only the clusters and identities shared audio time has not already paired.
    /// Returns cluster id → identity id; unmatched clusters are left out.
    public static func match(clusters: [String: [Float]],
                             voiceprints: [String: SpeakerVoiceprint],
                             threshold: Double = similarityThreshold) -> [String: String] {
        var pairs: [Candidate] = []
        for (cluster, embedding) in clusters {
            // Centroids are already unit length, so each cluster is normalized once and dotted.
            guard let unit = normalized(embedding) else { continue }
            for (identity, voiceprint) in voiceprints where voiceprint.centroid.count == unit.count {
                let score = dot(unit, voiceprint.centroid)
                if score >= threshold { pairs.append(Candidate(cluster: cluster, identity: identity, score: score)) }
            }
        }
        pairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.identity != $1.identity ? $0.identity < $1.identity : $0.cluster < $1.cluster
        }
        var result: [String: String] = [:]
        var taken = Set<String>()
        for pair in pairs where result[pair.cluster] == nil && !taken.contains(pair.identity) {
            result[pair.cluster] = pair.identity
            taken.insert(pair.identity)
        }
        return result
    }
}
