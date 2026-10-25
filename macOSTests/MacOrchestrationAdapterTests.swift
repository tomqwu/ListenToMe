import XCTest
import ListenToMeCore

@MainActor
final class MacOrchestrationAdapterTests: XCTestCase {
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
