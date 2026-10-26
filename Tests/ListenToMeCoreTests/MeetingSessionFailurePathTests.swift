import XCTest
@testable import ListenToMeCore

@MainActor
final class MeetingSessionFailurePathTests: XCTestCase {
    private func session(capture: any AudioCapturing = StartFailureCapture(),
                         provider: any LLMProvider = ImmediateFailureProvider()) -> MeetingSession {
        MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                       makeCapture: { capture }, makeTranscriber: { MockTranscriber() },
                       makeProvider: { _ in provider }, models: [.quick: "Q", .listener: "L", .deep: "D"])
    }

    func testCaptureStartFailureRollsBackRunningAndPreparationState() async {
        let capture = StartFailureCapture()
        let model = session(capture: capture)
        do { try await model.start(); XCTFail("Expected capture failure") } catch {
            XCTAssertEqual(error.localizedDescription, "Fixture failure")
        }
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isPreparing)
        XCTAssertEqual(model.captureMessages[.you], "start failed")
        XCTAssertEqual(model.captureMessages[.others], "stopped")
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testCancellationDoesNotShowAProvidersLateFailure() async {
        let provider = HeldFailureProvider()
        let model = session(provider: provider)
        let response = Task { await model.respondQuick(.answerQuestion) }
        await provider.waitUntilStarted()
        model.cancelResponse(.quick)
        provider.fail()
        await response.value
        XCTAssertNil(model.roleError(.quick))
        XCTAssertFalse(model.quickSuggestion.contains("⚠️"), model.quickSuggestion)
        XCTAssertFalse(model.streamingRoles.contains(.quick))
    }
}

private struct FixtureFailure: LocalizedError {
    var errorDescription: String? { "Fixture failure" }
}

private final class StartFailureCapture: AudioCapturing, @unchecked Sendable {
    let chunks = AsyncStream<AudioChunk> { $0.finish() }
    private let lock = NSLock()
    private var stops = 0
    var stopCount: Int { lock.withLock { stops } }
    func start() async throws { throw FixtureFailure() }
    func stop() { lock.withLock { stops += 1 } }
}

private struct ImmediateFailureProvider: LLMProvider {
    let id = "failure"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: FixtureFailure()) }
    }
}

private final class HeldFailureProvider: LLMProvider, @unchecked Sendable {
    let id = "held-failure"
    private let lock = NSLock()
    private var output: AsyncThrowingStream<String, Error>.Continuation?
    private let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { output = continuation }
            started.continuation.yield(())
        }
    }
    func waitUntilStarted() async { for await _ in started.stream { return } }
    func fail() { lock.withLock { output }?.finish(throwing: FixtureFailure()) }
}
