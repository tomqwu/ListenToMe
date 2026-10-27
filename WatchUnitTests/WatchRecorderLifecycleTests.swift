import AVFoundation
import XCTest
@testable import ListenToMeWatch

@MainActor
final class WatchRecorderLifecycleTests: XCTestCase {
    func testPresentationDismissalKeepsCaptureUntilExplicitStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = LifecycleCaptureFixture()
        let recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
            .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
        }, requestPermission: {}, audioSession: .init(activate: {}, deactivate: {}),
                                    recordingsDirectory: root.appendingPathComponent("Recording"))
        let outbox = WatchOutbox(root: root.appendingPathComponent("Outbox"),
                                recordingRoot: root.appendingPathComponent("unused"),
                                transport: .init(isActive: { false }, outstandingURLs: { [] },
                                                 sendFile: { _, _ in XCTFail("No live transfer") },
                                                 sendUserInfo: { _ in XCTFail("No live user info") },
                                                 cancelOutstanding: {}))
        var finalized: [(URL, Bool)] = []
        var ends = 0
        recorder.onChunkFinalized = { url, metadata in finalized.append((url, metadata.isLast)) }
        recorder.onRecordingEnded = { _ in ends += 1 }
        defer { recorder.stop() }
        let view = WatchRootView(link: WatchLinkClient(sendMessage: { _, _, _ in XCTFail("No remote control") }),
                                 recorder: recorder, outbox: outbox)
        try await recorder.start()
        XCTAssertTrue(view.recordingScreenShown.wrappedValue)
        view.recordingScreenShown.wrappedValue = false
        XCTAssertTrue(recorder.isRecording, "A presentation callback is not an explicit Stop")
        XCTAssertTrue(capture.isRunning)
        XCTAssertTrue(finalized.isEmpty)
        XCTAssertEqual(ends, 0)
        recorder.stop()
        XCTAssertFalse(view.recordingScreenShown.wrappedValue)
        XCTAssertEqual(finalized.count, 1)
        let last = try XCTUnwrap(finalized.first)
        XCTAssertTrue(last.1)
        XCTAssertGreaterThan(try AVAudioFile(forReading: last.0).length, 0)
        recorder.stop()
        view.recordingScreenShown.wrappedValue = false
        XCTAssertEqual(finalized.count, 1, "Repeated Stop/dismissal must not finalize again")
        XCTAssertEqual(ends, 0, "The last AAC carries the end, so no separate end marker is needed")
        XCTAssertEqual(recorder.phase, .idle)
    }

    func testCancelledBeforeFirstTurnNeverRequestsStartOrContinuePermission() async throws {
        for continuing in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let capture = LifecycleCaptureFixture()
            var permissions = 0
            let recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
                .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
            }, requestPermission: { permissions += 1 },
                                        audioSession: .init(activate: {}, deactivate: {}), recordingsDirectory: root)
            defer { recorder.stop() }
            if continuing {
                try await recorder.start()
                capture.event?(.interruptionBegan)
                XCTAssertTrue(recorder.canContinue)
            }
            permissions = 0
            let operation = Task { @MainActor in
                if continuing { try? await recorder.continueRecording() } else { try? await recorder.start() }
            }
            operation.cancel()
            await operation.value
            XCTAssertEqual(permissions, 0, "A cancelled first turn must not begin system consent work")
            XCTAssertFalse(recorder.isRecording)
        }
    }

    func testCancelledPermissionWaitNeverActivatesCapture() async throws {
        try await checkPendingStart(cancelTask: true, stop: false, makeUnavailable: false)
    }

    func testStopInvalidatesPendingPermissionAndCannotStartLater() async throws {
        try await checkPendingStart(cancelTask: false, stop: true, makeUnavailable: false)
    }

    func testReadinessChangedDuringPermissionWaitRefusesCapture() async throws {
        try await checkPendingStart(cancelTask: false, stop: false, makeUnavailable: true)
    }

    private func checkPendingStart(cancelTask: Bool, stop: Bool, makeUnavailable: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var denied = false, activations = 0, creations = 0
        var permission: CheckedContinuation<Void, Never>?
        let recorder = WatchRecorder(makeCapture: {
            creations += 1
            return LifecycleCaptureFixture()
        }, capabilitySnapshot: {
            .init(microphoneDenied: denied, battery: 1, freeBytes: Int64.max)
        }, requestPermission: {
            await withCheckedContinuation { permission = $0 }
        }, audioSession: .init(activate: { activations += 1 }, deactivate: {}), recordingsDirectory: directory)
        defer { recorder.stop() }
        let start = Task { @MainActor in
            do { try await recorder.start(); return true } catch { return false }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while permission == nil, ContinuousClock.now < deadline { await Task.yield() }
        guard let pending = permission else {
            start.cancel()
            return XCTFail("Permission suspension was not reached")
        }
        if cancelTask { start.cancel() }
        if stop { recorder.stop() }
        if makeUnavailable { denied = true }
        pending.resume()
        let completed = await start.value
        XCTAssertFalse(completed, "A stale or cancelled permission request must not start recording")
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(activations, 0, "No audio session after cancellation or loss of readiness")
        XCTAssertEqual(creations, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    // Existing lifecycle adopted through isolated session/capture adapters; no historical red claimed.
    func testRecordingFinalizesAACAndInterruptionWaitsForExplicitContinue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = LifecycleCaptureFixture()
        var activations = 0, deactivations = 0
        let outbox = WatchOutbox(root: directory.appendingPathComponent("Outbox"),
                                recordingRoot: directory.appendingPathComponent("unused"),
                                transport: .init(isActive: { false }, outstandingURLs: { [] },
                                                 sendFile: { _, _ in XCTFail("No live transfer") },
                                                 sendUserInfo: { _ in XCTFail("No live user info") },
                                                 cancelOutstanding: {}))
        let recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
            .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
        }, requestPermission: {}, audioSession: .init(activate: { activations += 1 },
                                                      deactivate: { deactivations += 1 }),
                                    recordingsDirectory: directory.appendingPathComponent("Recording"))
        recorder.onChunkFinalized = { url, metadata in
            do { try outbox.add(url, metadata) } catch { XCTFail("Completed audio not queued: \(error)") }
        }
        defer { recorder.stop(); outbox.deleteWaiting() }
        try await recorder.start()
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(outbox.waitingRecordings, 0)
        let first = try XCTUnwrap(capture.run)
        capture.event?(.interruptionBegan)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(recorder.canContinue)
        XCTAssertEqual(outbox.waitingRecordings, 1)
        XCTAssertEqual(deactivations, 1)
        capture.event?(.interruptionEnded)
        XCTAssertFalse(recorder.isRecording, "An interruption must not automatically resume the microphone")
        try await recorder.continueRecording()
        XCTAssertTrue(recorder.isRecording)
        let second = try XCTUnwrap(capture.run)
        XCTAssertEqual(second.recordingID, first.recordingID)
        XCTAssertEqual(second.firstIndex, first.firstIndex + 1)
        XCTAssertEqual(activations, 2)
        recorder.stop()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(deactivations, 2)
        let folder = directory.appendingPathComponent("Outbox").appendingPathComponent(first.recordingID.uuidString)
        for index in [0, 1] {
            XCTAssertGreaterThan(try AVAudioFile(forReading: folder.appendingPathComponent("\(index).m4a")).length, 0)
        }
        XCTAssertEqual(outbox.waitingRecordings, 1)
    }

    func testFailedLiveHandoffStaysPendingAndDeleteWaitsForRecordingToStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordingRoot = root.appendingPathComponent("Recording"), outboxRoot = root.appendingPathComponent("Outbox")
        let capture = LifecycleCaptureFixture()
        let recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
            .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
        }, requestPermission: {}, audioSession: .init(activate: {}, deactivate: {}), recordingsDirectory: recordingRoot)
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot,
                                transport: .init(isActive: { false }, outstandingURLs: { [] },
                                                 sendFile: { _, _ in XCTFail("No live transfer") },
                                                 sendUserInfo: { _ in }, cancelOutstanding: {}),
                                recordingIsActive: { [weak recorder] in recorder?.isRecording == true })
        defer { recorder.stop(); outbox.deleteWaiting() }
        try Data("obstruction".utf8).write(to: outboxRoot)
        recorder.onChunkFinalized = { [weak outbox] url, metadata in
            guard let outbox else { return XCTFail("Outbox released") }
            do { try outbox.add(url, metadata); XCTFail("Obstructed handoff must fail") } catch {}
        }
        try await recorder.start()
        let run = try XCTUnwrap(capture.run)
        let url = run.url(run.firstIndex)
        let metadata = WatchChunkMetadata(recordingID: run.recordingID, index: run.firstIndex,
                                          startOffset: 0, duration: 1, isLast: false,
                                          startedAt: run.startedAt, watchBuild: "fixture")
        capture.chunk?(WatchFinishedChunk(url: url, metadata: metadata))
        XCTAssertEqual(outbox.waitingRecordings, 1, "A failed live chunk remains visibly pending")
        outbox.deleteWaiting()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Delete must not erase the active recording")
        recorder.stop()
        outbox.deleteWaiting()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "After Stop, Delete erases pending source audio")
        try FileManager.default.removeItem(at: outboxRoot)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot,
                                    transport: .init(isActive: { false }, outstandingURLs: { [] },
                                                     sendFile: { _, _ in XCTFail("No transfer") },
                                                     sendUserInfo: { _ in }, cancelOutstanding: {}))
        XCTAssertEqual(relaunched.waitingRecordings, 0)
    }

    func testBackgroundCancelsPendingCompletionButPreservesStartedRecording() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = LifecycleCaptureFixture()
        let recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
            .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
        }, requestPermission: {}, audioSession: .init(activate: {}, deactivate: {}), recordingsDirectory: root)
        let preparation = WatchPreparation()
        var completion: CheckedContinuation<Void, Never>?, haptics = 0
        defer { preparation.cancel(); recorder.stop(); completion?.resume() }
        preparation.run(operation: {
            try await recorder.start()
            await withCheckedContinuation { completion = $0 }
        }, onSuccess: { haptics += 1 })
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while completion == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertNotNil(completion)
        XCTAssertTrue(recorder.isRecording)
        preparation.sceneChanged(.background, isRecording: recorder.isRecording) { recorder.stop() }
        XCTAssertFalse(preparation.isPending)
        XCTAssertTrue(recorder.isRecording, "An established capture must survive departure even before UI completion")
        completion?.resume()
        completion = nil
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(haptics, 0, "No late start haptic after departure")
    }
}

/// Drives the real recorder controller and AAC/outbox path, without a microphone or WC transport.
private final class LifecycleCaptureFixture: WatchChunkCapturing {
    var isRunning = false
    var run: WatchCaptureRun?
    var event: (@MainActor @Sendable (WatchAudioEvent) -> Void)?
    var chunk: (@MainActor @Sendable (WatchFinishedChunk) -> Void)?

    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void,
               onAudioEvent: @escaping @MainActor @Sendable (WatchAudioEvent) -> Void) throws {
        self.run = run
        event = onAudioEvent
        chunk = onChunk
        _ = try WatchAudioFixture.write(to: run.url(run.firstIndex))
        isRunning = true
    }

    func stop() -> WatchCaptureEnding {
        guard isRunning, let run else { return WatchCaptureEnding(last: nil, lastIndex: nil) }
        isRunning = false
        let metadata = WatchChunkMetadata(recordingID: run.recordingID, index: run.firstIndex,
                                          startOffset: run.startOffset, duration: 1, isLast: true,
                                          startedAt: run.startedAt, watchBuild: run.watchBuild)
        return WatchCaptureEnding(last: WatchFinishedChunk(url: run.url(run.firstIndex), metadata: metadata),
                                  lastIndex: run.firstIndex)
    }
}
