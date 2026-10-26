import AVFoundation
import Foundation
import ListenToMeCore
import XCTest

/// Real CoreML inference, separate from the simulator's injected speaker results. Fixtures are
/// synthetic stock voices; no microphone, user conversation, cloud inference or audible playback.
@MainActor
final class SpeakerModelQualityTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Turn: Decodable { let voice: String; let start: Double; let end: Double }
        let sampleRate: Int
        let durationSeconds: Double
        let turns: [Turn]
    }

    func testBriefAlternatingVoicesReceiveDifferentLabels() async throws {
        let result = try await labels(for: "brief-two-voices")
        XCTAssertEqual(result.count, 4)
        let first = try XCTUnwrap(result[0].identity, "The first brief voice must be heard")
        let second = try XCTUnwrap(result[1].identity, "The longer second voice must be heard")
        XCTAssertNotEqual(first.id, second.id, "Two distinct voices cannot both become Speaker 1")
        XCTAssertEqual(result[2].identity?.id, first.id, "The brief returning voice must keep its own label")
        XCTAssertEqual(result[3].identity?.id, second.id, "The second voice must retain its separate label")
        XCTAssertEqual(Set(result.map(\.voice)).count, 2)
    }

    func testOneVoiceIsNotSplitWhenPausesAndSentenceLengthsChange() async throws {
        let result = try await labels(for: "one-voice-pauses")
        XCTAssertEqual(Set(result.map(\.voice)).count, 1)
        let first = try XCTUnwrap(result.first?.identity)
        for turn in result {
            XCTAssertEqual(turn.identity?.id, first.id, "Pauses and short replies do not invent another person")
        }
    }

    func testHeldOutVoicesDoNotMerge() async throws {
        try await assertAlternatingVoices(in: "heldout-two-voices", expectedTurns: 4)
    }

    func testReturningVoicesKeepTheirLabelsInLongerDialogue() async throws {
        try await assertAlternatingVoices(in: "returning-two-voices", expectedTurns: 8)
    }

    func testVoiceEvidenceKeepsNamesWhenSharedAudioIsAbsent() async throws {
        let model = MobileSpeakers.productionDiarizer()
        let (firstFixture, firstAudio) = try load("brief-two-voices")
        let firstWindow = try await model.diarizeLive(samples: firstAudio, startingAtSample: 0, runToken: 1, final: false)
        var tracker = SpeakerIdentityTracker(namespace: "returning")
        let firstMapping = tracker.reconcile(firstWindow.segments, embeddings: firstWindow.embeddings,
                                              stableSpeakerIDScope: firstWindow.stableSpeakerIDScope)
        let first = assigned(firstFixture, window: firstWindow, mapping: firstMapping)
        let voiceA = try XCTUnwrap(first[0].identity)
        let voiceB = try XCTUnwrap(first[1].identity)
        XCTAssertNotEqual(voiceA.id, voiceB.id)
        tracker.rename(id: voiceA.id, name: "Known voice A")

        _ = try await model.diarizeLive(samples: [Float](repeating: 0, count: 100 * 16_000),
                                        startingAtSample: firstAudio.count, runToken: 1, final: false)

        let (nextFixture, nextAudio) = try load("returning-two-voices")
        let nextWindow = try await model.diarizeLive(samples: nextAudio, startingAtSample: 120 * 16_000,
                                                    runToken: 1, final: true)
        XCTAssertEqual(firstWindow.stableSpeakerIDScope, nextWindow.stableSpeakerIDScope)
        let later = nextWindow.segments.map {
            DiarizedSegment(speakerId: $0.speakerId, start: $0.start + 120, duration: $0.duration)
        }
        let nextMapping = tracker.reconcile(later, since: 120, embeddings: nextWindow.embeddings,
                                             stableSpeakerIDScope: nextWindow.stableSpeakerIDScope)
        let next = assigned(nextFixture, window: nextWindow, mapping: nextMapping, offset: 120)
        for (index, turn) in next.enumerated() {
            XCTAssertEqual(turn.identity?.id, index.isMultiple(of: 2) ? voiceA.id : voiceB.id,
                           "No shared audio: the retained model state must recognize \(turn.voice)")
            if index.isMultiple(of: 2) { XCTAssertEqual(turn.identity?.name, "Known voice A") }
        }
    }

    func testModelPredictionStateIsReleasedWhenTheRecordingEnds() async throws {
        let (_, audio) = try load("one-voice-pauses")
        let model = try XCTUnwrap(MobileSpeakers.productionDiarizer() as? MobileConversationDiarizer)
        _ = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        let active = await model.retainedPredictionFrames
        XCTAssertGreaterThan(active, 0, "Exercise a real active model before asserting cleanup")
        await model.endRun(token: 1)
        let retained = await model.retainedPredictionFrames
        XCTAssertEqual(retained, 0, "An ended recording cannot retain its voice timeline")
    }

    private func assertAlternatingVoices(in fixture: String, expectedTurns: Int) async throws {
        let result = try await labels(for: fixture)
        XCTAssertEqual(result.count, expectedTurns)
        let first = try XCTUnwrap(result[0].identity)
        let second = try XCTUnwrap(result[1].identity)
        XCTAssertNotEqual(first.id, second.id, "Different known voices must not share one label")
        for (index, turn) in result.enumerated() {
            XCTAssertEqual(turn.identity?.id, index.isMultiple(of: 2) ? first.id : second.id,
                           "Turn \(index) belongs to \(turn.voice)")
        }
    }

    private func labels(for name: String) async throws -> [(voice: String, identity: SpeakerIdentity?)] {
        let (fixture, samples) = try load(name)
        // The production adapter and its pinned model run here; do not replace this with FakeDiarizer.
        let model = MobileSpeakers.productionDiarizer()
        let window = try await model.diarizeLive(samples: samples, startingAtSample: 0, runToken: 1, final: true)
        var tracker = SpeakerIdentityTracker(namespace: "quality")
        let mapping = tracker.reconcile(window.segments, embeddings: window.embeddings,
                                        stableSpeakerIDScope: window.stableSpeakerIDScope)
        return assigned(fixture, window: window, mapping: mapping)
    }

    private func load(_ name: String) throws -> (Fixture, [Float]) {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Speakers", isDirectory: true)
        let fixture = try JSONDecoder().decode(Fixture.self,
            from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(name + ".wav"))
        XCTAssertEqual(file.processingFormat.sampleRate, Double(fixture.sampleRate))
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        XCTAssertEqual(Double(samples.count) / Double(fixture.sampleRate), fixture.durationSeconds, accuracy: 0.001)

        return (fixture, samples)
    }

    private func assigned(_ fixture: Fixture, window: DiarizedWindow,
                          mapping: [String: SpeakerIdentity], offset: Double = 0)
    -> [(voice: String, identity: SpeakerIdentity?)] {
        let identities = Dictionary(uniqueKeysWithValues: mapping.values.map { ($0.id, $0) })
        let identified = window.segments.compactMap { segment -> DiarizedSegment? in
            guard let identity = mapping[segment.speakerId] else { return nil }
            return DiarizedSegment(speakerId: identity.id, start: segment.start + offset, duration: segment.duration)
        }
        let lines = fixture.turns.enumerated().map { index, turn in
            TranscriptSegment(source: .you, text: "Synthetic turn \(index)", isFinal: true,
                              start: turn.start + offset, end: turn.end + offset, speakerName: "Microphone")
        }
        let assigned = SpeakerLabeling.assign(transcript: lines, diarized: identified, identities: identities,
                                              offset: 0, source: .you, minimumCoverage: 0.3)
        return zip(fixture.turns, lines).map { (voice: $0.0.voice, identity: assigned[$0.1.id]) }
    }
}
