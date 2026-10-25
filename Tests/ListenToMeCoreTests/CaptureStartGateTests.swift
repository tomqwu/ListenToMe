import XCTest
@testable import ListenToMeCore

@MainActor
final class CaptureStartGateTests: XCTestCase {
    func testClosingDuringCapabilityCheckNeverRequestsPermissionOrStartsCapture() async throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        var permissionCalls = 0, captures = 0
        var pending: CheckedContinuation<Bool, Never>?
        let work = Task {
            try await gate.perform(token, prepare: { await withCheckedContinuation { pending = $0 } },
                authorize: { permissionCalls += 1; return true }, start: { captures += 1 })
        }
        for _ in 0..<400 where pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        gate.close()
        pending?.resume(returning: true)
        let started = try await work.value
        XCTAssertFalse(started)
        XCTAssertEqual(permissionCalls, 0)
        XCTAssertEqual(captures, 0)
        XCTAssertNil(gate.begin(), "A closed window cannot accept another Start")
    }

    func testCancelledPermissionGrantCannotStartAnOldConversation() async throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        var captures = 0
        var pending: CheckedContinuation<Bool, Never>?
        let work = Task {
            try await gate.perform(token, prepare: { true },
                authorize: { await withCheckedContinuation { pending = $0 } }, start: { captures += 1 })
        }
        for _ in 0..<400 where pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        gate.cancel() // New conversation or Stop
        let newToken = try XCTUnwrap(gate.begin())
        pending?.resume(returning: true)
        let started = try await work.value
        XCTAssertFalse(started)
        XCTAssertEqual(captures, 0)
        XCTAssertTrue(gate.isPending, "Late completion must not clear a newer Start")
        let newStarted = try await gate.perform(newToken, prepare: { true }, authorize: { true }, start: { captures += 1 })
        XCTAssertTrue(newStarted)
        XCTAssertEqual(captures, 1)
    }

    func testStopBeforeTheTaskBeginsAndTaskCancellationPreventCapture() async throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        var checks = 0, captures = 0
        gate.cancel()
        let stopped = try await gate.perform(token, prepare: { checks += 1; return true },
            authorize: { true }, start: { captures += 1 })
        XCTAssertFalse(stopped)
        XCTAssertEqual(checks, 0)
        let cancelledToken = try XCTUnwrap(gate.begin())
        let work = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await gate.perform(cancelledToken, prepare: { true }, authorize: { true }, start: { captures += 1 })
        }
        let started = try await work.value
        XCTAssertFalse(started)
        XCTAssertEqual(captures, 0)
    }

    func testLateDeniedPermissionDoesNotPublishAnErrorInANewConversation() async throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        var errors: [String] = []
        var pending: CheckedContinuation<CapturePreflight.Decision, Never>?
        let work = Task {
            await gate.resolvePermission(token, check: { await withCheckedContinuation { pending = $0 } },
                                         onBlocked: { errors.append($0) })
        }
        for _ in 0..<400 where pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        gate.cancel()
        let next = try XCTUnwrap(gate.begin())
        pending?.resume(returning: .blocked(message: "Old permission denial", canOpenSettings: true))
        let allowed = await work.value
        XCTAssertFalse(allowed)
        XCTAssertTrue(errors.isEmpty, "A cancelled conversation must not publish its late permission failure")
        XCTAssertTrue(gate.isCurrent(next))
        let denied = await gate.resolvePermission(next, check: { .blocked(message: "Current denial", canOpenSettings: true) },
                                                 onBlocked: { errors.append($0) })
        XCTAssertFalse(denied)
        XCTAssertEqual(errors, ["Current denial"])
    }

    func testCancelledStartNeverRequestsPermissionEvenBeforeCallbackWorkBegins() async throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        gate.cancel()
        var requests = 0
        let allowed = await gate.resolvePermission(token, check: { requests += 1; return .start },
                                                  onBlocked: { _ in XCTFail("No obsolete failure") })
        XCTAssertFalse(allowed)
        XCTAssertEqual(requests, 0)
    }

    func testOnePendingStartAndExplicitReopen() throws {
        let gate = CaptureStartGate()
        let token = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.isPending)
        XCTAssertNil(gate.begin())
        gate.finish(token)
        XCTAssertFalse(gate.isPending)
        gate.close()
        XCTAssertNil(gate.begin())
        gate.reopen()
        XCTAssertNotNil(gate.begin())
    }
}
