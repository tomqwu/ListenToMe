import AppKit
import XCTest
import ListenToMeCore

@MainActor
final class MacSpeakerRenameTests: XCTestCase {
    func testDoubleClickRenamesButSingleClickAndDisabledLabelDoNot() throws {
        let button = MacSpeakerNameButton(frame: .zero)
        var requests = 0
        button.rename = { requests += 1 }
        func event(_ count: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1))
        }
        button.mouseDown(with: try event(1))
        XCTAssertEqual(requests, 0)
        button.mouseDown(with: try event(2))
        XCTAssertEqual(requests, 1)
        button.isEnabled = false
        button.mouseDown(with: try event(2))
        XCTAssertEqual(requests, 1)
    }
    func testAccessibilityRenameAndNameValidation() {
        let button = MacSpeakerNameButton(frame: .zero)
        var requests = 0
        button.rename = { requests += 1 }
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(requests, 1)
        button.isEnabled = false
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertEqual(requests, 1)
        XCTAssertNil(SpeakerRenameEditor.normalized("  \n "))
        XCTAssertNil(SpeakerRenameEditor.normalized("Microphone"))
        XCTAssertNil(SpeakerRenameEditor.normalized("Apple Watch"))
        XCTAssertEqual(SpeakerRenameEditor.normalized("  Dana \n Lee  "), "Dana Lee")
        XCTAssertEqual(SpeakerRenameEditor.normalized(String(repeating: "a", count: 90))?.count, 80)
    }
    func testRenameLiveParticipantBeforeTranscriptAttribution() {
        var people = [SpeakerParticipant(id: "live", name: "Speaker 1", source: .others, seconds: 3)]
        let store = ConversationStore()
        store.apply(TranscriptSegment(source: .others, text: "Unattributed speech", isFinal: true, start: 0, end: 3))
        XCTAssertEqual(SpeakerParticipant.rename(id: "live", to: "Dana", participants: &people, store: store), .others)
        XCTAssertEqual(people.first?.name, "Dana", "Naming a live breakdown participant must not require attributed text")
        XCTAssertNil(store.utterances.first?.speakerID, "Naming must not assign unrecognized speech to that voice")
    }

    func testRenameRestoredSpeakerAndIgnoreUnknownIdentity() {
        var people: [SpeakerParticipant] = []
        let store = ConversationStore()
        let run = UUID()
        let late = TranscriptSegment(source: .others, text: "Late final", isFinal: true, start: 20, end: 23,
                                     speakerID: "restored", speakerName: "Speaker 1", recordingID: run)
        let other = TranscriptSegment(source: .you, text: "Other speaker", isFinal: true, start: 12, end: 15,
                                      speakerID: "other", speakerName: "Speaker 2", recordingID: run)
        let early = TranscriptSegment(source: .others, text: "Early final", isFinal: true, start: 10, end: 11,
                                      speakerID: "restored", speakerName: "Speaker 1", recordingID: run)
        for segment in [late, early, other] { store.apply(segment) }
        let original = store.utterances
        XCTAssertEqual(store.presentedUtterances.map(\.id), [early.id, other.id, late.id])
        XCTAssertEqual(SpeakerParticipant.rename(id: "restored", to: "Dana", participants: &people, store: store), .others)
        XCTAssertEqual(store.utterances.map(\.speakerName), ["Dana", "Dana", "Speaker 2"])
        XCTAssertEqual(store.presentedUtterances.map(\.speakerName), ["Dana", "Speaker 2", "Dana"])
        XCTAssertEqual(store.presentedUtterances.map(\.id), [early.id, other.id, late.id])
        XCTAssertEqual(store.utterances.map(\.id), original.map(\.id), "Rename must preserve canonical editing targets")
        XCTAssertEqual(store.utterances.map(\.recordingID), original.map(\.recordingID))
        XCTAssertEqual(store.utterances.map(\.start), original.map(\.start))
        XCTAssertEqual(store.utterances.map(\.end), original.map(\.end))
        XCTAssertEqual(store.utterances.map(\.text), original.map(\.text))
        let revision = store.revision
        XCTAssertNil(SpeakerParticipant.rename(id: "missing", to: "Wrong", participants: &people, store: store))
        XCTAssertEqual(store.revision, revision, "Unknown identities must not mutate the conversation")
        XCTAssertEqual(store.utterances.map(\.speakerName), ["Dana", "Dana", "Speaker 2"])
    }

}
