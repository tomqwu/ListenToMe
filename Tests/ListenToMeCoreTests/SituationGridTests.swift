import XCTest
@testable import ListenToMeCore

final class SituationGridTests: XCTestCase {
    private let speech = TranscriptSegment(source: .others, text: "Alice will send the report Friday.",
                                           isFinal: true, start: 12, end: 15)
    private let json = #"""
    {"summary":"Report follow-up.","open":[],"todo":[{"text":"Send report",
    "quotes":["Alice will send the report Friday."],"owner":"Alice","deadline":"Friday"}],"decided":[]}
    """#

    func testValidGridKeepsLiteralSourcesAndSurvivesArchiveRetitleAndLanguageCopy() throws {
        let grid = try XCTUnwrap(SituationGrid.decode(json, segments: [speech]))
        XCTAssertTrue(grid.markdown.contains("### To-do"))
        XCTAssertTrue(grid.markdown.contains("Owner: Alice"))
        XCTAssertTrue(grid.markdown.contains("Source: “Alice will send the report Friday\\."))
        let record = SessionRecord(id: "one", title: "Meeting", date: Date(), transcript: speech.text,
                                   summary: grid.markdown, segments: [speech], hasIncompleteImport: true, situationGrid: grid)
        let renamed = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
            .retitled("Renamed", state: .user)
        XCTAssertEqual(renamed.hasIncompleteImport, true)
        let copy = renamed.with(languages: .init(current: "en"))
        XCTAssertEqual(copy.situationGrid, grid)
        XCTAssertEqual(copy.hasIncompleteImport, true, "Retitle and language copies must preserve incomplete-import provenance")
        XCTAssertEqual(SituationGrid.decode("```json\n" + json + "\n```", segments: [speech]), grid)
    }

    func testInvalidReferencesOwnersAndMalformedOutputFallBack() {
        XCTAssertNil(SituationGrid.decode(json, segments: []))
        XCTAssertNil(SituationGrid.decode(json.replacingOccurrences(of: "\"Alice\"", with: "\"Bob\""), segments: [speech]))
        XCTAssertNil(SituationGrid.decode(json.replacingOccurrences(of: "\"Friday\"", with: "\"Monday\""), segments: [speech]))
        XCTAssertNil(SituationGrid.decode("Freeform summary", segments: [speech]))
        XCTAssertNil(SituationGrid.decode(String(json.dropLast()), segments: [speech]))
        XCTAssertNil(SituationGrid.decode(json.replacingOccurrences(of: "\"Report follow-up.\"", with: "\"\""), segments: [speech]))
        let partial = TranscriptSegment(source: .others, text: speech.text, isFinal: false, start: 12, end: 15)
        XCTAssertNil(SituationGrid.decode(json, segments: [partial]))
    }

    @MainActor func testCompletionUsesReadableFallbackAndPreservesPreviousBatchEvidence() async throws {
        let store = ConversationStore()
        store.apply(speech)
        let provider = RecordingProvider(deltas: [json])
        let session = MeetingSession(store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "test"])
        session.structuredListenerEnabled = true
        await session.refreshListener()
        let grid = try XCTUnwrap(session.visibleSituation)
        XCTAssertEqual(session.listenerSummary, grid.markdown)
        XCTAssertTrue(session.listenerPersona?.contains(SituationGrid.instructions) == true)
        store.apply(TranscriptSegment(source: .you, text: "Also discuss costs.", isFinal: true, start: 20, end: 22))
        await session.refreshListener()
        XCTAssertEqual(session.visibleSituation, grid)
        XCTAssertTrue(provider.lastUser?.contains("Previous meeting record") == true)
        XCTAssertTrue(provider.lastUser?.contains("Source:") == true)
        XCTAssertEqual(session.finishSituationGrid("Readable freeform fallback"), "Readable freeform fallback")
        XCTAssertNil(session.visibleSituation)
        session.structuredListenerEnabled = false
        XCTAssertEqual(session.finishSituationGrid(json), json)
        session.resetConversation()
        XCTAssertNil(session.visibleSituation)
    }

    @MainActor func testStructuredCompletionKeepsGroundingAndOutputLimitNotices() async throws {
        let store = ConversationStore()
        store.apply(speech)
        let provider = BoundedGridProvider(output: json)
        let session = MeetingSession(store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "test"])
        session.structuredListenerEnabled = true
        session.notes = String(repeating: "Very long contextual notes. ", count: 1000)
        await session.refreshListener()
        XCTAssertNotNil(session.visibleSituation)
        let notices = session.roleNotices(.listener)
        XCTAssertTrue(notices.contains(LLMOutputLimit.notice))
        XCTAssertEqual(notices.count, 1)
        XCTAssertTrue(session.promptTruncationNotice?.contains("notes") == true)
    }
}

private struct BoundedGridProvider: LLMProvider {
    let id = "bounded-grid"
    let maxPromptCharacters: Int? = 8000
    let output: String
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        LLMOutputLimit.textStream(streamEvents(request))
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.content(output))
            continuation.yield(.outputLimitReached)
            continuation.finish()
        }
    }
}
