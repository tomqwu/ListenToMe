import AVFoundation
import XCTest
@testable import ListenToMeWatch

@MainActor
final class WatchOutboxDurabilityTests: XCTestCase {
    func testRecoveryFailureKeepsRecordedAudioForNextLaunch() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordingRoot = root.appendingPathComponent("Recording")
        let id = UUID()
        let chunk = recordingRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.m4a")
        let audio = try WatchAudioFixture.write(to: chunk)
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: false, startedAt: Date(), watchBuild: "fixture")
        try JSONEncoder().encode(metadata).write(to: chunk.deletingPathExtension().appendingPathExtension("json"))
        let outboxRoot = root.appendingPathComponent("Outbox")
        // A filesystem obstruction makes recovery's handoff fail, without an artificial capture error.
        try Data("occupied".utf8).write(to: outboxRoot)
        let failed = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(failed.waitingRecordings, 1, "Unqueued recovery audio remains visibly pending")
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunk.path),
                      "An outbox write failure must not delete the Watch recording")
        guard FileManager.default.fileExists(atPath: chunk.path) else { return }
        XCTAssertEqual(try Data(contentsOf: chunk), audio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunk.deletingPathExtension().appendingPathExtension("json").path))

        try FileManager.default.removeItem(at: outboxRoot)
        let recovered = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        let queued = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.m4a")
        XCTAssertEqual(recovered.waitingRecordings, 1)
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        XCTAssertGreaterThan(try AVAudioFile(forReading: queued).length, 0)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(relaunched.waitingRecordings, 1)
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        relaunched.deleteWaiting()
        XCTAssertEqual(relaunched.waitingRecordings, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
    }

    func testRecoveryFailureKeepsLaterChunksAndOriginalEndBoundary() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), started = Date()
        let recordingRoot = root.appendingPathComponent("Recording")
        let folder = recordingRoot.appendingPathComponent(id.uuidString)
        for index in 0...1 {
            _ = try WatchAudioFixture.write(to: folder.appendingPathComponent("\(index).m4a"))
            let metadata = WatchChunkMetadata(recordingID: id, index: index, startOffset: Double(index),
                                              duration: 1, isLast: false, startedAt: started, watchBuild: "fixture")
            try JSONEncoder().encode(metadata).write(to: folder.appendingPathComponent("\(index).json"))
        }
        let outboxRoot = root.appendingPathComponent("Outbox")
        let blocked = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: blocked.appendingPathComponent("keep"))
        _ = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("1.m4a").path),
                      "A failed handoff must preserve later chunks and the original end boundary")
        try FileManager.default.removeItem(at: blocked)
        let recovered = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(recovered.waitingRecordings, 1)
        let endURL = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("end.json")
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: endURL),
                                                                          format: nil) as? [String: Any])
        let end = try WatchRecordingEnd(userInfo: fields)
        XCTAssertEqual(end.lastIndex, 1, "Retry must not shorten the recording to the first failed chunk")
        recovered.deleteWaiting()
    }

    func testRecoveryRetainsEndBoundaryWhenEndMarkerCannotBeWritten() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (id, recordingRoot) = try interruptedRecording(in: root)
        let outboxRoot = root.appendingPathComponent("Outbox")
        let endURL = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("end.json")
        try FileManager.default.createDirectory(at: endURL, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: endURL.appendingPathComponent("keep"))
        let first = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(first.waitingRecordings, 1)
        try FileManager.default.removeItem(at: endURL)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertTrue(FileManager.default.fileExists(atPath: endURL.path),
                      "Relaunch must retry the end marker even after every audio chunk moved")
        guard FileManager.default.fileExists(atPath: endURL.path) else { return }
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: endURL),
                                                                          format: nil) as? [String: Any])
        let end = try WatchRecordingEnd(userInfo: fields)
        XCTAssertEqual(end.recordingID, id)
        XCTAssertEqual(end.lastIndex, 0)
        XCTAssertTrue(end.unexpected)
        relaunched.deleteWaiting()
    }

    func testDeleteIncludesUnqueuedRecoveryAndPreventsResurrection() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, recordingRoot) = try interruptedRecording(in: root)
        let outboxRoot = root.appendingPathComponent("Outbox")
        try Data("obstruction".utf8).write(to: outboxRoot)
        let first = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(first.waitingRecordings, 1, "Unqueued recovery audio must be visible as waiting")
        first.deleteWaiting()
        XCTAssertEqual(first.waitingRecordings, 0)
        try FileManager.default.removeItem(at: outboxRoot)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(relaunched.waitingRecordings, 0, "Deleted recovery audio must not return after repair/relaunch")
    }

    func testLiveEndWithoutFinalChunkRemainsDurableAfterStorageFailure() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordingRoot = root.appendingPathComponent("Recording"), outboxRoot = root.appendingPathComponent("Outbox")
        try Data("obstruction".utf8).write(to: outboxRoot)
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        let end = WatchRecordingEnd(recordingID: UUID(), startedAt: Date(), lastIndex: 2, unexpected: false)
        outbox.sendEnd(end)
        XCTAssertEqual(outbox.waitingRecordings, 1)
        try FileManager.default.removeItem(at: outboxRoot)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        let endURL = outboxRoot.appendingPathComponent(end.recordingID.uuidString).appendingPathComponent("end.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: endURL.path))
        guard FileManager.default.fileExists(atPath: endURL.path) else { return }
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: endURL),
                                                                          format: nil) as? [String: Any])
        let saved = try WatchRecordingEnd(userInfo: fields)
        XCTAssertEqual(saved.lastIndex, 2)
        XCTAssertFalse(saved.unexpected)
        relaunched.deleteWaiting()
    }

    func testQueuedEndClearsEmptyRecoveryIntentAfterActivation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordingRoot = root.appendingPathComponent("Recording")
        let outboxRoot = root.appendingPathComponent("Outbox")
        var active = false, ends: [[String: Any]] = []
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot,
                                transport: .init(isActive: { active }, outstandingURLs: { [] },
                                                 sendFile: { _, _ in XCTFail("No audio here") },
                                                 sendUserInfo: { ends.append($0) }, cancelOutstanding: {}))
        let end = WatchRecordingEnd(recordingID: UUID(), startedAt: Date(), lastIndex: 0, unexpected: false)
        try FileManager.default.createDirectory(at: recordingRoot.appendingPathComponent(end.recordingID.uuidString),
                                                withIntermediateDirectories: true)
        outbox.sendEnd(end)
        XCTAssertEqual(outbox.waitingRecordings, 1)
        active = true
        outbox.reconcileAtLaunch(outstanding: [])
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(outbox.waitingRecordings, 0, "Accepted end must not leave a phantom recovery recording")
        outbox.reconcileAtLaunch(outstanding: [])
        XCTAssertEqual(ends.count, 1)
        outbox.deleteWaiting()
    }

    func testLaterContinuedChunkAdvancesSavedEndIntentAfterRelaunch() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), started = Date()
        let recordingRoot = root.appendingPathComponent("Recording"), outboxRoot = root.appendingPathComponent("Outbox")
        let endURL = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("end.json")
        try FileManager.default.createDirectory(at: endURL, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: endURL.appendingPathComponent("keep"))
        let first = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        first.sendEnd(WatchRecordingEnd(recordingID: id, startedAt: started, lastIndex: 0, unexpected: false))
        // The recorder's Continue contract uses this same ID and the next index (WATCH-008).
        let folder = recordingRoot.appendingPathComponent(id.uuidString)
        _ = try WatchAudioFixture.write(to: folder.appendingPathComponent("1.m4a"))
        let metadata = WatchChunkMetadata(recordingID: id, index: 1, startOffset: 1, duration: 1,
                                          isLast: false, startedAt: started, watchBuild: "fixture")
        try JSONEncoder().encode(metadata).write(to: folder.appendingPathComponent("1.json"))
        try FileManager.default.removeItem(at: endURL)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: endURL),
                                                                          format: nil) as? [String: Any])
        let end = try WatchRecordingEnd(userInfo: fields)
        XCTAssertEqual(end.lastIndex, 1, "An old interrupted boundary must not hide later continued audio")
        XCTAssertTrue(end.unexpected, "The later unfinished run ended unexpectedly")
        relaunched.deleteWaiting()
    }

    func testContinuedFinalHandoffClearsOldIntentAfterAcknowledgement() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), started = Date()
        let recordingRoot = root.appendingPathComponent("Recording"), outboxRoot = root.appendingPathComponent("Outbox")
        let endURL = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("end.json")
        try FileManager.default.createDirectory(at: endURL, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: endURL.appendingPathComponent("keep"))
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        outbox.sendEnd(WatchRecordingEnd(recordingID: id, startedAt: started, lastIndex: 0, unexpected: false))
        try FileManager.default.removeItem(at: endURL)
        let source = recordingRoot.appendingPathComponent(id.uuidString).appendingPathComponent("1.m4a")
        _ = try WatchAudioFixture.write(to: source)
        let metadata = WatchChunkMetadata(recordingID: id, index: 1, startOffset: 1, duration: 1,
                                          isLast: true, startedAt: started, watchBuild: "fixture")
        try outbox.add(source, metadata)
        let queued = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("1.m4a")
        outbox.transferFinished(fileURL: queued, metadata: metadata, error: nil)
        XCTAssertEqual(outbox.waitingRecordings, 0, "Completed continued audio must not leave an obsolete end intent")
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(relaunched.waitingRecordings, 0)
        outbox.deleteWaiting()
        relaunched.deleteWaiting()
    }

    // Baseline adoption of existing acknowledgement behavior; no historical failure is claimed.
    func testFailedTransferSurvivesRelaunchUntilSuccessAndDuplicateCallbackIsSafe() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordingRoot = root.appendingPathComponent("Recording")
        let id = UUID(), source = root.appendingPathComponent("finished.m4a")
        let audio = try WatchAudioFixture.write(to: source)
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: true, startedAt: Date(), watchBuild: "fixture")
        let outboxRoot = root.appendingPathComponent("Outbox")
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        defer { outbox.deleteWaiting() }
        try outbox.add(source, metadata)
        let queued = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.m4a")
        XCTAssertEqual(outbox.waitingRecordings, 1)
        outbox.transferFinished(fileURL: queued, metadata: metadata,
                                error: NSError(domain: "OfflineFixture", code: 1))
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: recordingRoot, transport: isolatedTransport())
        XCTAssertEqual(relaunched.waitingRecordings, 1)
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        relaunched.transferFinished(fileURL: queued, metadata: metadata, error: nil)
        XCTAssertEqual(relaunched.waitingRecordings, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
        relaunched.transferFinished(fileURL: queued, metadata: metadata, error: nil)
        XCTAssertEqual(relaunched.waitingRecordings, 0)
    }

    func testMetadataWriteFailureKeepsSourceAudioAndCanBeRetried() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), source = root.appendingPathComponent("finished.m4a")
        let audio = try WatchAudioFixture.write(to: source)
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: true, startedAt: Date(), watchBuild: "fixture")
        let outboxRoot = root.appendingPathComponent("Outbox")
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: root.appendingPathComponent("unused"),
                                transport: isolatedTransport())
        let blockedSidecar = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.json")
        try FileManager.default.createDirectory(at: blockedSidecar, withIntermediateDirectories: true)
        try Data("obstruction".utf8).write(to: blockedSidecar.appendingPathComponent("keep"))
        XCTAssertThrowsError(try outbox.add(source, metadata), "Metadata must be durable before accepting audio")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Failure must leave audio with the recorder")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        XCTAssertEqual(try Data(contentsOf: source), audio)
        XCTAssertEqual(outbox.waitingRecordings, 0)
        try FileManager.default.removeItem(at: blockedSidecar)
        try outbox.add(source, metadata)
        XCTAssertEqual(outbox.waitingRecordings, 1)
        let relaunched = WatchOutbox(root: outboxRoot, recordingRoot: root.appendingPathComponent("unused"),
                                    transport: isolatedTransport())
        XCTAssertEqual(relaunched.waitingRecordings, 1)
        let saved = try JSONDecoder().decode(WatchChunkMetadata.self, from: Data(contentsOf: blockedSidecar))
        XCTAssertEqual(saved, metadata)
        relaunched.deleteWaiting()
    }

    func testRepeatedHandoffNeverReplacesUnacknowledgedAudio() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), source = root.appendingPathComponent("finished.m4a")
        let audio = try WatchAudioFixture.write(to: source)
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: true, startedAt: Date(), watchBuild: "fixture")
        let outboxRoot = root.appendingPathComponent("Outbox")
        let outbox = WatchOutbox(root: outboxRoot, recordingRoot: root.appendingPathComponent("unused"),
                                transport: isolatedTransport())
        try outbox.add(source, metadata)
        let queued = outboxRoot.appendingPathComponent(id.uuidString).appendingPathComponent("0.m4a")
        XCTAssertNoThrow(try outbox.add(source, metadata), "Repeating the completed handoff must be harmless")
        XCTAssertTrue(FileManager.default.fileExists(atPath: queued.path))
        guard FileManager.default.fileExists(atPath: queued.path) else { return }
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        try Data("conflicting recording".utf8).write(to: source)
        XCTAssertThrowsError(try outbox.add(source, metadata))
        XCTAssertEqual(try Data(contentsOf: queued), audio)
        XCTAssertEqual(try Data(contentsOf: source), Data("conflicting recording".utf8))
        XCTAssertEqual(outbox.waitingRecordings, 1)
        outbox.deleteWaiting()
    }

    // Native adapter coverage added during transport isolation; no historical red is claimed.
    func testOfflineActivationQueuesOnceAndDeleteCancelsItsTransport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), source = root.appendingPathComponent("finished.m4a")
        _ = try WatchAudioFixture.write(to: source)
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: true, startedAt: Date(), watchBuild: "fixture")
        var active = false, pending = Set<URL>(), sent: [URL] = [], cancellations = 0
        let outbox = WatchOutbox(root: root.appendingPathComponent("Outbox"),
                                recordingRoot: root.appendingPathComponent("unused"),
                                transport: .init(isActive: { active }, outstandingURLs: { pending },
                                                 sendFile: { url, dictionary in
            let decoded = try? WatchChunkMetadata(transferMetadata: dictionary)
            XCTAssertEqual(decoded?.recordingID, metadata.recordingID)
            XCTAssertEqual(decoded?.index, metadata.index)
            XCTAssertEqual(decoded?.isLast, metadata.isLast)
            XCTAssertEqual(decoded?.startedAt.timeIntervalSince1970 ?? 0,
                           metadata.startedAt.timeIntervalSince1970, accuracy: 0.000001)
            pending.insert(url)
            sent.append(url)
        }, sendUserInfo: { _ in }, cancelOutstanding: { cancellations += 1; pending.removeAll() }))
        try outbox.add(source, metadata)
        XCTAssertTrue(sent.isEmpty)
        active = true
        outbox.reconcileAtLaunch(outstanding: [])
        outbox.reconcileAtLaunch(outstanding: [])
        XCTAssertEqual(sent.count, 1, "An activation replay must not queue another transfer")
        let queued = try XCTUnwrap(sent.first)
        pending.removeAll()
        outbox.transferFinished(fileURL: queued, metadata: metadata, error: NSError(domain: "OfflineFixture", code: 1))
        outbox.deleteWaiting()
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(outbox.waitingRecordings, 0)
        try await Task.sleep(for: .seconds(6))
        outbox.reconcileAtLaunch(outstanding: [])
        XCTAssertEqual(sent.count, 1, "Deleted audio must not be retried later")
        XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func interruptedRecording(in root: URL) throws -> (UUID, URL) {
        let id = UUID(), recordingRoot = root.appendingPathComponent("Recording")
        let folder = recordingRoot.appendingPathComponent(id.uuidString)
        _ = try WatchAudioFixture.write(to: folder.appendingPathComponent("0.m4a"))
        let metadata = WatchChunkMetadata(recordingID: id, index: 0, startOffset: 0, duration: 1,
                                          isLast: false, startedAt: Date(), watchBuild: "fixture")
        try JSONEncoder().encode(metadata).write(to: folder.appendingPathComponent("0.json"))
        return (id, recordingRoot)
    }

    private func isolatedTransport() -> WatchOutbox.Transport {
        .init(isActive: { false }, outstandingURLs: { [] },
              sendFile: { _, _ in XCTFail("Offline test must not enqueue a file") },
              sendUserInfo: { _ in XCTFail("Offline test must not enqueue user info") },
              cancelOutstanding: {})
    }

}
