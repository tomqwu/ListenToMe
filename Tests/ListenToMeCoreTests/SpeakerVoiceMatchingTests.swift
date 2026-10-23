import XCTest
@testable import ListenToMeCore

/// Voice-embedding identity matching across analysis windows (issue #171).
final class SpeakerVoiceMatchingTests: XCTestCase {
    private func segment(_ id: String, _ start: Double, _ duration: Double) -> DiarizedSegment {
        DiarizedSegment(speakerId: id, start: start, duration: duration)
    }

    /// A unit vector in the plane of the first two axes, `degrees` from the first axis. Two of these
    /// have cosine similarity cos(difference), which makes threshold edges exact.
    private func voice(_ degrees: Double, dimensions: Int = 4) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        vector[0] = Float(cos(degrees * .pi / 180))
        vector[1] = Float(sin(degrees * .pi / 180))
        return vector
    }

    private func voiceprint(_ degrees: Double, seconds: TimeInterval = 60) -> SpeakerVoiceprint {
        SpeakerVoiceprint(embedding: voice(degrees), seconds: seconds)!
    }

    // MARK: Vector math

    func testCosineSimilarityAndNormalization() throws {
        XCTAssertEqual(try XCTUnwrap(SpeakerVoiceMatching.cosineSimilarity([1, 0], [3, 0])), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SpeakerVoiceMatching.cosineSimilarity([1, 0], [0, 2])), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SpeakerVoiceMatching.cosineSimilarity([1, 0], [-1, 0])), -1, accuracy: 1e-9)
        XCTAssertNil(SpeakerVoiceMatching.cosineSimilarity([1, 0], [1, 0, 0]))
        XCTAssertNil(SpeakerVoiceMatching.cosineSimilarity([0, 0], [1, 0]))
        XCTAssertNil(SpeakerVoiceMatching.cosineSimilarity([.nan, 1], [1, 0]))
        XCTAssertNil(SpeakerVoiceMatching.normalized([]))
        XCTAssertNil(SpeakerVoiceMatching.normalized([.infinity, 0]))
        let unit = try XCTUnwrap(SpeakerVoiceMatching.normalized([3, 4]))
        XCTAssertEqual(unit[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(unit[1], 0.8, accuracy: 1e-6)
    }

    func testVoiceprintRejectsUnusableInputAndAveragesBySpeech() throws {
        XCTAssertNil(SpeakerVoiceprint(embedding: [0, 0], seconds: 5))
        XCTAssertNil(SpeakerVoiceprint(embedding: [1, 0], seconds: 0))
        XCTAssertNil(SpeakerVoiceprint(embedding: [1, 0], seconds: .nan))
        var voiceprint = try XCTUnwrap(SpeakerVoiceprint(embedding: [2, 0], seconds: 10))
        XCTAssertEqual(voiceprint.centroid, [1, 0])
        // Equal speech pulls the centroid halfway, and it stays unit length.
        voiceprint.absorb([0, 5], seconds: 10)
        XCTAssertEqual(voiceprint.centroid[0], Float(0.5.squareRoot()), accuracy: 1e-6)
        XCTAssertEqual(voiceprint.centroid[1], Float(0.5.squareRoot()), accuracy: 1e-6)
        XCTAssertEqual(voiceprint.weight, 20)
        // Wrong dimension, no speech or a zero vector change nothing.
        let before = voiceprint
        voiceprint.absorb([1, 0, 0], seconds: 10)
        voiceprint.absorb([1, 0], seconds: 0)
        voiceprint.absorb([0, 0], seconds: 10)
        voiceprint.absorb([1, -1], seconds: .infinity)
        XCTAssertEqual(voiceprint, before)
        // An exactly opposite voice cancels to zero, which cannot be normalized: kept as it was.
        var opposite = try XCTUnwrap(SpeakerVoiceprint(embedding: [1, 0], seconds: 10))
        opposite.absorb([-1, 0], seconds: 10)
        XCTAssertEqual(opposite.centroid, [1, 0])
    }

    func testVoiceprintWeightIsCappedSoTheVoiceKeepsAdapting() throws {
        var voiceprint = try XCTUnwrap(SpeakerVoiceprint(embedding: voice(0), seconds: 10_000))
        XCTAssertEqual(voiceprint.weight, SpeakerVoiceMatching.maximumWeight)
        voiceprint.absorb(voice(90), seconds: SpeakerVoiceMatching.maximumWeight)
        XCTAssertEqual(voiceprint.weight, SpeakerVoiceMatching.maximumWeight)
        XCTAssertEqual(try XCTUnwrap(SpeakerVoiceMatching.cosineSimilarity(voiceprint.centroid, voice(45))),
                       1, accuracy: 1e-5)
    }

    // MARK: Matching

    func testThresholdEdges() {
        let prints = ["alice": voiceprint(0)]
        let atThreshold = acos(SpeakerVoiceMatching.similarityThreshold) * 180 / .pi
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": voice(atThreshold - 0.01)], voiceprints: prints),
                       ["S1": "alice"])
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": voice(atThreshold + 0.01)], voiceprints: prints),
                       [:])
        // An explicit threshold is honoured exactly, inclusive.
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": [1, 0, 0, 0]], voiceprints: prints, threshold: 1),
                       ["S1": "alice"])
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": voice(60)], voiceprints: prints, threshold: 0.6),
                       [:])
        // Embeddings of another dimension never match.
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": [1, 0]], voiceprints: prints), [:])
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: [:], voiceprints: prints), [:])
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["S1": voice(0)], voiceprints: [:]), [:])
    }

    func testAssignmentIsOneToOne() {
        // Both clusters sound most like Alice; only the closer one gets her, the other takes its next
        // choice above the threshold, and a third with no free match stays unmatched.
        let prints = ["alice": voiceprint(0), "bob": voiceprint(30)]
        let result = SpeakerVoiceMatching.match(
            clusters: ["S1": voice(5), "S2": voice(12), "S3": voice(2)], voiceprints: prints)
        XCTAssertEqual(result["S3"], "alice")
        XCTAssertEqual(result["S2"], "bob")
        XCTAssertNil(result["S1"])
        XCTAssertEqual(Set(result.values).count, result.count)
    }

    func testTwoSimilarVoicesAreToldApartWhenBothSpeak() {
        // Alice and Beth sound alike (cosine 0.97), but each window cluster is still nearer its own.
        let prints = ["alice": voiceprint(0), "beth": voiceprint(14)]
        let result = SpeakerVoiceMatching.match(clusters: ["S1": voice(12), "S2": voice(1)], voiceprints: prints)
        XCTAssertEqual(result, ["S1": "beth", "S2": "alice"])
    }

    func testAssignmentIsGlobalNotPerCluster() {
        // Review of #207: c1 is nearer I (0.883) than J (0.848); c2 only fits J (0.875). Taking the
        // strongest pairs first gives c1 → I and c2 → J, so nobody is left out.
        let prints = ["I": voiceprint(0), "J": voiceprint(60)]
        XCTAssertEqual(SpeakerVoiceMatching.match(clusters: ["c1": voice(28), "c2": voice(89)], voiceprints: prints),
                       ["c1": "I", "c2": "J"])
    }

    // MARK: Tracker

    func testSilentSpeakerReturnsWithTheirIdentityAndEditedName() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("S1", 0, 40), segment("S2", 40, 40)],
                                      embeddings: ["S1": voice(0), "S2": voice(90)])
        let alice = first["S1"]!
        tracker.rename(id: alice.id, name: "Alice")
        // Bob talks alone for minutes; Alice is silent through every overlap. (The first window shares
        // too little of Bob's audio for shared time, so his voice carries him.)
        _ = tracker.reconcile([segment("S1", 60, 140)], since: 20, embeddings: ["S1": voice(88)])
        _ = tracker.reconcile([segment("S1", 140, 200)], since: 140, embeddings: ["S1": voice(91)])
        // She speaks again in a window that shares no audio with anything she said.
        let back = tracker.reconcile([segment("S2", 280, 60), segment("S1", 360, 40)], since: 280,
                                     embeddings: ["S1": voice(3), "S2": voice(89)])
        XCTAssertEqual(back["S1"]?.id, alice.id)
        XCTAssertEqual(back["S1"]?.name, "Alice")
        XCTAssertEqual(back["S2"]?.id, first["S2"]?.id)
        XCTAssertEqual(tracker.voiceprintCount, 2)
    }

    func testWithoutEmbeddingsTheSilentSpeakerWouldBeANewSpeaker() {
        // The gap #171 closes: by shared time alone, a returning voice is a stranger.
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("S1", 0, 40), segment("S2", 40, 40)])
        _ = tracker.reconcile([segment("S1", 60, 200)], since: 20)
        let back = tracker.reconcile([segment("S1", 360, 40)], since: 340)
        XCTAssertFalse(first.values.contains { $0.id == back["S1"]?.id })
        XCTAssertEqual(tracker.voiceprintCount, 0)
    }

    func testUnfamiliarVoiceBecomesANewSpeaker() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let alice = tracker.reconcile([segment("S1", 0, 30)], embeddings: ["S1": voice(0)])["S1"]!
        // An embedding for a cluster with no speech in the window is ignored, even if it sounds like Alice.
        let next = tracker.reconcile([segment("S1", 100, 30)], since: 100,
                                     embeddings: ["S1": voice(60), "ghost": voice(0)])
        XCTAssertNotEqual(next["S1"]?.id, alice.id)
        XCTAssertEqual(next["S1"]?.name, "Speaker 2")
        XCTAssertNil(next["ghost"])
    }

    func testTwoClustersThatSoundAlikeNeverShareOneIdentity() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let alice = tracker.reconcile([segment("S1", 0, 30)], embeddings: ["S1": voice(0)])["S1"]!
        // A later window splits into two clusters that both sound like Alice: one keeps her, the other
        // is someone new rather than a second "Alice".
        let split = tracker.reconcile([segment("S1", 200, 20), segment("S2", 220, 20)], since: 200,
                                      embeddings: ["S1": voice(2), "S2": voice(9)])
        XCTAssertEqual(split["S1"]?.id, alice.id)
        XCTAssertNotEqual(split["S2"]?.id, alice.id)
    }

    func testSharedTimeStillCarriesClustersWithoutAUsableEmbedding() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("a", 0, 30), segment("b", 30, 30)],
                                      embeddings: ["a": voice(0), "b": [0, 0, 0, 0]])
        XCTAssertEqual(tracker.voiceprintCount, 1)
        // "y" has no embedding and matches by shared time.
        let next = tracker.reconcile([segment("y", 40, 30)], since: 20, embeddings: [:])
        XCTAssertEqual(next["y"]?.id, first["b"]?.id)
        XCTAssertEqual(tracker.voiceprintCount, 1)
    }

    func testABriefClusterCannotClaimAnIdentityByVoice() {
        // Review of #207: a 0.3 s backchannel gives too noisy an embedding to re-link anyone.
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let alice = tracker.reconcile([segment("a", 0, 30)], embeddings: ["a": voice(0)])["a"]!
        let brief = tracker.reconcile([segment("x", 300, 0.3)], since: 300, embeddings: ["x": voice(0)])
        XCTAssertNotEqual(brief["x"]?.id, alice.id)
        let longer = tracker.reconcile([segment("y", 400, 2)], since: 400, embeddings: ["y": voice(0)])
        XCTAssertEqual(longer["y"]?.id, alice.id, "Two seconds is enough")
    }

    func testConfidentSharedTimeWinsOverASimilarVoice() {
        // Review of #207: X's own cluster shares nearly all its audio with X but sounds a little off
        // (cosine 0.819), while a different person Z sounds more like X (cosine 0.866). Shared time
        // keeps X; Z must not inherit X's label or name.
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let speakerX = tracker.reconcile([segment("a", 0, 60)], embeddings: ["a": voice(0)])["a"]!
        tracker.rename(id: speakerX.id, name: "Xavier")
        let next = tracker.reconcile([segment("x", 30, 60), segment("z", 100, 30)], since: 30,
                                     embeddings: ["x": voice(35), "z": voice(-30)])
        XCTAssertEqual(next["x"]?.id, speakerX.id)
        XCTAssertEqual(next["x"]?.name, "Xavier")
        XCTAssertNotEqual(next["z"]?.id, speakerX.id)
        XCTAssertNotEqual(next["z"]?.name, "Xavier")
    }

    func testOverlappingWindowsCountEachSecondOfSpeechOnce() throws {
        // Review of #207: windows overlap and passes run every ~20 s, so the same 6 s of speech is
        // heard by several passes. It must weigh 6 s, not 24 s, and so stay unsettled.
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let speaker = tracker.reconcile([segment("a", 0, 6)], embeddings: ["a": voice(0)])["a"]!
        _ = tracker.reconcile([segment("a", 0, 6)], embeddings: ["a": voice(1)])
        _ = tracker.reconcile([segment("a", 0, 6)], embeddings: ["a": voice(2)])
        _ = tracker.reconcile([segment("b", 1, 5)], since: 1, embeddings: ["b": voice(3)])
        let voiceprint = try XCTUnwrap(tracker.voiceprint(for: speaker.id))
        XCTAssertEqual(voiceprint.weight, 6, accuracy: 1e-9)
        XCTAssertLessThan(voiceprint.weight, SpeakerVoiceMatching.settledWeight)
        // New speech after what was heard does count.
        _ = tracker.reconcile([segment("a", 1, 15)], since: 1, embeddings: ["a": voice(0)])
        XCTAssertEqual(try XCTUnwrap(tracker.voiceprint(for: speaker.id)).weight, 16, accuracy: 1e-9)
    }

    func testSettledVoiceprintIgnoresASharedTimeMatchThatSoundsLikeSomeoneElse() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let alice = tracker.reconcile([segment("a", 0, 60)], embeddings: ["a": voice(0)])["a"]!
        // Shared time says this cluster is Alice, but it sounds nothing like her: she keeps her voice,
        // and a later window of her real voice, heard after silence, still finds her.
        let muddled = tracker.reconcile([segment("m", 30, 60)], since: 30, embeddings: ["m": voice(80)])
        XCTAssertEqual(muddled["m"]?.id, alice.id)
        let later = tracker.reconcile([segment("z", 400, 30)], since: 400, embeddings: ["z": voice(2)])
        XCTAssertEqual(later["z"]?.id, alice.id)
    }

    func testUnsettledVoiceprintLearnsFromSharedTime() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        // A first voiceprint from a few seconds of speech is unreliable; the shared-time match corrects it.
        let alice = tracker.reconcile([segment("a", 0, 5)], embeddings: ["a": voice(50)])["a"]!
        _ = tracker.reconcile([segment("m", 0, 200)], since: 0.5, embeddings: ["m": voice(0)])
        let later = tracker.reconcile([segment("z", 600, 30)], since: 600, embeddings: ["z": voice(3)])
        XCTAssertEqual(later["z"]?.id, alice.id)
    }

    /// The issue's acceptance: a 40-minute, three-person meeting analyzed in trailing windows, with
    /// each person going quiet for minutes at a time, never grows past three speakers, and a rename
    /// sticks to every later window.
    func testLongMeetingWithLongSilencesKeepsTheRealNumberOfSpeakers() {
        let people = ["alice", "bob", "carol"]
        let voices = Dictionary(uniqueKeysWithValues: people.enumerated().map { ($1, unitNoise(seed: $0 + 1)) })
        // Who talks in each minute: long stretches where one or two people say nothing.
        let schedule: [ClosedRange<Int>: [String]] = [
            0...4: ["alice", "bob"], 5...14: ["bob"], 15...19: ["carol"], 20...24: ["alice"],
            25...33: ["bob", "carol"], 34...39: ["alice", "carol"]
        ]
        func speakers(atMinute minute: Int) -> [String] {
            schedule.first { $0.key.contains(minute) }?.value ?? []
        }
        var tracker = SpeakerIdentityTracker(namespace: "run")
        var baseline = SpeakerIdentityTracker(namespace: "base")
        var seen = Set<String>()
        var baselineSeen = Set<String>()
        var aliceID: String?
        var analyzed = 0.0
        var pass = 0
        for now in stride(from: 30.0, through: 2_400, by: 30) {
            let windowStart = max(analyzed - SpeakerAnalysisPolicy.windowOverlap, 0)
            var segments: [DiarizedSegment] = []
            var embeddings: [String: [Float]] = [:]
            var clusterFor: [String: String] = [:]
            pass += 1
            // Each 10 s slot belongs to one of the minute's speakers, alternating.
            for slot in stride(from: windowStart, to: now, by: 10) {
                let present = speakers(atMinute: Int(slot / 60))
                guard !present.isEmpty else { continue }
                let person = present[Int(slot / 10) % present.count]
                // Cluster ids are renumbered every pass, so they say nothing about who is who.
                let cluster = clusterFor[person] ?? "S\((clusterFor.count + pass) % 7)"
                clusterFor[person] = cluster
                segments.append(segment(cluster, slot, 10))
                embeddings[cluster] = jitter(voices[person]!, seed: pass * 31 + people.firstIndex(of: person)!)
            }
            analyzed = now
            let mapping = tracker.reconcile(segments, since: windowStart, embeddings: embeddings)
            seen.formUnion(mapping.values.map(\.id))
            baselineSeen.formUnion(baseline.reconcile(segments, since: windowStart).values.map(\.id))
            guard let cluster = clusterFor["alice"], let identity = mapping[cluster] else { continue }
            if let aliceID {
                XCTAssertEqual(identity.id, aliceID, "pass \(pass)")
                XCTAssertEqual(identity.name, "Alice", "pass \(pass)")
            } else {
                aliceID = identity.id
                tracker.rename(id: identity.id, name: "Alice")
            }
        }
        XCTAssertNotNil(aliceID)
        XCTAssertEqual(seen.count, 3)
        XCTAssertGreaterThan(baselineSeen.count, 3, "shared time alone duplicates returning speakers")
    }

    // MARK: Deterministic pseudo-random voices

    private func unitNoise(seed: Int, dimensions: Int = 32) -> [Float] {
        var state = UInt64(seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let raw = (0..<dimensions).map { _ -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: state >> 11) % 2_000) / 1_000 - 1
        }
        return SpeakerVoiceMatching.normalized(raw)!
    }

    /// The same voice heard in another window: close to it, never identical.
    private func jitter(_ voice: [Float], seed: Int) -> [Float] {
        let noise = unitNoise(seed: 1_000 + seed, dimensions: voice.count)
        return zip(voice, noise).map { $0 + 0.25 * $1 }
    }
}
