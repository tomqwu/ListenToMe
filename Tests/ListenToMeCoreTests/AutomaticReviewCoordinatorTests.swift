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
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Why is Azure slow?"), source: "Why is Azure slow?",
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
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source, provider: { _ in provider }, apply: { _, _, _ in })
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
            runner.synchronize(enabled: true, manualBusy: busy, pieces: live("Azure question"), source: "Azure question", provider: { _ in provider },
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
            runner.synchronize(enabled: enabled, manualBusy: false, pieces: live(source), source: source, provider: { _ in provider },
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
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("A question"), source: "A question", provider: { _ in provider },
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
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("A question"), source: "A question", provider: { _ in
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
            runner.synchronize(enabled: true, manualBusy: busy, pieces: live(source), source: source, provider: { _ in provider },
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
                runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source, provider: { _ in provider },
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

    func testTimeoutIsTerminalForThatInputAndNewSpeechTriesAgain() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero, retryInterval: .milliseconds(5),
                                                timeout: .milliseconds(10))
        let provider = ReviewTestProvider(delay: .seconds(1))
        func update(_ source: String) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source,
                provider: { _ in provider }, apply: { _, _, _ in XCTFail("Timed out output must not publish") })
            runner.offer([recommendations[0]], source: source)
        }
        update("A question")
        try await wait { runner.errors[.summary]?.contains("needed more than") == true }
        try await Task.sleep(for: .milliseconds(60))
        let count = await provider.requests().count
        XCTAssertEqual(count, 1, "The identical oversized request must not be retried")
        XCTAssertTrue(runner.status(.summary).contains("choose a faster model"), runner.status(.summary))
        update("A question")
        try await Task.sleep(for: .milliseconds(30))
        let repeated = await provider.requests().count
        XCTAssertEqual(repeated, 1, "Unchanged input stays terminal")
        update("A question with new context")
        try await wait { await provider.requests().count == 2 }
    }

    func testDeadlineScalesWithModeAndInputSize() {
        let base = Duration.seconds(60)
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .summary, characters: 0), base)
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .deep, characters: 0), .seconds(120))
        // 45,000 characters: 60 s + 60 s x 2.25 = 195 s for Summary, twice that for Deep.
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .summary, characters: 45_000), .seconds(195))
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .deep, characters: 45_000), .seconds(390))
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .deep, characters: 60_000), .seconds(480),
                       "The largest accepted input still gets a finite deadline")
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: .seconds(300), mode: .summary, characters: 60_000),
                       .seconds(300), "Summary is capped at five minutes")
        XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: .seconds(300), mode: .deep, characters: 60_000),
                       .seconds(600), "The cap applies before doubling, so Deep tops out at ten minutes")
        for size in [0, 1_000, 60_000] {
            XCTAssertEqual(AutomaticReviewCoordinator.deadline(base: base, mode: .deep, characters: size),
                AutomaticReviewCoordinator.deadline(base: base, mode: .summary, characters: size) * 2,
                "Deep gets exactly twice Summary's deadline at every size, cap included")
        }
    }

    func testOversizedSourceIsRefusedWithoutSendingIt() {
        let runner = AutomaticReviewCoordinator()
        let source = String(repeating: "a", count: 60_001)
        runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source,
            provider: { _ in XCTFail("Oversized source must not be sent"); return ReviewTestProvider() },
            apply: { _, _, _ in })
        runner.offer([recommendations[0]], source: source)
        XCTAssertTrue(runner.status(.summary).contains("exceeds the review limit"))
        XCTAssertTrue(runner.status(.deep).contains("Waiting"))
    }

    /// A provider's own timeout (URLSession's idle timeout on a stalled connection) is transient,
    /// not "this model is too slow for this input", so it must keep the retry backoff.
    func testProviderNetworkTimeoutStillRetriesWithBackoff() async throws {
        // A backoff long enough that the retrying state is observable under load, but far shorter
        // than the wait helper's deadline.
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero, retryInterval: .milliseconds(150))
        let provider = ReviewTestProvider(failFirst: true, failure: URLError(.timedOut))
        var output = "Previous"
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("A question"), source: "A question",
            provider: { _ in provider }, apply: { _, value, _ in output = value })
        runner.offer([recommendations[0]], source: "A question")
        try await wait { runner.errors[.summary] != nil }
        let status = runner.status(.summary)
        XCTAssertTrue(status.contains("Retrying"), status)
        XCTAssertFalse(status.contains("needed more than"),
                       "A network timeout must not be reported as the model being too slow")
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertEqual(output, "Reviewed: A question", "The identical input is retried after backoff")
        XCTAssertNil(runner.errors[.summary])
    }

    /// #111: the joined input moves whenever an earlier piece changes, so a notes keystroke, a
    /// second channel's partial or a finalized hypothesis used to cancel an in-flight review.
    func testNotesTypingAndSecondChannelSpeechDoNotCancelAnInFlightReview() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero)
        let provider = ReviewTestProvider(delay: .milliseconds(120))
        var output = "Previous"
        func sync(_ pieces: [QuickSummaryContext.Piece]) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: pieces,
                source: pieces.map(\.text).joined(separator: "\n"), provider: { _ in provider },
                apply: { _, value, _ in output = value })
        }
        let started: [QuickSummaryContext.Piece] = [
            .init(id: "notes:0", text: "Notes: ask about budget"),
            .init(id: "live:you:0", text: "You: why is Azure slow"),
            .init(id: "live:others:0", text: "Others: the region is far")
        ]
        sync(started)
        runner.offer([recommendations[0]], source: started.map(\.text).joined(separator: "\n"))
        try await wait { await provider.requests().count == 1 }
        // A notes keystroke, an append in one channel and a finalized hypothesis in the other.
        sync([.init(id: "notes:0", text: "Notes: ask about budget a"),
              .init(id: "live:you:0", text: "You: why is Azure slow today"),
              .init(id: "final:0", text: "Others: the region is far away")])
        XCTAssertEqual(runner.activeMode, .summary, "The running review must survive all three")
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertTrue(output.hasPrefix("Reviewed:"))
        XCTAssertEqual(runner.errors[.summary], nil)
    }

    /// A genuine rewrite of already-final speech still invalidates, and the cancelled attempt must
    /// not spend the mode's cooldown.
    func testFinalRevisionCancelsAndDoesNotBurnTheCooldown() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .seconds(30))
        let provider = ReviewTestProvider(delay: .milliseconds(60))
        var output = "Previous"
        func sync(_ pieces: [QuickSummaryContext.Piece]) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: pieces,
                source: pieces.map(\.text).joined(separator: "\n"), provider: { _ in provider },
                apply: { _, value, _ in output = value })
        }
        func offer(_ pieces: [QuickSummaryContext.Piece]) {
            sync(pieces)
            runner.offer([recommendations[0]], source: pieces.map(\.text).joined(separator: "\n"))
        }
        offer([.init(id: "final:0", text: "You: Sarah owns it")])
        try await wait { await provider.requests().count == 1 }
        offer([.init(id: "final:0", text: "You: Peter owns it")])
        XCTAssertEqual(output, "Previous", "A revised final must cancel the stale review")
        // The cancelled attempt never completed, so the 30-second cooldown must not apply to it.
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertEqual(output, "Reviewed: You: Peter owns it")
    }

    func testUserDirectivesShapeAutomaticRequestsAndStaleJobsKeepTheirOwn() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .milliseconds(10), deepInterval: .milliseconds(10))
        let provider = ReviewTestProvider(delay: .milliseconds(40))
        let chinese = AutomaticReviewDirectives(responseLanguage: "Simplified Chinese",
            personaGuidance: "Act as the hiring manager.", references: "SPEC: rollout gates")
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Why is Azure slow?"), source: "Why is Azure slow?", directives: chinese,
            provider: { _ in provider }, apply: { _, _, _ in })
        runner.offer(recommendations, source: "Why is Azure slow?")
        try await wait { await provider.requests().count == 1 }
        // A settings change mid-flight must not relabel work already queued with the old directives.
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Why is Azure slow?"), source: "Why is Azure slow?",
            directives: .init(responseLanguage: "French"), provider: { _ in provider }, apply: { _, _, _ in })
        try await wait { runner.completedCounts[.deep] == 1 }
        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertTrue(request.system.contains("Simplified Chinese"), request.system)
            XCTAssertTrue(request.system.contains("Act as the hiring manager."), request.system)
            XCTAssertFalse(request.system.contains("French"), "A stale job must not be relabelled")
        }
        XCTAssertTrue(requests[1].messages[0].content.contains("SPEC: rollout gates"),
                      "Deep must receive the attached reference material")
        XCTAssertFalse(requests[0].messages[0].content.contains("SPEC: rollout gates"),
                       "Summary keeps the manual listener contract: transcript evidence only")
    }

    func testNewDirectivesApplyToLaterAutomaticReviews() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero, deepInterval: .zero)
        let provider = ReviewTestProvider()
        func update(_ source: String, _ directives: AutomaticReviewDirectives) {
            runner.synchronize(enabled: true, manualBusy: false, pieces: live(source), source: source, directives: directives,
                provider: { _ in provider }, apply: { _, _, _ in })
            runner.offer([recommendations[0]], source: source)
        }
        update("Azure", .init(responseLanguage: "Simplified Chinese"))
        try await wait { runner.completedCounts[.summary] == 1 }
        update("Azure latency", .init(responseLanguage: "French"))
        try await wait { runner.completedCounts[.summary] == 2 }
        let requests = await provider.requests()
        XCTAssertTrue(requests[0].system.contains("Simplified Chinese"))
        XCTAssertTrue(requests[1].system.contains("French"))
    }

    func testAbsentDirectivesLeaveTheReviewInstructionsUnchanged() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .zero)
        let provider = ReviewTestProvider()
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Azure"), source: "Azure",
            provider: { _ in provider }, apply: { _, _, _ in })
        runner.offer([recommendations[0]], source: "Azure")
        try await wait { runner.completedCounts[.summary] == 1 }
        let requests = await provider.requests()
        XCTAssertEqual(requests[0].system, AutomaticReviewMode.summary.instructions)
        XCTAssertEqual(requests[0].messages[0].content, "Azure")
    }

    /// One provisional live piece per snapshot: appended speech extends it, a rewrite replaces it.
    private func live(_ source: String) -> [QuickSummaryContext.Piece] {
        [.init(id: "live:you:0", text: source)]
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
    let failure: any Error
    init(delay: Duration = .milliseconds(10), failFirst: Bool = false, response: String? = nil,
         failure: any Error = URLError(.networkConnectionLost)) {
        self.delay = delay; self.failFirst = failFirst; self.response = response; self.failure = failure
    }
    func requests() -> [LLMRequest] { captured }
    func maximum() -> Int { maxActive }
    func respond(_ request: LLMRequest, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        captured.append(request); active += 1; maxActive = max(maxActive, active)
        defer { active -= 1 }
        do {
            try await Task.sleep(for: delay)
            if failFirst { failFirst = false; throw failure }
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
