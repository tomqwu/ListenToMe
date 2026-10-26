import XCTest
@testable import ListenToMeCore

final class StreamingSpeakerIdentityTests: XCTestCase {
    private func segment(_ id: String, _ start: Double, _ duration: Double) -> DiarizedSegment {
        DiarizedSegment(speakerId: id, start: start, duration: duration)
    }

    func testStableSlotsKeepEditedNamesWithoutSharedAudio() {
        var tracker = SpeakerIdentityTracker(namespace: "conversation")
        let first = tracker.reconcile([segment("0", 0, 4), segment("1", 4, 4)], stableSpeakerIDScope: "stream")
        tracker.rename(id: first["0"]!.id, name: "Alex")
        let later = tracker.reconcile([segment("1", 120, 4), segment("0", 124, 4)], since: 120,
                                      stableSpeakerIDScope: "stream")
        XCTAssertEqual(later["0"]?.id, first["0"]?.id)
        XCTAssertEqual(later["0"]?.name, "Alex")
        XCTAssertEqual(later["1"], first["1"])
        XCTAssertEqual(tracker.voiceprintCount, 0, "This route uses only the model's per-recording slots")
    }

    func testAResetScopeCannotInheritAnOldNameThroughIdenticalTimestamps() {
        var tracker = SpeakerIdentityTracker(namespace: "conversation")
        let first = tracker.reconcile([segment("0", 0, 10)], stableSpeakerIDScope: "before-gap")["0"]!
        tracker.rename(id: first.id, name: "Do not inherit")
        let reset = tracker.reconcile([segment("0", 0, 10)], stableSpeakerIDScope: "after-gap")["0"]!
        XCTAssertNotEqual(reset.id, first.id, "A model reset may reuse slot 0 for somebody else")
        XCTAssertEqual(reset.name, "Speaker 2")
    }

    func testStableScopeBypassesConflictingTimeAndEmbeddingMatches() {
        var tracker = SpeakerIdentityTracker(namespace: "conversation")
        let legacy = tracker.reconcile([segment("old", 0, 5)], embeddings: ["old": [1, 0]])["old"]!
        tracker.rename(id: legacy.id, name: "Legacy voice")
        let stable = tracker.reconcile([segment("0", 0, 5)], embeddings: ["0": [1, 0]],
                                       stableSpeakerIDScope: "live")["0"]!
        XCTAssertNotEqual(stable.id, legacy.id, "An explicit new scope is stronger than overlapping old evidence")
        let again = tracker.reconcile([segment("0", 100, 5)], since: 100, embeddings: ["0": [0, 1]],
                                      stableSpeakerIDScope: "live")["0"]!
        XCTAssertEqual(again.id, stable.id)
    }

    func testAnotherRecordingHasIndependentIdentityEvenWhenRawSlotsMatch() {
        var first = SpeakerIdentityTracker(namespace: "first")
        var next = SpeakerIdentityTracker(namespace: "next", firstNumber: 4)
        let a = first.reconcile([segment("0", 0, 4)], stableSpeakerIDScope: "same-key")["0"]!
        let b = next.reconcile([segment("0", 0, 4)], stableSpeakerIDScope: "same-key")["0"]!
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(b.name, "Speaker 4")
    }
}
