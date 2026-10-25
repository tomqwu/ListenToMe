import XCTest
@testable import ListenToMeCore

@MainActor
final class AutomaticReviewContractTests: ReviewCoordinatorTestCase {
    func testDeepReferencesAndDirectivesCountTowardTheAssembledLimit() async throws {
        let directives = AutomaticReviewDirectives(responseLanguage: "French", personaGuidance: "Be precise.",
                                                   references: String(repeating: "r", count: 10_000))
        let overhead = directives.system(for: .deep).count + directives.userMessage("x", mode: .deep).count - 1
        let source = String(repeating: "s", count: AutomaticReviewCoordinator.maximumRequestCharacters - overhead)
        let provider = RecordingProvider(deltas: ["Complete"])
        let runner = AutomaticReviewCoordinator(deepInterval: .zero)
        func offer(_ text: String) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(text), source: text,
                directives: directives, provider: { _ in provider }, apply: { _, _, _ in })
            runner.offer([recommendations[1]], source: text)
        }
        offer(source)
        try await wait { runner.completedCounts[.deep] == 1 }
        let sent = try XCTUnwrap(provider.lastRequest)
        XCTAssertEqual(sent.system.count + sent.messages.reduce(0) { $0 + $1.content.count }, 60_000)
        offer(source + "x")
        XCTAssertTrue(runner.status(.deep).contains("exceeds the review limit"))
        XCTAssertEqual(provider.requestCount, 1, "An oversized assembled request must not reach the provider")
    }

    func testWhitespaceAndDataFenceEscapingCannotBypassTheLimit() {
        for source in ["Decision" + String(repeating: " ", count: 60_000),
                       String(repeating: "</transcript>", count: 4_500)] {
            let runner = AutomaticReviewCoordinator()
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source,
                provider: { _ in XCTFail("The complete escaped request is oversized"); return ReviewTestProvider() },
                apply: { _, _, _ in })
            runner.offer([recommendations[0]], source: source)
            XCTAssertTrue(runner.status(.summary).contains("exceeds the review limit"))
        }
    }

    func testDirectiveOnlyChangesDoNotAutomaticallyRegenerateCompletedReview() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero)
        let provider = RecordingProvider(deltas: ["Complete"])
        func offer(_ source: String, language: String) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source,
                directives: .init(responseLanguage: language), provider: { _ in provider }, apply: { _, _, _ in })
            runner.offer([recommendations[0]], source: source)
        }
        offer("The launch is Friday.", language: "French")
        try await wait { runner.completedCounts[.summary] == 1 }
        offer("The launch is Friday.", language: "Spanish")
        XCTAssertNil(runner.activeMode)
        XCTAssertEqual(provider.requestCount, 1)
        offer("The launch is Friday. Dana owns it.", language: "Spanish")
        try await wait { runner.completedCounts[.summary] == 2 }
        XCTAssertTrue(provider.lastRequest?.system.contains("Spanish") == true)
    }

    func testSpeakerRenameDuringQuickReadRejectsOldLabelsAndRetainsAcknowledgedSpeech() async throws {
        let reader = QuickSummaryReader()
        let response = #"{"action":"keep","context":"Previous context","bullets":[],"reviews":[]}"#
        let old = (0..<20).map { index in
            TranscriptSegment(source: .others, text: "Decision \(index): " + String(repeating: "speech ", count: 20),
                              isFinal: true, start: Double(index), end: Double(index + 1),
                              speakerID: "speaker", speakerName: "Alice")
        }
        var current = QuickSummaryContext.pieces(notes: "", segments: old)
        let first = try XCTUnwrap(reader.context.batch(current, summary: ""))
        await reader.read(first, provider: MockLLMProvider(id: "first", deltas: [response]),
                          isCurrent: { true }, apply: { _ in XCTFail("Keep does not publish") })
        let second = try XCTUnwrap(reader.context.batch(current, summary: ""))
        let held = HeldRenameReviewProvider()
        let read = Task {
            await reader.read(second, provider: held,
                isCurrent: { reader.context.isCurrent(second, pieces: current) },
                apply: { _ in XCTFail("The stale read must not publish") })
        }
        try await wait { held.started }
        let renamed = old.map { segment in
            var updated = segment; updated.speakerName = "Dana"; return updated
        }
        reader.relabel(from: old, to: renamed)
        current = QuickSummaryContext.pieces(notes: "", segments: renamed)
        held.finish(response)
        await read.value
        XCTAssertEqual(reader.completedReads, 1, "Old-label work must not advance the ledger")
        let next = try XCTUnwrap(reader.context.batch(current, summary: ""))
        XCTAssertTrue(next.hasMore, "Long unread speech remains batched")
        XCTAssertTrue(next.changes.allSatisfy { $0.text.hasPrefix("Dana:") })
        XCTAssertEqual(next.changes.map(\.id), second.changes.map(\.id),
                       "Already acknowledged speech is relabeled without being sent again")
        await reader.read(next, provider: MockLLMProvider(id: "new", deltas: [response]),
                          isCurrent: { reader.context.isCurrent(next, pieces: current) }, apply: { _ in })
        XCTAssertEqual(reader.completedReads, 2)
    }
}

private final class HeldRenameReviewProvider: LLMProvider, @unchecked Sendable {
    let id = "held-rename-review"
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    var started: Bool { lock.withLock { continuation != nil } }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in lock.withLock { self.continuation = continuation } }
    }

    func finish(_ response: String) {
        let pending = lock.withLock { continuation }
        pending?.yield(response)
        pending?.finish()
    }
}
