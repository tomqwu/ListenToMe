import XCTest
@testable import ListenToMeCore

/// Failure, retry, deadline and oversized-input behaviour of `AutomaticReviewCoordinator`.
/// Split from `AutomaticReviewCoordinatorTests` so neither class outgrows one file.
@MainActor
final class AutomaticReviewFailureTests: ReviewCoordinatorTestCase {

    /// #161: split from the retry assertion below. The failure notice is *transient* — `pump`
    /// clears it the moment the retry is dispatched — so waiting for it while a 30 ms backoff is
    /// running is a race the CI runner loses. A retry interval longer than the test makes the
    /// failure state terminal, so this waits on a state that stays put instead of on a window.
    func testFailurePreservesPreviousOutputAndSaysItWillRetry() async throws {
        let runner = AutomaticReviewCoordinator(retryInterval: .seconds(60))
        let provider = ReviewTestProvider(failFirst: true)
        var output = "Previous"
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("A question"), source: "A question", provider: { _ in provider },
            apply: { _, value, _ in output = value })
        runner.offer([recommendations[0]], source: "A question")
        try await wait { runner.errors[.summary] != nil }
        XCTAssertEqual(output, "Previous", "A failed review never replaces the output already on screen")
        XCTAssertTrue(runner.status(.summary).contains("Retrying."), runner.status(.summary))
        XCTAssertNil(runner.completedCounts[.summary])
    }

    /// The other half: the retry needs no new speech. The end state here is terminal too — the
    /// review either completes or it does not — so there is no window to miss.
    func testAFailedReviewRetriesWithoutNewSpeech() async throws {
        let runner = AutomaticReviewCoordinator(retryInterval: .milliseconds(30))
        let provider = ReviewTestProvider(failFirst: true)
        var output = "Previous"
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("A question"), source: "A question", provider: { _ in provider },
            apply: { _, value, _ in output = value })
        runner.offer([recommendations[0]], source: "A question")
        try await wait { runner.completedCounts[.summary] == 1 }
        XCTAssertEqual(output, "Reviewed: A question")
        XCTAssertNil(runner.errors[.summary])
        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 2, "The retry reuses the same evidence; no new speech is needed")
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
}
