import XCTest
@testable import ListenToMeCore

/// The pieces iOS needs to label one microphone's transcript by speaker (issue #180). Everything
/// here is platform-neutral; the iOS app only wires it to the recorder and the diarizer.
final class SingleMicrophoneSpeakerTests: XCTestCase {
    private func line(_ start: TimeInterval, _ end: TimeInterval, _ text: String = "x",
                      name: String? = "Microphone", id: String? = nil) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end,
                          speakerID: id, speakerName: name)
    }

    // MARK: Identity numbering continues across recordings in one conversation

    func testTrackerCanContinueNumberingAfterAnEarlierRecording() {
        var tracker = SpeakerIdentityTracker(namespace: "run2", firstNumber: 3)
        let mapping = tracker.reconcile([DiarizedSegment(speakerId: "a", start: 0, duration: 4),
                                         DiarizedSegment(speakerId: "b", start: 4, duration: 4)])
        XCTAssertEqual(mapping["a"]?.name, "Speaker 3")
        XCTAssertEqual(mapping["b"]?.name, "Speaker 4")
        XCTAssertEqual(mapping["a"]?.id, "run2-3")
    }

    func testTrackerNeverStartsBelowOne() {
        var tracker = SpeakerIdentityTracker(namespace: "n", firstNumber: 0)
        XCTAssertEqual(tracker.reconcile([DiarizedSegment(speakerId: "a", start: 0, duration: 4)])["a"]?.name,
                       "Speaker 1")
    }

    func testNextSpeakerNumberSkipsNumbersAndRenamedSpeakersAlreadyInTheConversation() {
        XCTAssertEqual(SpeakerLabeling.nextSpeakerNumber(after: []), 1)
        XCTAssertEqual(SpeakerLabeling.nextSpeakerNumber(after: [line(0, 1)]), 1, "Microphone is not a speaker")
        let labeled = [line(0, 1, name: "Speaker 2", id: "r1-2"), line(1, 2, name: "Alice", id: "r1-1"),
                       line(2, 3, name: "Speaker 2", id: "r1-2")]
        XCTAssertEqual(SpeakerLabeling.nextSpeakerNumber(after: labeled), 3)
        // Three renamed identities and no numbered label left still reserve three numbers.
        let renamed = [line(0, 1, name: "Ann", id: "a"), line(1, 2, name: "Bo", id: "b"),
                       line(2, 3, name: "Cy", id: "c")]
        XCTAssertEqual(SpeakerLabeling.nextSpeakerNumber(after: renamed), 4)
        XCTAssertEqual(SpeakerLabeling.nextSpeakerNumber(after: [line(0, 1, name: "Speaker 7", id: "z")]), 8)
    }

    // MARK: Lines get the identity whose speech covers them

    func testAssignMapsLinesOntoIdentitiesByTimeAndLeavesUnheardLinesAlone() {
        let first = line(0, 4), second = line(4, 8), silent = line(20, 22)
        let alice = SpeakerIdentity(id: "run-1", name: "Alice")
        let bob = SpeakerIdentity(id: "run-2", name: "Speaker 2")
        let diarized = [DiarizedSegment(speakerId: "run-1", start: 0, duration: 4),
                        DiarizedSegment(speakerId: "run-2", start: 4, duration: 4)]
        let result = SpeakerLabeling.assign(transcript: [first, second, silent], diarized: diarized,
                                            identities: ["run-1": alice, "run-2": bob], offset: 0, source: .you)
        XCTAssertEqual(result[first.id], alice)
        XCTAssertEqual(result[second.id], bob)
        XCTAssertNil(result[silent.id])
    }

    func testAssignShiftsDiarizedTimesByTheRecordingOffset() {
        // A second recording in the same conversation starts its transcript at 100 s, but its audio
        // buffer starts at 0.
        let resumed = line(100, 104)
        let identity = SpeakerIdentity(id: "r2-3", name: "Speaker 3")
        let result = SpeakerLabeling.assign(transcript: [resumed],
                                            diarized: [DiarizedSegment(speakerId: "r2-3", start: 0, duration: 4)],
                                            identities: ["r2-3": identity], offset: 100, source: .you)
        XCTAssertEqual(result[resumed.id], identity)
    }

    func testAssignSkipsUnknownIdentitiesAndOtherSources() {
        let mine = line(0, 4)
        let theirs = TranscriptSegment(source: .others, text: "x", isFinal: true, start: 0, end: 4)
        let result = SpeakerLabeling.assign(transcript: [mine, theirs],
                                            diarized: [DiarizedSegment(speakerId: "ghost", start: 0, duration: 4)],
                                            identities: [:], offset: 0, source: .you)
        XCTAssertTrue(result.isEmpty)
    }

    func testMinimumCoverageLeavesALineBarelyTouchedBySpeechUnlabeled() {
        let barely = line(0, 10), covered = line(10, 14)
        let diarized = [DiarizedSegment(speakerId: "a", start: 9, duration: 5)]   // 1 s of the first line
        let lenient = SpeakerLabeling.label(transcript: [barely, covered], diarized: diarized, offset: 0, source: .you)
        XCTAssertEqual(lenient.lineLabels[barely.id], "Speaker 1", "Default behaviour (macOS) is unchanged")
        let strict = SpeakerLabeling.label(transcript: [barely, covered], diarized: diarized, offset: 0,
                                           source: .you, minimumCoverage: 0.3)
        XCTAssertNil(strict.lineLabels[barely.id])
        XCTAssertEqual(strict.lineLabels[covered.id], "Speaker 1")
        XCTAssertEqual(strict.order, ["a": "Speaker 1"], "Numbering still covers every diarized speaker")
    }

    // MARK: A label change is not new speech

    func testRelabelingAcknowledgedSpeechIsNotSentToTheModelAgain() throws {
        var context = QuickSummaryContext()
        let spoken = line(0, 2, "Ship it on Friday.", name: nil)
        let before = QuickSummaryContext.pieces(notes: "", segments: [spoken])
        let batch = try XCTUnwrap(context.batch(before, summary: ""))
        context.accept(batch, memory: "Ship Friday.")
        var named = spoken
        named.speakerName = "Speaker 1"
        let after = QuickSummaryContext.pieces(notes: "", segments: [named])
        XCTAssertTrue(context.hasChanges(after), "Precondition: the label is part of the piece")
        context.relabel(from: [spoken], to: [named])
        XCTAssertFalse(context.hasChanges(after))
        XCTAssertNil(try context.batch(after, summary: ""))
        XCTAssertEqual(context.memory, "Ship Friday.")
    }

    func testRelabelingLeavesUnreadOrEditedSpeechPending() throws {
        var context = QuickSummaryContext()
        let read = line(0, 2, "Read.", name: nil)
        let first = QuickSummaryContext.pieces(notes: "", segments: [read])
        context.accept(try XCTUnwrap(context.batch(first, summary: "")), memory: "")
        let unread = line(2, 4, "Not read yet.", name: nil)
        let before = QuickSummaryContext.pieces(notes: "", segments: [read, unread])
        var renamedUnread = unread
        renamedUnread.speakerName = "Speaker 2"
        // The read line was also corrected, so its acknowledged text no longer matches `before`.
        let corrected = TranscriptSegment(id: read.id, source: .you, text: "Read again.", isFinal: true,
                                          start: 0, end: 2, speakerName: "Speaker 1")
        let after = QuickSummaryContext.pieces(notes: "", segments: [corrected, renamedUnread])
        XCTAssertEqual(before.count, 2)
        context.relabel(from: [read, unread], to: [corrected, renamedUnread])
        let pending = try XCTUnwrap(context.batch(after, summary: ""))
        XCTAssertEqual(pending.changes.map(\.text), ["Speaker 1: Read again.", "Speaker 2: Not read yet."])
    }

    @MainActor
    func testReaderRelabelsItsLedger() throws {
        let reader = QuickSummaryReader()
        let spoken = line(0, 2, "Hello.", name: nil)
        var named = spoken
        named.speakerName = "Speaker 1"
        let after = QuickSummaryContext.pieces(notes: "", segments: [named])
        reader.relabel(from: [spoken], to: [named])
        XCTAssertTrue(reader.context.hasChanges(after), "Nothing was acknowledged, so nothing is migrated")
    }
}
