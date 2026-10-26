import XCTest
@testable import ListenToMeCore

@MainActor
final class SpeakerPassCoordinatorTests: XCTestCase {
    func testResetDuringUncooperativePreparationNeverEntersOldAnalysis() async {
        let work = SpeakerPassCoordinator()
        let oldGate = SpeakerWorkGate(), newGate = SpeakerWorkGate()
        var analyzed: [String] = []
        let old = work.start(prepare: { await oldGate.hold() }, operation: { analyzed.append("old") })
        await oldGate.waitUntilHeld()
        work.cancel()
        let current = work.start(prepare: { await newGate.hold() }, operation: { analyzed.append("new") })
        await newGate.waitUntilHeld()
        oldGate.release()
        await old.value
        XCTAssertTrue(analyzed.isEmpty)
        XCTAssertTrue(work.isRunning, "Old completion cannot clear the new pass")
        newGate.release()
        await current.value
        XCTAssertEqual(analyzed, ["new"])
        XCTAssertFalse(work.isRunning)
    }

    func testCancelledInFlightAnalysisCannotClearReplacementTask() async {
        let work = SpeakerPassCoordinator()
        let oldGate = SpeakerWorkGate(), newGate = SpeakerWorkGate()
        let old = work.start { await oldGate.hold() }
        await oldGate.waitUntilHeld()
        let current = work.start { await newGate.hold() }
        await newGate.waitUntilHeld()
        oldGate.release()
        await old.value
        XCTAssertTrue(work.isRunning)
        newGate.release()
        await current.value
        await work.wait()
        XCTAssertFalse(work.isRunning)
    }

    func testWaitingForOldPassDoesNotWaitForLaterRecording() async {
        let work = SpeakerPassCoordinator()
        let oldGate = SpeakerWorkGate(), newGate = SpeakerWorkGate()
        let old = work.start { await oldGate.hold() }
        await oldGate.waitUntilHeld()
        var waiting = false, finished = false
        let waiter = Task { waiting = true; await work.wait(); finished = true }
        for _ in 0..<10_000 {
            if waiting { break }
            await Task.yield()
        }
        XCTAssertTrue(waiting)
        let current = work.start { await newGate.hold() }
        await newGate.waitUntilHeld()
        oldGate.release()
        await old.value
        for _ in 0..<10_000 {
            if finished { break }
            await Task.yield()
        }
        XCTAssertTrue(finished, "The old wait must finish without waiting for the new recording")
        XCTAssertTrue(work.isRunning, "The old wait finishes while the new pass is still held")
        newGate.release()
        await current.value
        await waiter.value
    }

    func testCancellationBeforeTaskStartsSkipsPreparationAndOperation() async {
        let work = SpeakerPassCoordinator()
        var calls = 0
        let task = work.start(prepare: { calls += 1 }, operation: { calls += 1 })
        work.cancel()
        await task.value
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(work.isRunning)
    }

    func testWaitDrainsObservedPassAndDirectCancellationClearsOwnership() async {
        let work = SpeakerPassCoordinator(), gate = SpeakerWorkGate()
        let task = work.start(prepare: { await gate.hold() }, operation: { XCTFail("Cancelled pass") })
        await gate.waitUntilHeld()
        var finished = false
        let waiter = Task { await work.wait(); finished = true }
        await Task.yield()
        XCTAssertFalse(finished)
        task.cancel()
        gate.release()
        await task.value
        await waiter.value
        XCTAssertTrue(finished)
        XCTAssertFalse(work.isRunning)
    }
}

@MainActor
private final class SpeakerWorkGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilHeld() async {
        for _ in 0..<10_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        XCTFail("Speaker work did not reach its gate")
    }
}
