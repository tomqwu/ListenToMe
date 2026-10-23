import AVFoundation
import Foundation
import Observation
import os
import WatchConnectivity

/// Finished watch chunks waiting to reach the paired iPhone (issue #181, Slice 3).
///
/// Each chunk lives in `Application Support/Outbox/<recordingID>/<index>.m4a` beside its metadata,
/// `<index>.json`, and goes to the iPhone with `transferFile` only: the watch makes no network
/// request. A chunk is deleted only once `didFinish` reports success (decision 3); a failed transfer
/// is sent again after `WatchCapturePolicy.retryDelay`. A chunk's metadata is also kept in memory and
/// read back from the transfer itself, so a chunk whose metadata file could not be written is never
/// stuck. A recording's end marker, when it has no last chunk, waits as `end.json` until the session
/// can queue it with `transferUserInfo`.
@MainActor @Observable
final class WatchOutbox {
    /// Recordings with at least one chunk not yet delivered.
    private(set) var waitingRecordings = 0
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let session: WCSession
    @ObservationIgnored private let root: URL
    /// Metadata of chunks added or seen in a transfer this launch, by `<recordingID>/<index>.m4a`.
    @ObservationIgnored private var known: [String: WatchChunkMetadata] = [:]
    /// Failed transfers per chunk, for the retry delay. Reset at launch.
    @ObservationIgnored private var attempts: [String: Int] = [:]
    @ObservationIgnored private var retries: [String: Task<Void, Never>] = [:]
    private static let endName = "end.json"
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios.watchkitapp", category: "WatchOutbox")

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Outbox", isDirectory: true)
    }

    /// Runs at launch, before anything can record, and recovers what a killed launch left in
    /// `recordingRoot` (see `recoverUnfinished`).
    init(session: WCSession = .default, root: URL = WatchOutbox.defaultRoot,
         recordingRoot: URL = WatchRecorder.recordingRoot) {
        self.session = session
        self.root = root
        recoverUnfinished(in: recordingRoot)
        recount()
    }

    /// Takes a finished, closed chunk from the recorder and starts sending it.
    func add(_ url: URL, _ metadata: WatchChunkMetadata) throws {
        let folder = try makeFolder(metadata.recordingID)
        let destination = folder.appendingPathComponent("\(metadata.index).m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        // The recorder's placeholder for this chunk is no longer needed.
        try? FileManager.default.removeItem(at: sidecar(for: url))
        known[key(destination)] = metadata
        writeSidecar(metadata, for: destination)
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
        for transfer in outstanding {
            remember(transfer.file.metadata.flatMap { try? WatchChunkMetadata(transferMetadata: $0) },
                     for: transfer.file.fileURL)
        }
        let queued = Set(outstanding.map(\.file.fileURL))
        for url in WatchCapturePolicy.chunksToQueue(finalized: chunkURLs(), outstanding: queued) {
            guard let metadata = metadata(for: url) else {
                Self.log.error("Chunk kept without metadata; Delete on the watch removes it")
                continue
            }
            send(url, metadata)
        }
        flushEnds()
        recount()
    }

    /// `didFinish` for a chunk: deleted only on success, otherwise sent again after a delay.
    /// `metadata` is what the transfer carried, the fallback when the chunk's file was never written.
    func transferFinished(fileURL: URL, metadata: WatchChunkMetadata?, error: (any Error)?) {
        let url = localURL(fileURL)
        let key = key(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let error else {
            attempts[key] = nil
            known[key] = nil
            retries.removeValue(forKey: key)?.cancel()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: sidecar(for: url))
            removeIfEmpty(url.deletingLastPathComponent())
            recount()
            return
        }
        remember(metadata, for: url)
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
        known = [:]
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
              !WatchCapturePolicy.chunksToQueue(finalized: [url], outstanding: outstanding).isEmpty else { return }
        guard let metadata = metadata(for: url) else {
            Self.log.error("Chunk kept without metadata; Delete on the watch removes it")
            return
        }
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

    // MARK: Metadata

    /// From memory, then the metadata file, then nothing.
    private func metadata(for url: URL) -> WatchChunkMetadata? {
        known[key(url)] ?? readSidecar(for: url)
    }

    /// Keeps metadata learned from a transfer, and writes the file again if it is missing, so the chunk
    /// can still be resent after a relaunch.
    private func remember(_ metadata: WatchChunkMetadata?, for fileURL: URL) {
        let url = localURL(fileURL)
        guard let metadata, metadata.index == Int(url.deletingPathExtension().lastPathComponent),
              metadata.recordingID.uuidString == url.deletingLastPathComponent().lastPathComponent else { return }
        known[key(url)] = metadata
        if readSidecar(for: url) == nil, FileManager.default.fileExists(atPath: url.path) {
            writeSidecar(metadata, for: url)
        }
    }

    private func writeSidecar(_ metadata: WatchChunkMetadata, for chunk: URL) {
        do {
            try JSONEncoder().encode(metadata).write(to: sidecar(for: chunk), options: .atomic)
        } catch {
            // Still sendable this launch from memory, or later from the transfer's own metadata.
            Self.log.error("Chunk metadata not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Launch

    /// A killed launch can leave chunks in `recordingRoot`. Only the highest index can be unfinished
    /// (a rotation closes a chunk before opening the next): it is sent if it can be read, otherwise
    /// deleted. Every lower one is complete, only never handed over, and is sent. The iPhone is then
    /// told the recording ended unexpectedly, naming the highest index, so a lost chunk shows as a gap.
    /// An empty folder is a run stopped by an interruption, whose last chunk already said so.
    private func recoverUnfinished(in recordingRoot: URL) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: recordingRoot, includingPropertiesForKeys: nil))
            ?? []
        for folder in folders {
            defer { try? FileManager.default.removeItem(at: folder) }
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let indices = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .compactMap { $0.hasSuffix(".m4a") ? Int($0.dropLast(4)) : nil }.sorted()
            guard let highest = indices.last else { continue }
            var previous: WatchChunkMetadata?
            var keptHighest = false
            for index in indices {
                let url = folder.appendingPathComponent("\(index).m4a")
                guard let chunk = recoveredChunk(url, id: id, index: index, previous: previous,
                                                 mustBeReadable: index == highest) else {
                    Self.log.notice("Discarded the unfinished chunk of a recording that ended unexpectedly")
                    continue
                }
                do {
                    try add(url, chunk)
                    previous = chunk
                    keptHighest = keptHighest || index == highest
                } catch {
                    Self.log.error("Recovered chunk not queued: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Nothing at all was recorded: there is nothing to tell the iPhone.
            guard highest > 0 || keptHighest else { continue }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            let startedAt = previous?.startedAt ?? pendingMetadata(folder, highest)?.startedAt ?? created ?? Date()
            sendEnd(WatchRecordingEnd(recordingID: id, startedAt: startedAt, lastIndex: highest, unexpected: true))
        }
    }

    /// The chunk's metadata, with its real duration when the file can be read. `nil` when it must be
    /// readable and is not (killed mid-write: an AAC file without its index); such a file is deleted.
    private func recoveredChunk(_ url: URL, id: UUID, index: Int, previous: WatchChunkMetadata?,
                                mustBeReadable: Bool) -> WatchChunkMetadata? {
        let pending = pendingMetadata(url.deletingLastPathComponent(), index)
        let seconds = (try? AVAudioFile(forReading: url))
            .map { Double($0.length) / max(1, $0.processingFormat.sampleRate) }
        let readable = seconds.map { $0 > 0 && $0 < WatchChunkMetadata.maximumDuration } ?? false
        guard readable || !mustBeReadable else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let created = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.creationDateKey]))?.creationDate
        return WatchChunkMetadata(
            recordingID: id, index: index,
            startOffset: pending?.startOffset ?? previous.map { $0.startOffset + $0.duration }
                ?? Double(index) * WatchCapturePolicy.chunkDuration,
            duration: readable ? seconds ?? WatchCapturePolicy.chunkDuration : WatchCapturePolicy.chunkDuration,
            isLast: false, startedAt: pending?.startedAt ?? previous?.startedAt ?? created ?? Date(),
            watchBuild: pending?.watchBuild ?? "unknown")
    }

    /// The recorder's placeholder written when it opened the chunk; see `WatchCaptureRun`.
    private func pendingMetadata(_ folder: URL, _ index: Int) -> WatchChunkMetadata? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(index).json")) else { return nil }
        return try? JSONDecoder().decode(WatchChunkMetadata.self, from: data)
    }

    // MARK: Files

    private func makeFolder(_ id: UUID) throws -> URL {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: WatchRecorder.protection)
        return folder
    }

    /// Found by its last two path parts, so a path the system rewrote still matches.
    private func localURL(_ fileURL: URL) -> URL {
        root.appendingPathComponent(fileURL.deletingLastPathComponent().lastPathComponent, isDirectory: true)
            .appendingPathComponent(fileURL.lastPathComponent)
    }

    private func key(_ url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
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
