import XCTest
@testable import ListenToMeCore

/// Issue #235: iOS has no Deep pane, so its coordinator runs Summary reviews only. The Quick
/// evaluator's prompt is shared with macOS and may still recommend Deep; that recommendation must
/// never reach a model on a coordinator that does not run Deep.
@MainActor
final class AutomaticReviewModesTests: ReviewCoordinatorTestCase {
    func testACoordinatorWithoutDeepIgnoresDeepRecommendations() async throws {
        let runner = AutomaticReviewCoordinator(modes: [.summary], summaryInterval: .milliseconds(30))
        XCTAssertEqual(runner.modes, [.summary])
        let provider = ReviewTestProvider()
        var applied: [AutomaticReviewMode] = []
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Why is Azure slow?"),
                           source: "Why is Azure slow?", provider: { _ in provider },
                           apply: { mode, _, _ in applied.append(mode) })
        runner.offer(recommendations, source: "Why is Azure slow?")
        try await wait { runner.completedCounts[.summary] == 1 }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(applied, [.summary])
        XCTAssertNil(runner.completedCounts[.deep])
        let requests = await provider.requests()
        XCTAssertEqual(requests.count, 1, "Only the Summary review reaches the provider")
        XCTAssertEqual(runner.status(.deep), "Auto · Waiting for a substantive question or tradeoff.")
    }

    func testADeepOnlyRecommendationQueuesNothingWithoutDeep() async throws {
        let runner = AutomaticReviewCoordinator(modes: [.summary])
        let provider = ReviewTestProvider()
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Tradeoff"), source: "Tradeoff",
                           provider: { _ in provider }, apply: { _, _, _ in })
        runner.offer([.init(mode: "deep", confidence: "high", reason: "Unresolved tradeoff")], source: "Tradeoff")
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(runner.activeMode)
        let requests = await provider.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testTheDefaultCoordinatorStillRunsEveryMode() {
        XCTAssertEqual(AutomaticReviewCoordinator().modes, Set(AutomaticReviewMode.allCases))
    }
}
