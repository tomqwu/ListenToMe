import Foundation

/// One diarization pass over a window of audio: its segments, plus one voice embedding per diarized
/// cluster (keyed by the segments' `speakerId`). The embeddings are what lets `SpeakerIdentityTracker`
/// recognize a voice that was silent through the windows' shared audio (issue #171). A diarizer that
/// exposes no embeddings leaves `embeddings` empty, and identities are carried by shared time alone.
public struct DiarizedWindow: Sendable, Equatable {
    public let segments: [DiarizedSegment]
    public let embeddings: [String: [Float]]

    public init(segments: [DiarizedSegment], embeddings: [String: [Float]] = [:]) {
        self.segments = segments
        self.embeddings = embeddings
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
    /// Cosine similarity at or above which a cluster may be the same person as an identity. FluidAudio's
    /// own clustering keeps two clusters apart below about 0.82 (its AHC threshold of 0.6 Euclidean
    /// on unit embeddings), so 0.75 accepts the same voice heard in another window while staying
    /// above the similarity typical of two different people.
    public static let similarityThreshold = 0.75
    /// Two candidate identities within this similarity of each other are too close to call by voice;
    /// shared audio time decides between them when it can.
    public static let ambiguityMargin = 0.05
    /// A cluster with less speech than this gives too noisy an embedding to update a voiceprint.
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

    /// Matches clusters to identities by voice, one to one: the most similar pair at or above
    /// `threshold` is taken first, then the next pair whose cluster and identity are both still free.
    /// When a cluster's pick is within `margin` of the identity `preferred` names for it (its shared-time
    /// match), and that identity is free and also above the threshold, the voices are too close to call
    /// and the shared-time match wins. Ties break on identity id, then cluster id, so results are
    /// deterministic. Returns cluster id → identity id; unmatched clusters are left out.
    public static func match(clusters: [String: [Float]],
                             voiceprints: [String: SpeakerVoiceprint],
                             preferred: [String: String] = [:],
                             threshold: Double = similarityThreshold,
                             margin: Double = ambiguityMargin) -> [String: String] {
        var similarity: [String: [String: Double]] = [:]
        var pairs: [Candidate] = []
        for (cluster, embedding) in clusters {
            // Centroids are already unit length, so each cluster is normalized once and dotted.
            guard let unit = normalized(embedding) else { continue }
            for (identity, voiceprint) in voiceprints where voiceprint.centroid.count == unit.count {
                let score = dot(unit, voiceprint.centroid)
                guard score >= threshold else { continue }
                similarity[cluster, default: [:]][identity] = score
                pairs.append(Candidate(cluster: cluster, identity: identity, score: score))
            }
        }
        pairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.identity != $1.identity ? $0.identity < $1.identity : $0.cluster < $1.cluster
        }
        var result: [String: String] = [:]
        var taken = Set<String>()
        for pair in pairs where result[pair.cluster] == nil && !taken.contains(pair.identity) {
            var chosen = pair.identity
            if let timed = preferred[pair.cluster], timed != chosen, !taken.contains(timed),
               let timedScore = similarity[pair.cluster]?[timed], pair.score - timedScore < margin {
                chosen = timed
            }
            result[pair.cluster] = chosen
            taken.insert(chosen)
        }
        return result
    }
}
