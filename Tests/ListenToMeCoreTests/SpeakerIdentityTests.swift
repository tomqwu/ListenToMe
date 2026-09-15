import XCTest
@testable import ListenToMeCore

final class SpeakerIdentityTests: XCTestCase {
    private func segment(_ id: String, _ start: Double, _ duration: Double) -> DiarizedSegment {
        DiarizedSegment(speakerId: id, start: start, duration: duration)
    }

    func testRenumberedClustersKeepEditedNamesAsAudioGrows() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("a", 0, 3), segment("b", 3, 3)])
        let alice = first["a"]!
        tracker.rename(id: alice.id, name: "Alice")
        let next = tracker.reconcile([segment("x", 0, 3), segment("y", 3, 3), segment("x", 6, 5)])
        XCTAssertEqual(next["x"]?.id, alice.id)
        XCTAssertEqual(next["x"]?.name, "Alice")
        XCTAssertEqual(next["y"], first["b"])
    }

    func testAmbiguousSplitDoesNotDuplicateNamedIdentity() {
        var tracker = SpeakerIdentityTracker()
        let old = tracker.reconcile([segment("a", 0, 10)])["a"]!
        tracker.rename(id: old.id, name: "Alice")
        let split = tracker.reconcile([segment("x", 0, 5), segment("y", 5, 5)])
        XCTAssertNotEqual(split["x"]?.id, old.id)
        XCTAssertNotEqual(split["y"]?.id, old.id)
        XCTAssertNotEqual(split["x"]?.id, split["y"]?.id)
    }

    func testAmbiguousMergeDoesNotInheritAnArbitraryName() {
        var tracker = SpeakerIdentityTracker()
        let old = tracker.reconcile([segment("a", 0, 5), segment("b", 5, 5)])
        let merged = tracker.reconcile([segment("x", 0, 10)])["x"]!
        XCTAssertFalse(old.values.contains { $0.id == merged.id })
    }

    func testNewVoiceAndNewRunHaveDistinctIdentities() {
        var tracker = SpeakerIdentityTracker(namespace: "one")
        let old = tracker.reconcile([segment("a", 0, 3)])["a"]!
        let next = tracker.reconcile([segment("b", 0, 3), segment("a", 3, 3)])
        XCTAssertEqual(next["b"]?.id, old.id)
        XCTAssertNotEqual(next["a"]?.id, old.id)
        var otherRun = SpeakerIdentityTracker(namespace: "two", prefix: "Mic speaker")
        let microphone = otherRun.reconcile([segment("a", 0, 3)])["a"]!
        XCTAssertNotEqual(microphone.id, old.id)
        XCTAssertEqual(microphone.name, "Mic speaker 1")
    }

    func testInvalidSegmentsAreIgnoredAndOrderingIsDeterministic() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let result = tracker.reconcile([
            segment("b", 0, 2), segment("a", 0, 2), segment("zero", 4, 0),
            segment("nan", .nan, 2), segment("inf", 0, .infinity)
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["a"]?.name, "Speaker 1")
        XCTAssertEqual(result["b"]?.name, "Speaker 2")
    }

    // MARK: Incremental (trailing-window) passes — issue #109

    func testTrailingWindowKeepsIdentitiesFromTheOverlap() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("a", 0, 30), segment("b", 30, 30)])
        tracker.rename(id: first["a"]!.id, name: "Alice")
        // Next pass re-analyzes only [40, 90); model IDs are renumbered, but the 20 s overlap with
        // "b" must carry that identity over instead of minting a new speaker.
        let window = tracker.reconcile([segment("s0", 40, 20), segment("s1", 60, 30)], since: 40)
        XCTAssertEqual(window["s0"], first["b"])
        XCTAssertNotEqual(window["s1"]?.id, first["b"]?.id)
        XCTAssertNotEqual(window["s1"]?.id, first["a"]?.id)
        // History before the window survives, so a later window can still match Alice.
        let again = tracker.reconcile([segment("t0", 0, 30)], since: 0)
        XCTAssertEqual(again["t0"]?.name, "Alice")
    }

    func testWindowedPassDoesNotMatchSpeakersOutsideTheWindow() {
        var tracker = SpeakerIdentityTracker(namespace: "run")
        let first = tracker.reconcile([segment("a", 0, 30), segment("b", 30, 30)])
        // A window covering only [60, 90) overlaps neither previous speaker → a new identity.
        let window = tracker.reconcile([segment("s0", 60, 30)], since: 60)
        XCTAssertFalse(first.values.contains { $0.id == window["s0"]?.id })
    }

    func testWindowedReconcileWithZeroStartBehavesLikeAFullPass() {
        var full = SpeakerIdentityTracker(namespace: "run")
        var windowed = SpeakerIdentityTracker(namespace: "run")
        let a = full.reconcile([segment("a", 0, 10), segment("b", 10, 10)])
        let b = windowed.reconcile([segment("a", 0, 10), segment("b", 10, 10)], since: 0)
        XCTAssertEqual(a, b)
        XCTAssertEqual(full.reconcile([segment("x", 0, 10), segment("y", 10, 10)]),
                       windowed.reconcile([segment("x", 0, 10), segment("y", 10, 10)], since: 0))
    }

    func testClipKeepsOnlyHistoryBeforeTheWindow() {
        let history = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 10),
            DiarizedSegment(speakerId: "B", start: 8, duration: 10),   // straddles the boundary
            DiarizedSegment(speakerId: "C", start: 12, duration: 5),   // entirely inside the window
            DiarizedSegment(speakerId: "D", start: 2, duration: 0)     // degenerate
        ]
        let clipped = SpeakerStats.clip(history, endingAt: 10)
        XCTAssertEqual(clipped, [
            DiarizedSegment(speakerId: "A", start: 0, duration: 10),
            DiarizedSegment(speakerId: "B", start: 8, duration: 2)
        ])
        XCTAssertTrue(SpeakerStats.clip(history, endingAt: 0).isEmpty)
    }

    func testMicrophoneAlignmentDoesNotRelabelSystemAudio() {
        let mic = TranscriptSegment(source: .you, text: "Hello", isFinal: true, start: 10, end: 12)
        let system = TranscriptSegment(source: .others, text: "Hi", isFinal: true, start: 10, end: 12)
        let result = SpeakerLabeling.label(transcript: [mic, system],
                                          diarized: [segment("a", 0, 2)], offset: 10, source: .you)
        XCTAssertEqual(result.lineLabels[mic.id], "Speaker 1")
        XCTAssertNil(result.lineLabels[system.id])
    }

    func testRenamedTranscriptFlowsThroughContextPromptsAndExport() {
        let store = ConversationStore()
        let remote = TranscriptSegment(source: .others, text: "I will ship it.", isFinal: true, start: 0, end: 2)
        let mic = TranscriptSegment(source: .you, text: "Thanks.", isFinal: true, start: 2, end: 3)
        store.apply(remote); store.apply(mic)
        store.attributeSpeakers([remote.id: SpeakerIdentity(id: "remote", name: "Speaker 1")],
                                replacing: [remote.id])
        store.renameSpeaker(id: "remote", name: "Alice")
        let context = ContextEngine().buildContext(from: store, notes: nil)
        XCTAssertEqual(context.messages.first?.speakerLabel, "Alice")
        let prompt = PromptBuilder.buildListener(context: context)
        XCTAssertTrue(prompt.messages.contains { $0.content.contains("Alice: I will ship it.") })
        let markdown = SessionExporter.markdown(title: "Test", transcript: store.utterances)
        XCTAssertTrue(markdown.contains("**Alice:** I will ship it."))
        XCTAssertTrue(markdown.contains("**You:** Thanks."))
        XCTAssertEqual(store.utterances.first?.source, .others)
        // Clearing an unmatched current-run line must not affect older runs or another channel.
        store.attributeSpeakers([mic.id: SpeakerIdentity(id: "mic", name: "Bob")], replacing: [mic.id])
        store.attributeSpeakers([:], replacing: [mic.id])
        XCTAssertEqual(store.utterances[0].speakerLabel, "Alice")
        XCTAssertEqual(store.utterances[1].speakerLabel, "You")
        XCTAssertNil(store.utterances[1].speakerID)
    }
}
