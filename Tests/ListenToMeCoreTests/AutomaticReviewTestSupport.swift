import XCTest
@testable import ListenToMeCore

// Shared fixtures for the automatic-review suites, which are split across two files so neither
// class outgrows what one file should hold.

/// Recommendations, the live-piece snapshot and the polling helper every review test uses.
@MainActor
class ReviewCoordinatorTestCase: XCTestCase {
    let recommendations = [
        QuickSummaryDecision.Review(mode: "summary", confidence: "high", reason: "New topic"),
        QuickSummaryDecision.Review(mode: "deep", confidence: "medium", reason: "Substantive question")
    ]

    /// One provisional live piece per snapshot: appended speech extends it, a rewrite replaces it.
    func live(_ source: String) -> [QuickSummaryContext.Piece] {
        [.init(id: "live:you:0", text: source)]
    }

    func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let satisfied = await condition()
        XCTAssertTrue(satisfied)
    }
}

actor ReviewTestProvider: LLMProvider {
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
    /// Strips the `<transcript>` fence the shared builders add (#140).
    nonisolated static func unfenced(_ content: String) -> String {
        content.replacingOccurrences(of: "<transcript>\n", with: "")
            .replacingOccurrences(of: "\n</transcript>", with: "")
    }
    func respond(_ request: LLMRequest, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        captured.append(request); active += 1; maxActive = max(maxActive, active)
        defer { active -= 1 }
        do {
            try await Task.sleep(for: delay)
            if failFirst { failFirst = false; throw failure }
            // Echo the transcript it was handed, minus the data fence (#140), so the assertions
            // read the evidence the review actually received.
            continuation.yield(response ?? ("Reviewed: " + Self.unfenced(request.messages[0].content)))
            continuation.finish()
        } catch { continuation.finish(throwing: error) }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await respond(request, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
