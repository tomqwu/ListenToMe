import XCTest
@testable import ListenToMeCore

@MainActor
final class AutomaticReviewCoordinatorTests: XCTestCase {
    private let recommendations = [
        QuickSummaryDecision.Review(mode: "summary", confidence: "high", reason: "New topic"),
        QuickSummaryDecision.Review(mode: "deep", confidence: "medium", reason: "Substantive question")
    ]

    func testRecommendationsRunSeriallyOnceAndSilenceDoesNotPoll() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .milliseconds(30), deepInterval: .milliseconds(30))
        let provider = ReviewTestProvider()
        var outputs: [AutomaticReviewMode: String] = [:]
        runner.synchronize(enabled: true, manualBusy: false, source: "Why is Azure slow?",
            provider: { _ in provider }, apply: { mode, text, _ in outputs[mode] = text })
        runner.offer(recommendations, source: "Why is Azure slow?")
        try await wait { runner.completedCounts[.deep] == 1 }
        XCTAssertEqual(outputs.count, 2)
        let maximum = await provider.maximum()
        XCTAssertEqual(maximum, 1, "Summary and Deep must not race each other")
        runner.offer(recommendations, source: "Why is Azure slow?")
        try await Task.sleep(for: .milliseconds(90))
        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 2, "The same evidence and idle time cannot run full reviews again")
    }

    func testCooldownCoalescesLatestEvidenceAndLowConfidenceStaysManual() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .milliseconds(80))
        let provider = ReviewTestProvider()
        func update(_ source: String) {
            runner.synchronize(enabled: true, manualBusy: false, source: source, provider: { _ in provider }, apply: { _, _, _ in })
            runner.offer([recommendations[0]], source: source)
        }
        update("Azure")
        try await wait { runner.completedCounts[.summary] == 1 }
        update("Azure question")
        update("Azure question clarified")
        try await wait { runner.completedCounts[.summary] == 2 }
        let requests = await provider.requests()
        XCTAssertEqual(requests.map { $0.messages[0].content }, ["Azure", "Azure question clarified"])
        runner.offer([.init(mode: "deep", confidence: "low", reason: "Unclear")], source: "Azure question clarified")
        try await Task.sleep(for: .milliseconds(30))
        let count = await provider.requests().count
        XCTAssertEqual(count, 2)
    }

    func testManualPriorityCancelsAutomaticAndAvoidsDuplicateAfterManualCompletes() async throws {
        let runner = AutomaticReviewCoordinator()
        let provider = ReviewTestProvider(delay: .seconds(1))
        var output = "Previous"
        func sync(_ busy: Bool) {
            runner.synchronize(enabled: true, manualBusy: busy, source: "Azure question", provider: { _ in provider },
                apply: { _, value, _ in output = value })
        }
        sync(false)
        runner.offer([recommendations[0]], source: "Azure question")
        try await wait { await provider.requests().count == 1 }
        sync(true)
        XCTAssertNil(runner.activeMode)
        runner.markManualCompletion(.summary, source: "Azure question")
        sync(false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(output, "Previous", "Cancelled automatic output must not replace a manual review")
        let count = await provider.requests().count
        XCTAssertEqual(count, 1)
    }

    func testStopAndRevisionDiscardLateOutputAndNewConversationCanReuseSameText() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero)
        let provider = ReviewTestProvider(delay: .milliseconds(70))
        var output = "Previous"
        func sync(_ source: String, enabled: Bool = true) {
            runner.synchronize(enabled: enabled, manualBusy: false, source: source, provider: { _ in provider },
                apply: { _, value, _ in output = value })
        }
        sync("Sarah owns it")
        runner.offer([recommendations[0]], source: "Sarah owns it")
        try await wait { await provider.requests().count == 1 }
        sync("Peter owns it")
        runner.offer([recommendations[0]], source: "Peter owns it")
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertEqual(output, "Reviewed: Peter owns it")
        sync("Peter owns it, Thursday")
        runner.offer([recommendations[0]], source: "Peter owns it, Thursday")
        sync("Peter owns it, Thursday", enabled: false)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(output, "Reviewed: Peter owns it")
        runner.reset()
        sync("Peter owns it")
        runner.offer([recommendations[0]], source: "Peter owns it")
        try await wait { runner.completedCounts[.summary] == 1 }
    }

    func testFailurePreservesOutputAndRetriesWithoutNewSpeech() async throws {
        let runner = AutomaticReviewCoordinator(retryInterval: .milliseconds(30))
        let provider = ReviewTestProvider(failFirst: true)
        var output = "Previous"
        runner.synchronize(enabled: true, manualBusy: false, source: "A question", provider: { _ in provider },
            apply: { _, value, _ in output = value })
        runner.offer([recommendations[0]], source: "A question")
        try await wait { runner.errors[.summary] != nil }
        XCTAssertEqual(output, "Previous")
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertEqual(output, "Reviewed: A question")
        XCTAssertNil(runner.errors[.summary])
    }

    func testUnavailableProviderDoesNotFallbackOrPoll() async throws {
        let runner = AutomaticReviewCoordinator()
        var attempts = 0
        runner.synchronize(enabled: true, manualBusy: false, source: "A question", provider: { _ in
            attempts += 1; throw QuickSummaryError.message("Selected model unavailable")
        }, apply: { _, _, _ in XCTFail("No alternate provider is authorized") })
        runner.offer([recommendations[0]], source: "A question")
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(runner.status(.summary).contains("Selected model unavailable"))
    }

    func testNewerManualReviewRemovesOlderQueuedAutomaticWork() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .milliseconds(20))
        let provider = ReviewTestProvider(delay: .milliseconds(100))
        func sync(_ source: String, busy: Bool) {
            runner.synchronize(enabled: true, manualBusy: busy, source: source, provider: { _ in provider },
                apply: { _, _, _ in XCTFail("A covered automatic review must not publish") })
        }
        sync("First topic", busy: false)
        runner.offer([recommendations[0]], source: "First topic")
        try await wait { await provider.requests().count == 1 }
        sync("First topic with more detail", busy: true)
        XCTAssertTrue(runner.status(.summary).contains("Queued"))
        runner.markManualCompletion(.summary, source: "First topic with more detail")
        sync("First topic with more detail", busy: false)
        try await Task.sleep(for: .milliseconds(130))
        let count = await provider.requests().count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(runner.status(.summary).contains("Up to date"))
    }

    func testEmptyAndOversizedResponsesStopAfterThreeAttemptsAndNewContextCanRetry() async throws {
        for response in ["  ", String(repeating: "x", count: 100_001)] {
            let runner = AutomaticReviewCoordinator(summaryInterval: .zero, retryInterval: .milliseconds(5))
            let provider = ReviewTestProvider(response: response)
            func update(_ source: String) {
                runner.synchronize(enabled: true, manualBusy: false, source: source, provider: { _ in provider },
                    apply: { _, _, _ in XCTFail("Invalid output must not publish") })
                runner.offer([recommendations[0]], source: source)
            }
            update("A question")
            try await wait { runner.errors[.summary]?.contains("paused after repeated failures") == true }
            try await Task.sleep(for: .milliseconds(40))
            let count = await provider.requests().count
            XCTAssertEqual(count, 3)
            update("A question with new context")
            try await wait { await provider.requests().count == 6 }
            runner.reset()
        }
    }

    func testTimeoutAndSourceLimitPreservePreviousOutput() async throws {
        let runner = AutomaticReviewCoordinator(retryInterval: .milliseconds(5), timeout: .milliseconds(10))
        let provider = ReviewTestProvider(delay: .seconds(1))
        runner.synchronize(enabled: true, manualBusy: false, source: "A question", provider: { _ in provider },
            apply: { _, _, _ in XCTFail("Timed out output must not publish") })
        runner.offer([recommendations[0]], source: "A question")
        try await wait { runner.errors[.summary]?.contains("paused after repeated failures") == true }
        let count = await provider.requests().count
        XCTAssertEqual(count, 3)
        runner.reset()
        let source = String(repeating: "a", count: 60_001)
        runner.synchronize(enabled: true, manualBusy: false, source: source,
            provider: { _ in XCTFail("Oversized source must not be sent"); return provider }, apply: { _, _, _ in })
        runner.offer([recommendations[0]], source: source)
        XCTAssertTrue(runner.status(.summary).contains("exceeds the review limit"))
        XCTAssertTrue(runner.status(.deep).contains("Waiting"))
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let satisfied = await condition()
        XCTAssertTrue(satisfied)
    }
}

private actor ReviewTestProvider: LLMProvider {
    nonisolated let id = "review-test"
    let delay: Duration
    var failFirst: Bool
    let response: String?
    var captured: [LLMRequest] = []
    var active = 0
    var maxActive = 0
    init(delay: Duration = .milliseconds(10), failFirst: Bool = false, response: String? = nil) {
        self.delay = delay; self.failFirst = failFirst; self.response = response
    }
    func requests() -> [LLMRequest] { captured }
    func maximum() -> Int { maxActive }
    func respond(_ request: LLMRequest, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        captured.append(request); active += 1; maxActive = max(maxActive, active)
        defer { active -= 1 }
        do {
            try await Task.sleep(for: delay)
            if failFirst { failFirst = false; throw URLError(.networkConnectionLost) }
            continuation.yield(response ?? ("Reviewed: " + request.messages[0].content)); continuation.finish()
        } catch { continuation.finish(throwing: error) }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await respond(request, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
