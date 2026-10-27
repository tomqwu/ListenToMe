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
        for text in ["One", "Two"] {
            store.apply(TranscriptSegment(source: .others, text: text, isFinal: true, start: 0, end: 3,
                                          speakerID: "restored", speakerName: "Speaker 1"))
        }
        store.apply(TranscriptSegment(source: .you, text: "Other speaker", isFinal: true, start: 4, end: 5,
                                      speakerID: "other", speakerName: "Speaker 2"))
        XCTAssertEqual(SpeakerParticipant.rename(id: "restored", to: "Dana", participants: &people, store: store), .others)
        XCTAssertEqual(store.utterances.map(\.speakerName), ["Dana", "Dana", "Speaker 2"])
        let revision = store.revision
        XCTAssertNil(SpeakerParticipant.rename(id: "missing", to: "Wrong", participants: &people, store: store))
        XCTAssertEqual(store.revision, revision, "Unknown identities must not mutate the conversation")
        XCTAssertEqual(store.utterances.map(\.speakerName), ["Dana", "Dana", "Speaker 2"])
    }

}
