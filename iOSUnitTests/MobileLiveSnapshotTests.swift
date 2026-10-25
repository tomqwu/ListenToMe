import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

private final class SnapshotProvider: LLMProvider, @unchecked Sendable {
    let id = "snapshot-test"
    var requests: [LLMRequest] = []
    var response = "- Synthetic recap."
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        return AsyncThrowingStream {
            $0.yield(response)
            $0.finish()
        }
    }
}

@MainActor
final class MobileLiveSnapshotTests: XCTestCase {
    private func session(provider: SnapshotProvider? = nil) -> MobileSession {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return MobileSession(storageDirectory: root, summaryProvider: provider)
    }

    private func line(_ text: String, final: Bool = true) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: text, isFinal: final, start: 0, end: 1)
    }

    func testSnapshotReusesLongTranscriptAndInvalidatesCorrectionsLabelsPartialsAndNotes() {
        let session = session()
        session.segments = (0..<200).map { line("Line \($0) " + String(repeating: "detail ", count: 120)) }
        let original = session.liveSnapshot()
        let count = session.liveSnapshotComputations
        for _ in 0..<10 { _ = session.quickPieces; _ = session.summarySource; session.scheduleAutoQuick() }
        XCTAssertEqual(session.liveSnapshotComputations, count)
        XCTAssertEqual(session.quickPieces, original.pieces)
        let first = session.segments[0]
        session.segments[0] = TranscriptSegment(id: first.id, source: first.source,
            text: "Corrected finalized speech", isFinal: true, start: first.start, end: first.end)
        XCTAssertTrue(session.summarySource.contains("Corrected finalized speech"))
        session.segments[0].speakerName = "Dana"
        XCTAssertTrue(session.summarySource.contains("Dana: Corrected finalized speech"))
        session.partial = line("A provisional question that is long enough", final: false)
        let partial = session.liveSnapshot()
        XCTAssertTrue(partial.manualSource.contains("(provisional) A provisional"))
        let before = session.liveSnapshotComputations
        let unchanged = session.partial
        session.partial = unchanged
        _ = session.quickPieces
        XCTAssertEqual(session.liveSnapshotComputations, before)
        session.partial = line("A different hypothesis that is long enough", final: false)
        XCTAssertTrue(session.liveSnapshot().manualSource.contains("different hypothesis"))
        session.notes = "New notes"
        XCTAssertTrue(session.summarySource.hasPrefix("Notes: New notes"))
        session.segments = []
        session.partial = nil
        session.notes = ""
        XCTAssertTrue(session.quickPieces.isEmpty)
        XCTAssertTrue(session.liveSnapshot().manualSource.isEmpty)
    }

    func testManualSummaryFloorsTagsAndDefinesProvisionalWithoutChangingSavedText() async throws {
        let provider = SnapshotProvider()
        let session = session(provider: provider)
        session.partial = line("too short", final: false)
        await session.summarize()
        XCTAssertTrue(provider.requests.isEmpty)
        let speech = "The proposed delivery date might be next Friday"
        session.partial = line(speech, final: false)
        await session.summarize()
        let request = try XCTUnwrap(provider.requests.last)
        XCTAssertTrue(request.system.contains(PromptBuilder.provisionalNotice))
        XCTAssertTrue(request.messages[0].content.contains("You: (provisional) " + speech))
        XCTAssertEqual(session.currentRecord.segments?.last?.text, speech)
        session.segments = [line(speech)]
        session.partial = nil
        await session.summarize()
        let finalRequest = try XCTUnwrap(provider.requests.last)
        XCTAssertFalse(finalRequest.system.contains(PromptBuilder.provisionalNotice))
        XCTAssertFalse(finalRequest.messages[0].content.contains(ConversationStore.provisionalTag))
    }

    func testCloudQuickTagsJSONInputWhileAutoRetainsItsOriginalRepresentation() async throws {
        let provider = SnapshotProvider()
        provider.response = #"{"action":"keep","context":"","bullets":[],"reviews":[]}"#
        let session = session(provider: provider)
        session.partial = line(String(repeating: "x", count: 23), final: false)
        XCTAssertTrue(session.liveSnapshot().manualSegments.isEmpty)
        let speech = String(repeating: "x", count: 24)
        session.partial = line(speech, final: false)
        XCTAssertEqual(session.liveSnapshot().manualSegments.count, 1)
        XCTAssertFalse(session.summarySource.contains(ConversationStore.provisionalTag))
        XCTAssertFalse(session.quickPieces.contains { $0.text.contains(ConversationStore.provisionalTag) })
        await session.summarize(mode: .quick)
        XCTAssertNil(session.message)
        let request = try XCTUnwrap(provider.requests.last)
        XCTAssertTrue(request.system.contains(PromptBuilder.provisionalNotice))
        let data = try XCTUnwrap(request.messages.first?.content.data(using: .utf8))
        let input = try JSONDecoder().decode(QuickSummaryContext.Input.self, from: data)
        XCTAssertEqual(input.changes.first?.text, "You: (provisional) " + speech)
    }

    func testAppleQuickAndAskBudgetIncludeTheNoticeAndPreserveTheTagWhenShortened() async throws {
        let provider = SnapshotProvider()
        let session = session()
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.onDeviceProviderOverride = provider
        session.partial = line(String(repeating: "earlier detail ", count: 2_000) + "latest question", final: false)
        await session.summarize(mode: .quick)
        let quick = try XCTUnwrap(provider.requests.last)
        let ask = session.askRequest("What is the latest question?").0
        for request in [quick, ask] {
            XCTAssertTrue(request.system.contains(PromptBuilder.provisionalNotice))
            XCTAssertTrue(request.messages[0].content.contains(ConversationStore.provisionalTag))
            XCTAssertTrue(request.messages[0].content.contains("latest question"))
            XCTAssertLessThanOrEqual(request.system.count + request.messages.reduce(0) { $0 + $1.content.count },
                                     PromptBudget.appleIntelligenceCharacters - PromptBudget.answerReserve)
        }
    }
}
