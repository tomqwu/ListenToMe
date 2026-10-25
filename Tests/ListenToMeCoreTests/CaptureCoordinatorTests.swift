import XCTest
@testable import ListenToMeCore

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    func testConcurrentStopsDrainOnceAndFenceLateEvents() async {
        let coordinator = CaptureCoordinator()
        let gate = CaptureGate()
        var token: CaptureCoordinator.Run?
        var phases: [CaptureCoordinator.Phase] = []
        var stops = 0
        var finishes = 0
        coordinator.phaseChanged = { phases.append($0) }
        XCTAssertTrue(coordinator.start { run in
            token = run
            return .init(prepare: {}, start: {}, stop: {
                stops += 1
                await gate.wait()
            }, didStart: {}, didFinish: { error, recorded in
                XCTAssertNil(error); XCTAssertTrue(recorded)
                XCTAssertEqual(coordinator.phase, .idle)
                XCTAssertFalse(coordinator.acceptsEvents(from: run))
                finishes += 1
            })
        })
        await until { coordinator.phase == .recording }
        let first = Task { await coordinator.stop() }
        await until { stops == 1 }
        let second = Task { await coordinator.stop() }
        await Task.yield()
        XCTAssertTrue(coordinator.acceptsEvents(from: token!)) // final utterances still accepted
        XCTAssertFalse(coordinator.start { _ in XCTFail("must not construct another run"); return self.empty() })
        gate.release()
        await first.value; await second.value
        XCTAssertEqual(stops, 1); XCTAssertEqual(finishes, 1)
        XCTAssertEqual(phases, [.preparing, .recording, .stopping, .idle])
        XCTAssertFalse(coordinator.acceptsEvents(from: token!))
        XCTAssertTrue(coordinator.start { _ in self.empty() })
        XCTAssertFalse(coordinator.acceptsEvents(from: token!))
        await coordinator.stop()
    }

    func testStopDuringUncooperativePreparationNeverStartsAndCleansUpOnce() async {
        let coordinator = CaptureCoordinator()
        let gate = CaptureGate()
        var preparing = false
        var starts = 0
        var stops = 0
        var finishes = 0
        coordinator.start { _ in
            .init(prepare: { preparing = true; await gate.wait(); throw Failure.start }, start: { starts += 1 },
                  stop: { stops += 1 }, didStart: { XCTFail("cancelled preparation started") },
                  didFinish: { error, recorded in
                XCTAssertNil(error); XCTAssertFalse(recorded); finishes += 1
            })
        }
        await until { preparing }
        let first = Task { await coordinator.stop() }
        await until { coordinator.phase == .stopping }
        let second = Task { await coordinator.stop() }
        await Task.yield()
        gate.release()
        await first.value; await second.value
        XCTAssertEqual(starts, 0); XCTAssertEqual(stops, 1); XCTAssertEqual(finishes, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testLateStartCompletionAfterStopCannotEnterRecording() async {
        let coordinator = CaptureCoordinator()
        let gate = CaptureGate()
        var entered = false
        coordinator.start { _ in
            .init(prepare: {}, start: { entered = true; await gate.wait() }, stop: {},
                  didStart: { XCTFail("late completion must not start recognition loops") },
                  didFinish: { error, recorded in XCTAssertNil(error); XCTAssertFalse(recorded) })
        }
        await until { entered }
        let stop = Task { await coordinator.stop() }
        await until { coordinator.phase == .stopping }
        gate.release(); await stop.value
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testStartAndStopFailuresRemainDistinctAndAllowRetry() async {
        let coordinator = CaptureCoordinator()
        var failures: [String] = []
        var recordings: [Bool] = []
        var stops = 0
        let finished: @MainActor (Error?, Bool) -> Void = { error, recorded in
            failures.append(error?.localizedDescription ?? "none"); recordings.append(recorded)
        }
        coordinator.start { _ in
            .init(prepare: {}, start: { throw Failure.start }, stop: { stops += 1; throw Failure.stop },
                  didStart: { XCTFail("failed start") }, didFinish: finished)
        }
        await until { coordinator.phase == .idle }
        XCTAssertEqual(failures, [Failure.start.localizedDescription])
        XCTAssertEqual(recordings, [false]); XCTAssertEqual(stops, 1)
        coordinator.start { _ in
            .init(prepare: {}, start: {}, stop: { throw Failure.stop }, didStart: {}, didFinish: finished)
        }
        await until { coordinator.phase == .recording }
        await coordinator.stop()
        XCTAssertEqual(failures, [Failure.start.localizedDescription, Failure.stop.localizedDescription])
        XCTAssertEqual(recordings, [false, true])
        await coordinator.stop() // idle is a no-op
    }

    func testFinalCheckpointCannotReenterStartBeforeCleanup() async {
        let coordinator = CaptureCoordinator()
        var blocked = 0
        coordinator.phaseChanged = { phase in
            if phase == .idle {
                if !coordinator.start({ _ in self.empty() }) { blocked += 1 }
            }
        }
        coordinator.start { _ in
            .init(prepare: {}, start: {}, stop: {}, didStart: {}, didFinish: { _, _ in
                if !coordinator.start({ _ in self.empty() }) { blocked += 1 }
            })
        }
        await until { coordinator.phase == .recording }
        await coordinator.stop()
        XCTAssertEqual(blocked, 2)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    private func empty() -> CaptureCoordinator.Operations {
        .init(prepare: {}, start: {}, stop: {}, didStart: {}, didFinish: { _, _ in })
    }

    private func until(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("transition did not complete", file: file, line: line)
    }

    private enum Failure: LocalizedError {
        case start, stop
        var errorDescription: String? { self == .start ? "start failure" : "stop failure" }
    }
}

@MainActor private final class CaptureGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
