import XCTest
@testable import ListenToMeCore

@MainActor
final class TranscriptEditingTests: XCTestCase {
    func testEditsPreserveIdentityOriginalAndCounters() {
        let store = ConversationStore()
        let line = TranscriptSegment(source: .others, text: "Pria", isFinal: true, start: 2, end: 4,
            speakerID: "one", speakerName: "Guest", language: "en-CA")
        store.apply(line)
        XCTAssertTrue(store.edit(id: line.id, text: " Priya \n"))
        XCTAssertTrue(store.edit(id: line.id, text: "Priya confirmed"))
        let edited = store.utterances[0]
        XCTAssertEqual(edited.id, line.id)
        XCTAssertEqual(edited.originalText, "Pria")
        XCTAssertEqual(edited.correctionModel, "Manual")
        XCTAssertEqual(edited.start, 2); XCTAssertEqual(edited.end, 4)
        XCTAssertEqual(edited.speakerID, "one"); XCTAssertEqual(edited.speakerName, "Guest")
        XCTAssertEqual(edited.language, "en-CA")
        XCTAssertEqual(store.othersCount, 1); XCTAssertEqual(store.youCount, 0)
        XCTAssertEqual(store.transcriptCharacterCount, edited.text.count)
        XCTAssertEqual(store.revision, 3)
    }

    func testRejectedEditsAndDeletesDoNotAdvanceRevisionAndDeletionKeepsOtherLines() {
        let store = ConversationStore()
        let first = TranscriptSegment(source: .you, text: "First", isFinal: true, start: 0, end: 1)
        let other = TranscriptSegment(source: .others, text: "Second", isFinal: true, start: 1, end: 2)
        let partial = TranscriptSegment(source: .you, text: "Live", isFinal: false, start: 2, end: 3)
        store.restore([first, other]); store.apply(partial)
        XCTAssertFalse(store.edit(id: first.id, text: " \n"))
        XCTAssertFalse(store.edit(id: first.id, text: first.text))
        XCTAssertFalse(store.edit(id: UUID(), text: "Missing"))
        XCTAssertFalse(store.edit(id: partial.id, text: "Changed"))
        XCTAssertFalse(store.delete(id: partial.id))
        XCTAssertEqual(store.revision, 1)
        XCTAssertTrue(store.delete(id: first.id))
        XCTAssertFalse(store.delete(id: first.id))
        XCTAssertEqual(store.utterances, [other]); XCTAssertEqual(store.partial, partial)
        XCTAssertEqual(store.youCount, 0); XCTAssertEqual(store.othersCount, 1)
        XCTAssertEqual(store.transcriptCharacterCount, other.text.count)
        XCTAssertEqual(store.revision, 2)
    }

    func testDeletingLastLineRoundTripsEmptyArchiveWithoutRestoringDeletedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root)
        let store = ConversationStore()
        let line = TranscriptSegment(source: .you, text: "Remove me", isFinal: true, start: 0, end: 1)
        store.apply(line)
        func record() -> SessionRecord {
            SessionRecord(id: "same", title: "Meeting", date: Date(timeIntervalSince1970: 1),
                transcript: store.utterances.map(\.text).joined(separator: "\n"), summary: "",
                segments: store.utterances)
        }
        try archive.save(record())
        XCTAssertTrue(store.delete(id: line.id))
        try archive.save(record())
        let reopened = try XCTUnwrap(SessionArchive(directory: root).all().first)
        XCTAssertTrue(reopened.transcript.isEmpty)
        XCTAssertEqual(reopened.segments, [])
        XCTAssertEqual(try archive.all().count, 1)
    }

    func testManualEditKeepsPreexistingRecognitionOriginal() {
        let store = ConversationStore()
        let line = TranscriptSegment(source: .you, text: "AI correction", isFinal: true, start: 0, end: 1,
                                     originalText: "Recognized", correctionModel: "Model")
        store.apply(line)
        XCTAssertTrue(store.edit(id: line.id, text: "Manual correction"))
        XCTAssertEqual(store.utterances[0].originalText, "Recognized")
    }

    func testSessionEditsInvalidateAnswersWithoutCreatingFirstSummaryWithAutoOff() async {
        let store = ConversationStore()
        let line = TranscriptSegment(source: .others, text: "Pria confirmed", isFinal: true, start: 0, end: 1)
        store.apply(line)
        let provider = RecordingProvider(deltas: ["Answer"])
        let session = MeetingSession(store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "L", .quick: "Q", .deep: "D"])
        session.quickSuggestion = "Stale"
        XCTAssertTrue(session.editTranscript(id: line.id, text: "Priya confirmed"))
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(session.quickSuggestion.isEmpty); XCTAssertTrue(session.deepAnswer.isEmpty)
        await session.refreshListener()
        XCTAssertTrue(provider.lastUser?.contains("Priya confirmed") == true)
        XCTAssertFalse(session.editTranscript(id: line.id, text: "Priya confirmed"))
        XCTAssertTrue(session.deleteTranscript(id: line.id))
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(session.listenerSummary.isEmpty)
        XCTAssertFalse(session.deleteTranscript(id: line.id))
    }
}
