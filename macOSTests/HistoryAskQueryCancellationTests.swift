import XCTest
import ListenToMeCore

/// A local-only provider that still attempts to publish after its consumer cancels.
private final class QueryHeldProvider: LLMProvider, @unchecked Sendable {
    let id = "query-cancellation-fixture"
    private let lock = NSLock()
    private var output: AsyncThrowingStream<String, Error>.Continuation?
    private var started = false
    private var cancelled = false
    private var sent: [LLMRequest] = []
    var hasStarted: Bool { lock.withLock { started } }
    var wasCancelled: Bool { lock.withLock { cancelled } }
    var requests: [LLMRequest] { lock.withLock { sent } }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] reason in
                if case .cancelled = reason { self?.lock.withLock { self?.cancelled = true } }
            }
            lock.withLock { output = continuation; started = true; sent.append(request) }
        }
    }

    func publish(_ text: String, finish: Bool = false) {
        let continuation = lock.withLock { output }
        continuation?.yield(text)
        if finish { continuation?.finish() }
    }
}

private struct QueryKeywordEmbedder: HistoryEmbedder {
    let signature = "query-cancellation-keyword-only"
    func embed(_ text: String) -> HistoryVector? { nil }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}

@MainActor
final class HistoryAskQueryCancellationTests: XCTestCase {
    private func route(_ provider: QueryHeldProvider) -> HistoryAskRoute {
        HistoryAskRoute(unavailable: nil, destination: nil, responseLanguage: nil, makeProvider: { provider })
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func exerciseChange(to query: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = HistorySearchModel(index: HistoryIndex(directory: root, embedder: QueryKeywordEmbedder()),
                                       syncDelay: .zero, searchDelay: .zero)
        let records = [
            SessionRecord(id: "budget", title: "Budget", date: Date(),
                          transcript: "The budget is forty thousand dollars.", summary: ""),
            SessionRecord(id: "berlin", title: "Berlin", date: Date(),
                          transcript: "The Berlin hotel is reserved for Friday.", summary: "")
        ]
        model.records = { records }
        let old = QueryHeldProvider(), fresh = QueryHeldProvider()
        defer {
            model.cancelAsk()
            old.publish("Late stale answer [1].", finish: true)
            fresh.publish("", finish: true)
            try? FileManager.default.removeItem(at: root)
        }
        try await model.index.sync(records)
        model.search("budget")
        model.ask("budget", route: route(old))
        let started = await eventually { old.hasStarted }
        XCTAssertTrue(started, "A real retrieved request must reach the held provider")
        guard started else { return }
        old.publish("Partial budget answer")
        let partial = await eventually { model.answer == "Partial budget answer" }
        XCTAssertTrue(partial)

        model.search(query) // The actual Mac and phone search-field callback.
        XCTAssertFalse(model.isAsking, "Editing or clearing the question must free Ask immediately")
        XCTAssertEqual(model.answer, "")
        XCTAssertEqual(model.answerQuestion, "")
        XCTAssertTrue(model.citations.isEmpty)
        XCTAssertEqual(model.sentPassages, 0)
        XCTAssertNil(model.askError)
        let cancelled = await eventually { old.wasCancelled }
        XCTAssertTrue(cancelled, "The prior provider consumer must be cancelled")

        model.search("Berlin")
        model.ask("Berlin", route: route(fresh))
        let freshStarted = await eventually { fresh.hasStarted }
        XCTAssertTrue(freshStarted, "A new question must not wait for the old server")
        guard freshStarted else { return }
        fresh.publish("Friday [1].", finish: true)
        await model.waitForAnswer()
        old.publish("Late stale answer [1].", finish: true)
        await Task.yield()
        XCTAssertEqual(model.answer, "Friday [1].")
        XCTAssertEqual(model.answerQuestion, "Berlin")
        XCTAssertEqual(model.citations.map(\.recordID), ["berlin"])
        XCTAssertFalse(model.isAsking)
        XCTAssertNil(model.askError)
        let prompt = try XCTUnwrap(fresh.requests.first?.messages.first?.content)
        XCTAssertTrue(prompt.contains("Berlin hotel"))
        XCTAssertFalse(prompt.contains("forty thousand"), "Only the new question's excerpts are sent")
        await model.waitForSearch()
    }

    func testChangingQuestionCancelsOldProviderAndAllowsNewAnswerWithoutLateOverwrite() async throws {
        try await exerciseChange(to: "Berlin")
    }

    func testClearingQuestionCancelsHiddenAnswerAndAllowsNextQuestion() async throws {
        try await exerciseChange(to: "  \n ")
    }

    func testTrimEquivalentQuestionKeepsCurrentStreamAndAnswer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = HistorySearchModel(index: HistoryIndex(directory: root, embedder: QueryKeywordEmbedder()),
                                       syncDelay: .zero, searchDelay: .zero)
        let records = [SessionRecord(id: "budget", title: "Budget", date: Date(),
                                     transcript: "The budget is forty thousand dollars.", summary: "")]
        model.records = { records }
        let provider = QueryHeldProvider()
        defer {
            model.cancelAsk(); provider.publish("", finish: true)
            try? FileManager.default.removeItem(at: root)
        }
        try await model.index.sync(records)
        model.search("budget")
        model.ask("budget", route: route(provider))
        let started = await eventually { provider.hasStarted }
        XCTAssertTrue(started)
        guard started else { return }
        provider.publish("Forty thousand")
        let partial = await eventually { model.answer == "Forty thousand" }
        XCTAssertTrue(partial)
        model.search("  budget  ")
        await model.waitForSearch()
        XCTAssertTrue(model.isAsking)
        XCTAssertFalse(provider.wasCancelled)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(model.answer, "Forty thousand")
        provider.publish(" dollars [1].", finish: true)
        await model.waitForAnswer()
        XCTAssertEqual(model.answer, "Forty thousand dollars [1].")
        XCTAssertEqual(model.citations.map(\.recordID), ["budget"])
    }
}
