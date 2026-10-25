import XCTest
@testable import ListenToMeCore

@MainActor
final class CaptureRestartTests: XCTestCase {
    func testStopInterruptsPreparationThatIgnoresTaskCancellation() async {
        let capture = CaptureCoordinator()
        let gate = RestartGate()
        var starts = 0
        var interruptions = 0
        capture.start { _ in
            .init(prepare: { await gate.wait() }, start: { starts += 1 }, stop: {}, interrupt: {
                interruptions += 1; gate.release()
            }, didStart: {}, didFinish: { _, _ in })
        }
        await until { gate.held }
        await capture.stop()
        XCTAssertEqual(interruptions, 1)
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(capture.wantsCapture)
        XCTAssertEqual(capture.phase, .idle)
    }

    func testNewestRestartWinsAndPreservesIntentThroughOldDrain() async {
        let capture = CaptureCoordinator()
        let drain = RestartGate()
        var starts: [String] = []
        var stops = 0
        capture.start { _ in
            .init(prepare: {}, start: { starts.append("initial") }, stop: { stops += 1; await drain.wait() },
                  didStart: {}, didFinish: { _, _ in XCTAssertTrue(capture.wantsCapture) })
        }
        await until { capture.phase == .recording }
        capture.restart { _ in self.operations(start: { starts.append("old locale") }) }
        await until { drain.held }
        XCTAssertTrue(capture.wantsCapture)
        capture.restart { _ in self.operations(start: { starts.append("new locale") }) }
        await Task.yield()
        drain.release()
        await until { starts.count == 2 && capture.phase == .recording }
        XCTAssertEqual(starts, ["initial", "new locale"])
        XCTAssertEqual(stops, 1)
        await capture.stop()
    }

    func testStopDuringRestartNeverResumesRecordingAndAwaitsCheckpoint() async {
        let capture = CaptureCoordinator()
        let drain = RestartGate()
        var checkpoints = 0
        capture.start { _ in
            .init(prepare: {}, start: {}, stop: { await drain.wait() }, didStart: {}, didFinish: { _, _ in })
        }
        await until { capture.phase == .recording }
        capture.restart { _ in XCTFail("Stop must discard the restart"); return self.operations() }
        await until { drain.held }
        capture.requestStop(after: { XCTAssertEqual(capture.phase, .idle); checkpoints += 1 })
        XCTAssertFalse(capture.wantsCapture)
        XCTAssertEqual(checkpoints, 0)
        drain.release()
        await until { checkpoints == 1 }
        XCTAssertEqual(capture.phase, .idle)
        capture.restart { _ in XCTFail("idle cannot restart"); return self.operations() }
    }

    func testRestartFailureClearsIntentAndAllowsFreshStart() async {
        let capture = CaptureCoordinator()
        capture.start { _ in self.operations() }
        await until { capture.phase == .recording }
        capture.restart { _ in self.operations(start: { throw NSError(domain: "test", code: 1) }) }
        await until { capture.phase == .idle && !capture.wantsCapture }
        XCTAssertTrue(capture.start { _ in self.operations() })
        await capture.stop()
    }

    func testStopCheckpointRunsBeforeAnotherStartAndBackgroundDoesNotHoldCapture() async {
        let capture = CaptureCoordinator()
        let background = RestartGate()
        var checkpoint = false
        var rejectedStart = false
        capture.start { _ in self.operations() }
        await until { capture.phase == .recording }
        capture.requestStop(after: {
            XCTAssertEqual(capture.phase, .idle)
            rejectedStart = !capture.start { _ in self.operations() }
            checkpoint = true
        }, background: { await background.wait() })
        await until { checkpoint && background.held }
        XCTAssertTrue(rejectedStart)
        XCTAssertTrue(capture.start { _ in self.operations() })
        await until { capture.phase == .recording }
        background.release()
        await capture.stop()
    }

    func testReentrantStopCompletionCannotStopAFutureRun() async {
        let capture = CaptureCoordinator()
        var callbacks = 0
        capture.start { _ in self.operations() }
        await until { capture.phase == .recording }
        capture.requestStop(after: {
            callbacks += 1
            capture.requestStop(after: { callbacks += 1 })
        })
        await until { callbacks == 2 }
        XCTAssertTrue(capture.start { _ in self.operations() })
        await until { capture.phase == .recording }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(capture.phase, .recording)
        XCTAssertTrue(capture.wantsCapture)
        await capture.stop()
    }

    private func operations(start: @escaping @MainActor () async throws -> Void = {}) -> CaptureCoordinator.Operations {
        .init(prepare: {}, start: start, stop: {}, didStart: {}, didFinish: { _, _ in })
    }

    private func until(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("transition did not complete", file: file, line: line)
    }
}

@MainActor private final class RestartGate {
    var continuation: CheckedContinuation<Void, Never>?
    var held: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
