import ListenToMeCore
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileSceneCapabilityTests: XCTestCase {
    func testLateActiveCapabilityCheckDoesNotImportAfterBackground() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox")
        let folder = inbox.appendingPathComponent("pending")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(SharedImport(id: "later", text: "Shared only in foreground", files: []))
            .write(to: folder.appendingPathComponent("manifest.json"))
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        var hold = true
        let session = MobileSession(storageDirectory: root, sharedInbox: inbox, recordingSupport: { _ in
            if hold { return await withCheckedContinuation { pending = $0 } }
            return .ready
        })
        session.applicationIsActive = { true }
        session.notes = "Keep current conversation"
        let active = Task { await session.handleScenePhase(.active) }
        for _ in 0..<400 where pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        await session.handleScenePhase(.background)
        pending?.resume(returning: .ready)
        await active.value
        XCTAssertFalse(session.isForeground)
        XCTAssertEqual(session.notes, "Keep current conversation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "Leave the share queued until a current foreground")
        hold = false
        await session.handleScenePhase(.active)
        XCTAssertEqual(session.notes, "Shared only in foreground")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
