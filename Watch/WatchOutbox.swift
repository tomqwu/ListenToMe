import Foundation
import Observation
import os
import WatchConnectivity

/// Finished watch chunks waiting to reach the paired iPhone (issue #181, Slice 3).
///
/// Each chunk lives in `Application Support/Outbox/<recordingID>/<index>.m4a` beside its metadata,
/// `<index>.json`, and goes to the iPhone with `transferFile` only: the watch makes no network
/// request. A chunk is deleted only once `didFinish` reports success (decision 3); a failed transfer
/// is sent again after `WatchCapturePolicy.retryDelay`. A recording's end marker, when it has no last
/// chunk, waits as `end.json` until the session can queue it with `transferUserInfo`.
@MainActor @Observable
final class WatchOutbox {
    /// Recordings with at least one chunk not yet delivered.
    private(set) var waitingRecordings = 0
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let session: WCSession
    @ObservationIgnored private let root: URL
    /// Failed transfers per chunk (`<recordingID>/<index>.m4a`), for the retry delay. Reset at launch.
    @ObservationIgnored private var attempts: [String: Int] = [:]
    @ObservationIgnored private var retries: [String: Task<Void, Never>] = [:]
    private static let endName = "end.json"
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios.watchkitapp", category: "WatchOutbox")

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Outbox", isDirectory: true)
    }

    /// Runs at launch, before anything can record: a chunk left in `recordingRoot` was being written
    /// when the app was killed, so it was never finished and cannot be read. It is deleted, and the
    /// iPhone is told the recording ended unexpectedly after the last finished chunk.
    init(session: WCSession = .default, root: URL = WatchOutbox.defaultRoot,
         recordingRoot: URL = WatchRecorder.recordingRoot) {
        self.session = session
        self.root = root
        discardUnfinished(in: recordingRoot)
        recount()
    }

    /// Takes a finished chunk from the recorder and starts sending it.
    func add(_ url: URL, _ metadata: WatchChunkMetadata) throws {
        let folder = try makeFolder(metadata.recordingID)
        let destination = folder.appendingPathComponent("\(metadata.index).m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        do {
            try JSONEncoder().encode(metadata).write(to: sidecar(for: destination), options: .atomic)
        } catch {
            // Still sent now; only a resend after a relaunch needs the file.
            Self.log.error("Chunk metadata not written: \(error.localizedDescription, privacy: .public)")
        }
        recount()
        send(destination, metadata)
    }

    /// The recording ended without a last chunk (see `WatchRecorder.onRecordingEnded`).
    func sendEnd(_ end: WatchRecordingEnd) {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: end.userInfo, format: .binary, options: 0)
            try data.write(to: makeFolder(end.recordingID).appendingPathComponent(Self.endName), options: .atomic)
        } catch {
            Self.log.error("End marker not written: \(error.localizedDescription, privacy: .public)")
            if session.activationState == .activated { session.transferUserInfo(end.userInfo) }
            return
        }
        flushEnds()
    }

    /// Once the session is active (at launch): queues every chunk the system is not already sending,
    /// and every end marker still waiting.
    func reconcileAtLaunch(outstanding: [WCSessionFileTransfer]) {
        let queued = Set(outstanding.map(\.file.fileURL))
        let finalized = chunkURLs()
        for url in WatchCapturePolicy.chunksToQueue(finalized: finalized, outstanding: queued) {
            guard let metadata = readSidecar(for: url) else {
                Self.log.error("Chunk kept without metadata; Delete on the watch removes it")
                continue
            }
            send(url, metadata)
        }
        flushEnds()
        recount()
    }

    /// `didFinish` for a chunk: deleted only on success, otherwise sent again after a delay.
    func transferFinished(_ transfer: WCSessionFileTransfer, error: (any Error)?) {
        transferFinished(fileURL: transfer.file.fileURL, error: error)
    }

    func transferFinished(fileURL: URL, error: (any Error)?) {
        // Found by its last two path parts, so a path the system rewrote still matches.
        let recording = fileURL.deletingLastPathComponent().lastPathComponent
        let url = root.appendingPathComponent(recording, isDirectory: true)
            .appendingPathComponent(fileURL.lastPathComponent)
        let key = recording + "/" + fileURL.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let error else {
            attempts[key] = nil
            retries.removeValue(forKey: key)?.cancel()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: sidecar(for: url))
            removeIfEmpty(url.deletingLastPathComponent())
            recount()
            return
        }
        let attempt = attempts[key, default: 0]
        attempts[key] = attempt + 1
        Self.log.error("Transfer failed, retrying: \(error.localizedDescription, privacy: .public)")
        let delay = WatchCapturePolicy.retryDelay(attempt: attempt)
        retries[key]?.cancel()
        retries[key] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.retry(url, key: key)
        }
    }

    /// The user's Delete: recordings that have not reached iPhone are gone from the watch.
    func deleteWaiting() {
        for transfer in session.outstandingFileTransfers { transfer.cancel() }
        for task in retries.values { task.cancel() }
        retries = [:]
        attempts = [:]
        for folder in recordingFolders() { try? FileManager.default.removeItem(at: folder) }
        recount()
    }

    // MARK: Sending

    private func send(_ url: URL, _ metadata: WatchChunkMetadata) {
        // Before activation completes, `reconcileAtLaunch` queues it instead.
        guard session.activationState == .activated else { return }
        session.transferFile(url, metadata: metadata.transferMetadata)
    }

    private func retry(_ url: URL, key: String) {
        retries[key] = nil
        let outstanding = Set(session.outstandingFileTransfers.map(\.file.fileURL))
        guard FileManager.default.fileExists(atPath: url.path),
              !WatchCapturePolicy.chunksToQueue(finalized: [url], outstanding: outstanding).isEmpty,
              let metadata = readSidecar(for: url) else { return }
        send(url, metadata)
    }

    /// Queues waiting end markers; `transferUserInfo` keeps them across launches until delivered.
    private func flushEnds() {
        guard session.activationState == .activated else { return }
        for folder in recordingFolders() {
            let url = folder.appendingPathComponent(Self.endName)
            guard let data = try? Data(contentsOf: url) else { continue }
            if let userInfo = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                session.transferUserInfo(userInfo)
            }
            try? FileManager.default.removeItem(at: url)
            removeIfEmpty(folder)
        }
    }

    // MARK: Launch

    private func discardUnfinished(in recordingRoot: URL) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: recordingRoot, includingPropertiesForKeys: nil))
            ?? []
        for folder in folders {
            defer { try? FileManager.default.removeItem(at: folder) }
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let unfinished = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .compactMap { $0.hasSuffix(".m4a") ? Int($0.dropLast(4)) : nil }
            // An empty folder is a recording stopped by an interruption: its last chunk said so.
            guard let index = unfinished.min(), index > 0 else { continue }
            Self.log.notice("Discarded an unfinished chunk of a recording that ended unexpectedly")
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            sendEnd(WatchRecordingEnd(recordingID: id, startedAt: startedAt(id) ?? created ?? Date(),
                                      lastIndex: index - 1, unexpected: true))
        }
    }

    /// From a finished chunk still waiting, when there is one.
    private func startedAt(_ id: UUID) -> Date? {
        chunkURLs().first { $0.deletingLastPathComponent().lastPathComponent == id.uuidString }
            .flatMap(readSidecar(for:))?.startedAt
    }

    // MARK: Files

    private func makeFolder(_ id: UUID) throws -> URL {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: WatchRecorder.protection)
        return folder
    }

    private func recordingFolders() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    /// Every chunk waiting, by recording and then by index.
    private func chunkURLs() -> [URL] {
        recordingFolders().sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .compactMap { $0.hasSuffix(".m4a") ? Int($0.dropLast(4)) : nil }.sorted()
                .map { folder.appendingPathComponent("\($0).m4a") }
        }
    }

    private func sidecar(for chunk: URL) -> URL {
        chunk.deletingPathExtension().appendingPathExtension("json")
    }

    private func readSidecar(for chunk: URL) -> WatchChunkMetadata? {
        guard let data = try? Data(contentsOf: sidecar(for: chunk)) else { return nil }
        return try? JSONDecoder().decode(WatchChunkMetadata.self, from: data)
    }

    private func removeIfEmpty(_ folder: URL) {
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func recount() {
        let count = Set(chunkURLs().map { $0.deletingLastPathComponent().lastPathComponent }).count
        guard count != waitingRecordings else { return }
        waitingRecordings = count
        onChange?()
    }
}
