import XCTest
@testable import ListenToMeCore

@MainActor
final class AutomaticReviewCoordinatorTests: ReviewCoordinatorTestCase {
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
        XCTAssertEqual(requests.map { $0.messages[0].content },
                       ["Azure", "Azure question clarified"].map { PromptData.block("transcript", $0) })
        runner.offer([.init(mode: "deep", confidence: "low", reason: "Unclear")], source: "Azure question clarified")
        try await Task.sleep(for: .milliseconds(30))
        let count = await provider.requests().count
        XCTAssertEqual(count, 2)
    }

    /// Issue #137: queue persistence must not depend on the Quick model reliably re-listing
    /// `pendingReviews`. A read that simply omits a queued mode leaves it queued; only an explicit
    /// signal — a completed review, a conversation/provider change, or a low-confidence downgrade —
    /// drops it.
    func testQueuedReviewSurvivesAnEvaluationThatOmitsItAndIsDroppedByADowngrade() {
        let runner = AutomaticReviewCoordinator()
        let provider = ReviewTestProvider(delay: .seconds(5))
        func sync(_ busy: Bool) {
            runner.synchronize(enabled: true, manualBusy: busy, pieces: live("Azure question"),
                               source: "Azure question", provider: { _ in provider }, apply: { _, _, _ in })
        }
        // Manual work is in flight, so both recommendations stay queued instead of dispatching.
        sync(true)
        runner.offer(recommendations, source: "Azure question")
        XCTAssertEqual(runner.status(.deep), "Auto · Queued; combining new context.")

        runner.offer([recommendations[0]], source: "Azure question")
        XCTAssertEqual(runner.status(.deep), "Auto · Queued; combining new context.",
                       "an omitted mode is not a signal to discard a queued review")
        XCTAssertEqual(runner.status(.summary), "Auto · Queued; combining new context.")

        runner.offer([.init(mode: "deep", confidence: "low", reason: "No longer substantive")],
                     source: "Azure question")
        XCTAssertEqual(runner.status(.deep), "Auto · Waiting for a substantive question or tradeoff.",
                       "an explicit downgrade does drop the queued review")
        XCTAssertEqual(runner.status(.summary), "Auto · Queued; combining new context.")
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
        // Only the shared data-fence notice (#140) is added when no directives are set.
        XCTAssertEqual(requests[0].system,
                       AutomaticReviewMode.summary.instructions + "\n" + PromptData.notice)
        XCTAssertEqual(requests[0].messages[0].content, PromptData.block("transcript", "Azure"))
    }
}
