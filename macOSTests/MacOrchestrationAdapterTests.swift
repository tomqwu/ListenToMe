import XCTest
import ListenToMeCore

@MainActor
final class MacOrchestrationAdapterTests: XCTestCase {
    func testStopFinishesBeforeTheOSPermissionCallbackAndIgnoresItsLateDenial() async {
        await checkStopBeforePermissionReturns(.blocked(message: "Obsolete denial", canOpenSettings: true))
    }

    func testStopFinishesBeforeTheOSPermissionCallbackAndIgnoresItsLateGrant() async {
        await checkStopBeforePermissionReturns(.start)
    }

    private func checkStopBeforePermissionReturns(_ decision: CapturePreflight.Decision) async {
        let gate = CaptureStartGate()
        let capture = CaptureCoordinator()
        var pending: CheckedContinuation<CapturePreflight.Decision, Never>?
        var errors: [String] = []
        var starts = 0
        capture.start { _ in
            .init(prepare: {
                try await MacCapturePreflight.prepare(gate: gate, refresh: { .ready }, permission: {
                    await withCheckedContinuation { pending = $0 }
                }, blocked: { errors.append($0) })
            }, start: { starts += 1 }, stop: {}, didStart: {}, didFinish: { error, _ in
                if let error { errors.append(error.localizedDescription) }
            })
        }
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        let stopped = expectation(description: "Stop returns without waiting for OS consent")
        let stop = Task { await capture.stop(); stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 0.5)
        XCTAssertEqual(capture.phase, .idle)
        XCTAssertFalse(gate.isPending)
        let retry = capture.start { _ in
            .init(prepare: {}, start: { starts += 1 }, stop: {}, didStart: {}, didFinish: { _, _ in })
        }
        XCTAssertTrue(retry, "A cancelled permission request must not hold the next recording")
        for _ in 0..<200 where capture.phase != .recording { try? await Task.sleep(for: .milliseconds(5)) }
        pending?.resume(returning: decision)
        await stop.value
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(errors.isEmpty)
        if retry { XCTAssertEqual(capture.phase, .recording) }
        await capture.stop()
    }

    func testCancellationBeforePreflightBeginsNeverChecksCapabilitiesOrRequestsPermission() async {
        let gate = CaptureStartGate()
        let work = Task {
            do {
                try await MacCapturePreflight.prepare(gate: gate, refresh: {
                    XCTFail("Cancelled Start must not inspect native capabilities"); return .ready
                }, permission: { XCTFail("Cancelled Start must not request permission"); return .start },
                blocked: { _ in XCTFail("No cancelled error") })
                XCTFail("Cancelled preparation cannot authorize capture")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        work.cancel()
        await work.value
        XCTAssertFalse(gate.isPending)
    }

    func testCancelDuringUnresponsiveCapabilityCheckDoesNotRequestPermission() async {
        let gate = CaptureStartGate()
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        var permissions = 0
        let finished = expectation(description: "Cancelled capability check returns")
        let work = Task {
            do {
                try await MacCapturePreflight.prepare(gate: gate, refresh: {
                    await withCheckedContinuation { pending = $0 }
                }, permission: { permissions += 1; return .start }, blocked: { _ in XCTFail("Obsolete error") })
                XCTFail("Cancelled preparation cannot authorize capture")
            } catch { XCTAssertTrue(error is CancellationError) }
            finished.fulfill()
        }
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        work.cancel()
        await fulfillment(of: [finished], timeout: 0.5)
        XCTAssertFalse(gate.isPending)
        pending?.resume(returning: .ready)
        await work.value
        XCTAssertEqual(permissions, 0)
    }

    func testUnsupportedCapabilityAndCancelledPermissionNeverAuthorizeCapture() async {
        let gate = CaptureStartGate()
        var permissions = 0
        do {
            try await MacCapturePreflight.prepare(gate: gate, refresh: { .unsupported(reason: "Choose a language") },
                permission: { permissions += 1; return .start }, blocked: { _ in XCTFail("No permission request") })
            XCTFail("Unsupported capture was authorized")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(permissions, 0)
        XCTAssertFalse(gate.isPending)
        do {
            try await MacCapturePreflight.prepare(gate: gate, refresh: { .ready }, permission: {
                permissions += 1
                gate.cancel() // Stop/New arrives while the OS callback is pending.
                return .blocked(message: CapturePreflight.deniedMessage, canOpenSettings: true)
            }, blocked: { _ in XCTFail("An obsolete denial cannot replace the new conversation's message") })
            XCTFail("Cancelled capture was authorized")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(permissions, 1)
        XCTAssertFalse(gate.isPending)
    }

    func testCheckpointPrivacyFailureRetryAndStatusUseDurableState() {
        let controller = MacCheckpointController()
        let key = SessionCheckpointKey(revision: 1, title: "Meeting", summary: "", notes: "",
                                       quickSuggestion: "", deepAnswer: "", complete: false)
        let record = SessionRecord(id: "test", title: "Meeting", date: Date(), transcript: "Words", summary: "")
        var allowed = false, writeSucceeds = false
        var assembled = 0, writes = 0, saved = 0
        func checkpoint() -> Bool {
            controller.checkpoint(allowed: allowed, hasContent: true, force: false, makeKey: { key },
                makeRecord: { _ in assembled += 1; return record },
                persist: { _ in writes += 1; return writeSucceeds }, errorText: { "Disk full" },
                didSave: { _ in saved += 1 })
        }
        XCTAssertFalse(checkpoint())
        XCTAssertEqual(assembled, 0)
        XCTAssertEqual(writes, 0)
        allowed = true
        XCTAssertFalse(checkpoint())
        XCTAssertTrue(controller.failed)
        XCTAssertEqual(controller.message, "Disk full")
        XCTAssertNil(controller.coordinator.startedAt)
        writeSucceeds = true
        XCTAssertTrue(checkpoint())
        XCTAssertFalse(controller.failed)
        XCTAssertTrue(controller.message.hasPrefix("Saved at"))
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(saved, 1)
        XCTAssertTrue(checkpoint())
        XCTAssertEqual(writes, 2, "Unchanged content must not be written again")
        XCTAssertEqual(assembled, 2)
    }
}
