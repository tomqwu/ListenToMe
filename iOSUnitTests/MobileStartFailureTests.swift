import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileStartFailureTests: XCTestCase {
    func testStartFailureStaysActionableUntilRetryAndDoesNotReplaceTheNextSuccessfulRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StartFailureRecorder()
        recorder.failure = RecordingError.message("The speech model could not be downloaded.")
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        session.start()
        for _ in 0..<400 where session.state == .preparing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.recordingStartFailure, "The speech model could not be downloaded.")
        session.message = "A different status update"
        XCTAssertEqual(session.recordingStartFailure, "The speech model could not be downloaded.")
        recorder.failure = nil
        session.start()
        XCTAssertNil(session.recordingStartFailure)
        for _ in 0..<400 where session.state == .preparing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        XCTAssertNil(session.recordingStartFailure)
        await session.stop()
    }

    func testCancelledPreparationDoesNotShowAStartFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StartFailureRecorder()
        recorder.waitDuringPreparation = true
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        session.start()
        for _ in 0..<400 where !recorder.entered { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.entered)
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.recordingStartFailure)
    }

    func testRecordingDoesNotRequireAConfiguredSummaryAIProvider() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, makeRecorder: { StartFailureRecorder() })
        let keys = ["mobileAIProvider", "mobileOllamaModel", "mobileOllamaQuickModel"]
        let original = UserDefaults.standard.dictionaryRepresentation().filter { keys.contains($0.key) }
        defer {
            for key in keys { UserDefaults.standard.removeObject(forKey: key) }
            for (key, value) in original { UserDefaults.standard.set(value, forKey: key) }
        }
        session.ai.provider = .ollama
        session.ai.model = ""
        session.ai.quickModel = ""
        XCTAssertNotNil(session.summaryAvailability)
        session.start()
        for _ in 0..<400 where session.state == .preparing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        XCTAssertNil(session.recordingStartFailure)
        await session.stop()
    }

    func testPermissionFailureAfterCancellationDoesNotPresentAStartupError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StartFailureRecorder()
        recorder.holdPreparation = true
        recorder.failure = RecordingError.message("Microphone access is off.")
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        session.start()
        for _ in 0..<400 where !recorder.entered { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.entered)
        let stopping = Task { await session.stop() }
        for _ in 0..<400 where !recorder.cancellationObserved { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.cancellationObserved)
        // The OS callback can return a permission/framework error rather than CancellationError.
        recorder.releasePreparation()
        await stopping.value
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.recordingStartFailure, "A cancelled start must not present a late permission failure")
        XCTAssertNil(session.message)
    }
}

@MainActor
private final class StartFailureRecorder: MobileRecording {
    var failure: (any Error)?
    var waitDuringPreparation = false
    var holdPreparation = false
    private(set) var entered = false
    private(set) var cancellationObserved = false
    private var preparation: CheckedContinuation<Void, Never>?

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        entered = true
        if holdPreparation {
            await withTaskCancellationHandler {
                await withCheckedContinuation { preparation = $0 }
            } onCancel: {
                Task { @MainActor in self.cancellationObserved = true }
            }
        }
        if waitDuringPreparation { try await Task.sleep(for: .seconds(60)) }
        if let failure { throw failure }
    }
    func stop() async throws {}
    func reconfigure() async throws {}
    func releasePreparation() { preparation?.resume(); preparation = nil }
}
