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

    /// Issue #222: My terms reach the selection prompt as the same session guidance Quick gets.
    func testMyTermsReachTheSelectionPrompt() async throws {
        let saved = UserDefaults.standard.object(forKey: VocabularySettingsStore.key)
        defer { UserDefaults.standard.set(saved, forKey: VocabularySettingsStore.key) }
        UserDefaults.standard.removeObject(forKey: VocabularySettingsStore.key)
        let provider = SelectionProvider([.content("- Rollout.")])
        let session = onDeviceSession(provider)
        session.segments = lines()
        XCTAssertNil(session.addToMyTerms("Kubeflow"))
        await session.summarizeSelection([session.segments[1]])
        let system = try XCTUnwrap(provider.requests.first?.system)
        XCTAssertTrue(system.contains("Context for this session:") && system.contains("Kubeflow"), system)
        XCTAssertFalse(provider.requests.first?.messages.first?.content.contains("Kubeflow") == true)
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
        let request = MobileSelectionRequest(lines: session.segments)
        session.prepareSelectionSummary(request)
        session.startSelectionSummary(request)
        XCTAssertEqual(session.selectionRun.phase, .blocked)
        XCTAssertEqual(session.selectionRun.message, session.selectionSummaryBlockReason(session.segments))
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
        XCTAssertEqual(session.selectionRun.phase, .failed)
        XCTAssertTrue(session.selectionRun.message?.hasPrefix("Selection summary failed:") == true)
        XCTAssertTrue(session.selectionSummaries.isEmpty)
        XCTAssertFalse(session.isSummarizing)
    }

    // MARK: PR #244 review

    /// Review 2: with any provider that is not on this device, opening the sheet only prepares the
    /// request; nothing is sent until the user taps Summarize. On this device it starts at once.
    func testAServerProviderSendsOnlyAfterTheTap() async throws {
        let provider = SelectionProvider([.content("- Ship Friday.")])
        let session = MobileSession(storageDirectory: root, summaryProvider: provider)
        session.segments = lines()
        XCTAssertFalse(session.selectionSummaryStaysOnDevice)
        let request = MobileSelectionRequest(lines: [session.segments[1]])
        session.prepareSelectionSummary(request)
        XCTAssertEqual(session.selectionRun.phase, .ready)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(provider.requests.isEmpty, "Nothing leaves before Summarize is tapped")
        session.startSelectionSummary(request)
        await session.selectionRun.task?.value
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(session.selectionRun.phase, .finished)

        let onDevice = SelectionProvider([.content("- Local.")])
        let local = onDeviceSession(onDevice)
        local.segments = lines()
        XCTAssertTrue(local.selectionSummaryStaysOnDevice)
        local.prepareSelectionSummary(MobileSelectionRequest(lines: [local.segments[1]]))
        XCTAssertEqual(local.selectionRun.phase, .running, "Apple Intelligence starts without a second tap")
        await local.selectionRun.task?.value
        XCTAssertEqual(onDevice.requests.count, 1)
    }

    /// Review 3: a new request never shows the text of an earlier one, and the run says which request
    /// and conversation its state belongs to.
    func testPreparingANewRequestClearsTheEarlierAnswer() async throws {
        let provider = SelectionProvider([.content("- First answer.")])
        let session = onDeviceSession(provider)
        session.segments = lines()
        await session.summarizeSelection([session.segments[1]])
        XCTAssertEqual(session.selectionRun.text, "- First answer.")
        let blocked = MobileSelectionRequest(lines: [])
        session.prepareSelectionSummary(blocked)
        XCTAssertEqual(session.selectionRun.phase, .blocked)
        XCTAssertEqual(session.selectionRun.text, "", "A blocked request shows no earlier text")
        XCTAssertNil(session.selectionRun.result)
        XCTAssertTrue(session.selectionRun.matches(blocked.id, conversation: session.id))
        let other = MobileSelectionRequest(lines: [session.segments[2]])
        XCTAssertFalse(session.selectionRun.matches(other.id, conversation: session.id))
        XCTAssertFalse(session.selectionRun.matches(blocked.id, conversation: "another-conversation"))
    }

    /// Review 5: Cancel stops the run, says "Cancelled." rather than a failure, frees the session, and the
    /// old task can never finish into the next run.
    func testACancelledRunCannotOverwriteTheNextOne() async throws {
        let held = HeldSelectionProvider()
        let session = onDeviceSession(SelectionProvider([]))
        session.onDeviceProviderOverride = held
        session.segments = lines()
        let first = MobileSelectionRequest(lines: [session.segments[1]])
        session.prepareSelectionSummary(first)
        try await waitUntil { await held.started == 1 }
        XCTAssertTrue(session.isSummarizing, "A selection summary holds the session like any other request")
        XCTAssertNotNil(session.summaryBlockReason(for: .summary), "Summary waits for it")
        session.cancelSelectionSummary()
        XCTAssertEqual(session.selectionRun.phase, .cancelled)
        XCTAssertEqual(session.selectionRun.message, "Cancelled.")
        XCTAssertFalse(session.isSummarizing)

        session.onDeviceProviderOverride = SelectionProvider([.content("- Second answer.")])
        let second = MobileSelectionRequest(lines: [session.segments[2]])
        session.prepareSelectionSummary(second)
        await session.selectionRun.task?.value
        await held.release("- Stale answer.")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.selectionRun.phase, .finished)
        XCTAssertEqual(session.selectionRun.text, "- Second answer.")
        XCTAssertEqual(session.selectionSummaries.map(\.text), ["- Second answer."], "The stale run saves nothing")
        XCTAssertFalse(session.isSummarizing)
    }

    /// Review note: a manual Summary blocks a selection summary, and the reverse (above), symmetrically;
    /// the main Cancel summary also stops a selection summary.
    func testCancelSummaryAlsoStopsASelectionSummary() async throws {
        let held = HeldSelectionProvider()
        let session = onDeviceSession(SelectionProvider([]))
        session.onDeviceProviderOverride = held
        session.segments = lines()
        session.prepareSelectionSummary(MobileSelectionRequest(lines: [session.segments[1]]))
        try await waitUntil { await held.started == 1 }
        session.cancelSummary()
        XCTAssertEqual(session.selectionRun.phase, .cancelled)
        XCTAssertFalse(session.isSummarizing)
        await held.release("- Late.")
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let satisfied = await predicate()
        XCTAssertTrue(satisfied)
    }
}

/// Holds its answer until `release`, so a test can cancel a run that is still streaming.
private actor HeldSelectionProvider: LLMProvider {
    nonisolated let id = "held-selection-test"
    private(set) var started = 0
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    func release(_ text: String) {
        for continuation in continuations { continuation.yield(text); continuation.finish() }
        continuations = []
    }
    private func hold(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        started += 1; continuations.append(continuation)
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await self.hold(continuation) } }
    }
}
