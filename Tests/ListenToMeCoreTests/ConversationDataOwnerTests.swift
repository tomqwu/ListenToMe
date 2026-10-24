import XCTest
@testable import ListenToMeCore

final class ConversationDataOwnerTests: XCTestCase {
    private struct Failure: Error {}

    func testDeletionCarriesEachIDAndImportKeyOnce() {
        let records = [
            SessionRecord(id: "A", title: "One", date: Date(), transcript: "", summary: "", sourceImportID: "watch:1"),
            SessionRecord(id: "B", title: "Two", date: Date(), transcript: "", summary: ""),
            SessionRecord(id: "A", title: "One again", date: Date(), transcript: "", summary: "",
                          sourceImportID: "watch:1"),
        ]
        let deletion = ConversationDeletion(records: records, everything: true)
        XCTAssertEqual(deletion.ids, ["A", "B"])
        XCTAssertEqual(deletion.sourceImportIDs, ["watch:1"])
        XCTAssertTrue(deletion.everything)
        XCTAssertEqual(ConversationDeletion(ids: ["", "C"], sourceImportIDs: [""]).ids, ["C"])
        XCTAssertEqual(ConversationDeletion(ids: ["C"], sourceImportIDs: [""]).sourceImportIDs, [])
        XCTAssertFalse(ConversationDeletion(ids: ["C"]).everything)
    }

    func testEveryOwnerRunsEvenAfterOneFails() {
        var reached: [String] = []
        let owners = [
            ConversationDataOwner("attachments") { _ in reached.append("attachments"); throw Failure() },
            ConversationDataOwner("Apple Watch audio") { deletion in reached.append("watch:\(deletion.ids)") },
            ConversationDataOwner("saved audio") { _ in reached.append("audio"); throw Failure() },
        ]
        let failed = ConversationDataErasure.run(owners, for: ConversationDeletion(ids: ["A"]))
        XCTAssertEqual(reached, ["attachments", "watch:[\"A\"]", "audio"])
        XCTAssertEqual(failed, ["attachments", "saved audio"])
        XCTAssertEqual(ConversationDataErasure.run([], for: ConversationDeletion(ids: ["A"])), [])
    }

    func testFailureNoteNamesWhatIsLeft() {
        XCTAssertNil(ConversationDataErasure.failureNote([]))
        let note = try? XCTUnwrap(ConversationDataErasure.failureNote(["attachments"]))
        XCTAssertEqual(note, "The conversation text is deleted, but some attachments could not be removed from this device.")
        XCTAssertTrue(ConversationDataErasure.failureNote(["attachments", "saved audio"])?.contains("saved audio") == true)
    }
}
