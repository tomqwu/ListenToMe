import XCTest
@testable import ListenToMeCore

final class RecognitionFinalizationTests: XCTestCase {
    func testFinalCallbacksBeforeWaitAreRetained() async {
        let first = UUID(), second = UUID()
        let drain = RecognitionFinalization(tokens: [first, second])
        await drain.complete(first)
        await drain.complete(second)
        let result = await drain.wait(timeout: .zero)
        XCTAssertTrue(result)
    }

    func testLateFinalCallbackCompletesWait() async {
        let token = UUID()
        let drain = RecognitionFinalization(tokens: [token])
        let waiting = Task { await drain.wait(timeout: .seconds(5)) }
        await drain.complete(token)
        let result = await waiting.value
        XCTAssertTrue(result)
    }

    func testUnknownCallbackCannotCompleteDrainAndDeadlineIsTerminal() async {
        let token = UUID()
        let drain = RecognitionFinalization(tokens: [token])
        await drain.complete(UUID())
        let expired = await drain.wait(timeout: .zero)
        XCTAssertFalse(expired)
        await drain.complete(token)
        let late = await drain.wait(timeout: .seconds(1))
        XCTAssertFalse(late)
    }

    func testCancellationEndsWait() async {
        let drain = RecognitionFinalization(tokens: [UUID()])
        let waiting = Task { await drain.wait(timeout: .seconds(60)) }
        waiting.cancel()
        let result = await waiting.value
        XCTAssertFalse(result)
    }
}
