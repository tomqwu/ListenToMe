import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Records each request and answers with fixed events.
private final class SelectionProvider: LLMProvider, @unchecked Sendable {
    let id = "selection-test"
    var events: [LLMStreamEvent]
    private(set) var requests: [LLMRequest] = []
    init(_ events: [LLMStreamEvent]) { self.events = events }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: URLError(.badURL)) }
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        requests.append(request)
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Issue #234 on iOS: summarize only the selected transcript lines through the chosen provider.
@MainActor
final class MobileSelectionSummaryTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func lines() -> [TranscriptSegment] {
        [TranscriptSegment(source: .you, text: "Opening chatter.", isFinal: true, start: 0, end: 4, speakerName: "Microphone"),
         TranscriptSegment(source: .you, text: "We ship on Friday.", isFinal: true, start: 62, end: 66, speakerName: "Alex"),
         TranscriptSegment(source: .you, text: "QA signs off Thursday.", isFinal: true, start: 70, end: 75, speakerName: "Sam")]
    }

    private func onDeviceSession(_ provider: SelectionProvider) -> MobileSession {
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = provider
        let original = session.ai.provider
        addTeardownBlock { @MainActor in session.ai.provider = original }
        session.ai.provider = .apple
        return session
    }

    func testOnlyTheSelectedLinesAreSentAndTheResultIsSavedWithTheRecord() async throws {
        let provider = SelectionProvider([.content("- Ship Friday; QA Thursday.")])
        let session = onDeviceSession(provider)
        session.segments = lines()
        session.notes = "Private note"
        let selected = Array(session.segments.suffix(2))
        XCTAssertNil(session.selectionSummaryBlockReason(selected))
        XCTAssertEqual(session.selectionSummaryDestination, "Summarized on this device with Apple Intelligence.")
        await session.summarizeSelection(selected)
        let request = try XCTUnwrap(provider.requests.first)
        let user = try XCTUnwrap(request.messages.first?.content)
        XCTAssertTrue(user.contains("[1:02] Alex: We ship on Friday.\n[1:10] Sam: QA signs off Thursday."), user)
        XCTAssertFalse(user.contains("Opening chatter"), "Unselected lines never leave")
        XCTAssertFalse(user.contains("Private note"), "Notes are not part of a selection")
        XCTAssertTrue(request.system.hasPrefix(SelectionSummaryPrompt.instructions))
        XCTAssertEqual(session.selectionRun.result?.text, "- Ship Friday; QA Thursday.")
        XCTAssertNil(session.selectionRun.notice)
        XCTAssertEqual(session.selectionSummaries.first?.span, "1:02–1:15 · 2 lines")
        XCTAssertEqual(session.summary, "", "The conversation's Summary is untouched")
        XCTAssertTrue(session.markdown.contains("## Selection summaries\n\n### 1:02–1:15 · 2 lines"), session.markdown)
        let saved = try XCTUnwrap(session.history.first)
        XCTAssertTrue(SessionExporter.json(for: saved).contains("\"selectionSummaries\""))

        let reloaded = MobileSession(storageDirectory: root)
        XCTAssertEqual(reloaded.selectionSummaries.map(\.text), ["- Ship Friday; QA Thursday."])
        XCTAssertEqual(reloaded.history.first?.selectionSummaries?.count, 1)
        reloaded.newConversation()
        XCTAssertTrue(reloaded.selectionSummaries.isEmpty)
    }

    func testTheMicrophoneLabelReachesThePromptAsYou() async throws {
        let provider = SelectionProvider([.content("- Chatter.")])
        let session = onDeviceSession(provider)
        session.segments = lines()
        await session.summarizeSelection([session.segments[0]])
        XCTAssertTrue(provider.requests.first?.messages.first?.content.contains("[0:00] You: Opening chatter.") == true)
    }

    func testAddToNotesAppendsUnderTheSpan() async throws {
        let provider = SelectionProvider([.content("- Ship Friday.")])
        let session = onDeviceSession(provider)
        session.segments = lines()
        session.notes = "Agenda"
        await session.summarizeSelection([session.segments[1]])
        let result = try XCTUnwrap(session.selectionRun.result)
        session.addSelectionSummaryToNotes(result)
        XCTAssertEqual(session.notes, "Agenda\n\nSelection summary (1:02–1:06 · 1 line):\n- Ship Friday.")
    }

    func testALongSelectionOnTheDeviceIsShortenedAndSaysSo() async throws {
        let provider = SelectionProvider([.content("- Long."), .outputLimitReached])
        let session = onDeviceSession(provider)
        session.segments = (0..<120).map {
            TranscriptSegment(source: .you, text: "Point \($0) " + String(repeating: "detail ", count: 20),
                              isFinal: true, start: Double($0 * 30), end: Double($0 * 30 + 20))
        }
        await session.summarizeSelection(session.segments)
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertLessThanOrEqual(request.system.count + (request.messages.first?.content.count ?? 0),
                                 PromptBudget.appleIntelligenceCharacters - PromptBudget.answerReserve)
        let notice = try XCTUnwrap(session.selectionRun.notice)
        XCTAssertTrue(notice.contains("The selection was too long for this model"), notice)
        XCTAssertTrue(notice.contains(LLMOutputLimit.notice), "A cut-off answer says so too")
        XCTAssertEqual(session.selectionSummaries.first?.shortened, true)
    }

    func testBlockedSelectionsSendNothingAndSayWhy() async {
        let provider = SelectionProvider([.content("x")])
        let session = MobileSession(storageDirectory: root, summaryProvider: provider)
        XCTAssertEqual(session.selectionSummaryBlockReason([]), "Select one or more finished lines to summarize.")
        session.segments = lines()
        session.isSummarizing = true
        XCTAssertNotNil(session.selectionSummaryBlockReason(session.segments))
        session.requestSelectionSummary(session.segments)
        XCTAssertEqual(session.selectionRun.error, session.selectionSummaryBlockReason(session.segments))
        session.isSummarizing = false
        XCTAssertTrue(provider.requests.isEmpty)
    }

    /// Without a usable provider (no key, no server) the button stays disabled with the reason.
    func testAnUnavailableProviderBlocksWithItsReason() {
        let session = MobileSession(storageDirectory: root)
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .openAI
        session.segments = lines()
        XCTAssertEqual(session.selectionSummaryBlockReason(session.segments), session.summaryAvailability(for: .summary))
        XCTAssertNotNil(session.selectionSummaryBlockReason(session.segments))
        XCTAssertTrue(session.selectionSummaryDestination.hasPrefix("Sends the selected lines to "),
                      "A server or cloud provider is named before anything is sent")
    }

    func testAFailureKeepsTheSavedSummariesAndSaysWhy() async {
        let provider = SelectionProvider([])
        let session = onDeviceSession(provider)
        session.segments = lines()
        await session.summarizeSelection([session.segments[1]])
        XCTAssertTrue(session.selectionRun.error?.hasPrefix("Selection summary failed:") == true)
        XCTAssertTrue(session.selectionSummaries.isEmpty)
    }
}
