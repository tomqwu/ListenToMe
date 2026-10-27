import XCTest
@testable import ListenToMeWatch

@MainActor
final class WatchPreparationTests: XCTestCase {
    func testCancelBeforeFirstTaskTurnRunsNoOperation() async {
        let owner = WatchPreparation()
        var operations = 0
        owner.run(operation: { operations += 1 })
        owner.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(operations, 0)
    }

    func testSupersededBeforeFirstTurnRunsOnlyTheNewOperation() async {
        let owner = WatchPreparation()
        var old = 0, newer = 0
        owner.run(operation: { old += 1 })
        owner.run(operation: { newer += 1 })
        await eventually { newer == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(old, 0)
        XCTAssertEqual(newer, 1)
    }

    func testOwnerReleasedBeforeFirstTurnRunsNoOperation() async {
        var owner: WatchPreparation? = WatchPreparation()
        weak var released = owner
        var operations = 0
        owner?.run(operation: { operations += 1 })
        owner = nil
        XCTAssertNil(released)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(operations, 0)
    }

    func testInactivePermissionUIKeepsPreparationAndAllowsGrant() async {
        let owner = WatchPreparation(), gate = PermissionReplyFixture()
        var successes = 0, cancellations = 0
        defer { owner.cancel(); gate.resolve(.success(())) }
        owner.run(operation: { try await gate.wait() }, onSuccess: { successes += 1 })
        await eventually { gate.isWaiting }
        owner.sceneChanged(.inactive) { cancellations += 1 }
        XCTAssertTrue(owner.isPending, "A permission overlay is not app departure")
        XCTAssertEqual(cancellations, 0)
        gate.resolve(.success(()))
        await eventually { !owner.isPending }
        XCTAssertEqual(successes, 1)
        XCTAssertNil(owner.problem)
        owner.sceneChanged(.background) { cancellations += 1 }
        XCTAssertEqual(cancellations, 0, "Finished capture is no longer pending preparation")
    }

    func testLateGrantAfterBackgroundCannotFinishANewerAttempt() async {
        let owner = WatchPreparation(), old = PermissionReplyFixture(), newer = PermissionReplyFixture()
        var successes = 0, failures = 0, cancellations = 0
        defer { owner.cancel(); old.resolve(.success(())); newer.resolve(.success(())) }
        owner.run(operation: { try await old.wait() }, onSuccess: { successes += 1 }, onFailure: { failures += 1 })
        await eventually { old.isWaiting }
        owner.sceneChanged(.background) { cancellations += 1 }
        XCTAssertFalse(owner.isPending, "Departure releases the UI without waiting for the OS reply")
        owner.run(operation: { try await newer.wait() }, onSuccess: { successes += 1 }, onFailure: { failures += 1 })
        await eventually { newer.isWaiting }
        old.resolve(.success(()))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(owner.isPending, "An old completion cannot clear the new busy state")
        XCTAssertNil(owner.problem)
        XCTAssertEqual(successes, 0)
        newer.resolve(.success(()))
        await eventually { !owner.isPending }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(cancellations, 1)
    }

    func testLateDenialAfterDismissalCannotSetANewerErrorOrHaptic() async {
        let owner = WatchPreparation(), old = PermissionReplyFixture(), newer = PermissionReplyFixture()
        var successes = 0, failures = 0
        defer { owner.cancel(); old.resolve(.success(())); newer.resolve(.success(())) }
        owner.run(operation: { try await old.wait() }, onFailure: { failures += 1 })
        await eventually { old.isWaiting }
        owner.cancel()
        owner.run(operation: { try await newer.wait() }, onSuccess: { successes += 1 }, onFailure: { failures += 1 })
        await eventually { newer.isWaiting }
        old.resolve(.failure(NSError(domain: "PermissionFixture", code: 1)))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(owner.isPending)
        XCTAssertNil(owner.problem)
        XCTAssertEqual(failures, 0)
        newer.resolve(.success(()))
        await eventually { !owner.isPending }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(failures, 0)
    }

    private func eventually(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(predicate(), "Expected native preparation transition was not observed")
    }
}

/// Intentionally ignores Task cancellation, like a system consent reply that can arrive later.
@MainActor
private final class PermissionReplyFixture {
    private var reply: CheckedContinuation<Void, any Error>?
    var isWaiting: Bool { reply != nil }
    func wait() async throws { try await withCheckedThrowingContinuation { reply = $0 } }
    func resolve(_ result: Result<Void, any Error>) {
        let pending = reply
        reply = nil
        pending?.resume(with: result)
    }
}
