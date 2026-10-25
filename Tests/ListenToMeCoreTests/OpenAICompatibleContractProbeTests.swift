import XCTest
@testable import ListenToMeCore

final class OpenAICompatibleContractProbeTests: XCTestCase {
    func testSyntheticProbeUsesTheActualEvaluatorAndValidResultClearsFailure() async throws {
        let provider = RecordingProvider(deltas: [#"{"reviews":[],"action":"keep","context":"Proposal only","bullets":[]}"#])
        let outcome = try await OpenAICompatibleContractProbe.run(provider: provider)
        XCTAssertEqual(outcome, .compatible)
        XCTAssertEqual(outcome.ledgerResult, true)
        XCTAssertEqual(provider.lastRequest?.purpose, .quickEvaluation)
        XCTAssertTrue(provider.lastUser?.contains("Dana") == true)
    }

    func testMalformedAnswerPausesAutoButTransportFailureKeepsPriorResult() async throws {
        let outcome = try await OpenAICompatibleContractProbe.run(provider: MockLLMProvider(id: "mock", deltas: ["ordinary prose"]))
        guard case .incompatible = outcome else { return XCTFail("Malformed model answer must fail compatibility") }
        XCTAssertEqual(outcome.ledgerResult, false)
        let unavailable = try await OpenAICompatibleContractProbe.run(provider: FailingProbe(error: URLError(.cannotConnectToHost)))
        guard case .unavailable = unavailable else { return XCTFail("A network failure is not a model format failure") }
        XCTAssertNil(unavailable.ledgerResult)
    }

    func testProviderCancellationNeverReturnsAPersistableOutcome() async {
        do {
            _ = try await OpenAICompatibleContractProbe.run(provider: FailingProbe(error: CancellationError()))
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testCancelledBeforeStartSendsNothing() async {
        let provider = RecordingProvider(deltas: ["ordinary prose"])
        let task = Task { try await OpenAICompatibleContractProbe.run(provider: provider) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(provider.requestCount, 0)
    }
}

private struct FailingProbe: LLMProvider {
    let id = "failing-probe"
    let error: any Error
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}
