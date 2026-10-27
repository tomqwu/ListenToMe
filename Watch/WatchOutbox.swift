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
/// is sent again after `WatchCapturePolicy.retryDelay`. New audio enters the outbox only after its
/// metadata is durable; failed handoffs stay with the recorder for recovery. Metadata learned from
/// an existing transfer also stays in memory if repairing its sidecar fails. A recording's end marker,
/// when it has no last chunk, waits as `end.json` until the session can queue it with `transferUserInfo`.
@MainActor @Observable
final class WatchOutbox {
    /// A transport boundary keeps filesystem/retry tests away from the app's live WCSession.
    struct Transport {
        let isActive: () -> Bool
        let outstandingURLs: () -> Set<URL>
        let sendFile: (URL, [String: Any]) -> Void
        let sendUserInfo: ([String: Any]) -> Void
        let cancelOutstanding: () -> Void

        static func live(_ session: WCSession) -> Self {
            Self(isActive: { session.activationState == .activated },
                 outstandingURLs: { Set(session.outstandingFileTransfers.map(\.file.fileURL)) },
                 sendFile: { session.transferFile($0, metadata: $1) },
                 sendUserInfo: { session.transferUserInfo($0) },
                 cancelOutstanding: { for transfer in session.outstandingFileTransfers { transfer.cancel() } })
        }
    }

    /// Recordings with at least one chunk not yet delivered.
    private(set) var waitingRecordings = 0
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let recordingRoot: URL
    @ObservationIgnored private let recordingIsActive: () -> Bool
    /// Folders with audio/end intent still owned locally; Delete is blocked during capture.
    @ObservationIgnored private var recoveryFolders: Set<URL> = []
    /// Metadata of chunks added or seen in a transfer this launch, by `<recordingID>/<index>.m4a`.
    @ObservationIgnored private var known: [String: WatchChunkMetadata] = [:]
    /// Failed transfers per chunk, for the retry delay. Reset at launch.
    @ObservationIgnored private var attempts: [String: Int] = [:]
    @ObservationIgnored private var retries: [String: Task<Void, Never>] = [:]
    private static let endName = "end.json"
    private static let recoveryEndName = ".recovery-end.plist"
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios.watchkitapp", category: "WatchOutbox")

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Outbox", isDirectory: true)
    }

    /// Runs at launch, before anything can record, and recovers what a killed launch left in
    /// `recordingRoot` (see `recoverUnfinished`).
    init(session: WCSession = .default, root: URL = WatchOutbox.defaultRoot,
         recordingRoot: URL = WatchRecorder.recordingRoot, transport: Transport? = nil,
         recordingIsActive: @escaping () -> Bool = { false }) {
        self.transport = transport ?? .live(session)
        self.root = root
        self.recordingRoot = recordingRoot
        self.recordingIsActive = recordingIsActive
        recoverUnfinished(in: recordingRoot)
        recount()
    }

    /// Takes a finished, closed chunk from the recorder and starts sending it.
    func add(_ url: URL, _ metadata: WatchChunkMetadata) throws {
        do { try accept(url, metadata) } catch {
            let folder = recordingFolder(metadata.recordingID)
            if url.deletingLastPathComponent().standardizedFileURL.path == folder.path,
               FileManager.default.fileExists(atPath: url.path) {
                recoveryFolders.insert(folder)
                recount()
            }
            throw error
        }
    }

    private func accept(_ url: URL, _ metadata: WatchChunkMetadata) throws {
        let folder = try makeFolder(metadata.recordingID)
        let destination = folder.appendingPathComponent("\(metadata.index).m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            // A repeated callback must not remove an unacknowledged chunk. Conflicting audio
            // stays with the recorder; neither copy is silently overwritten.
            let sameURL = url.standardizedFileURL == destination.standardizedFileURL
            let sourceExists = FileManager.default.fileExists(atPath: url.path)
            guard self.metadata(for: destination) == metadata else {
                throw CocoaError(.fileWriteFileExists)
            }
            if !sameURL, sourceExists {
                guard try Data(contentsOf: url) == Data(contentsOf: destination) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: sidecar(for: url))
            }
            finishSourceHandoff(url, metadata)
            recount()
            return
        }
        // A completed handoff needs durable metadata as well as audio. If writing it fails,
        // leave the original audio and its recovery placeholder with the recorder.
        try JSONEncoder().encode(metadata).write(to: sidecar(for: destination), options: .atomic)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: sidecar(for: destination))
            throw error
        }
        // The recorder's placeholder for this chunk is no longer needed.
        try? FileManager.default.removeItem(at: sidecar(for: url))
        known[key(destination)] = metadata
        finishSourceHandoff(url, metadata)
        recount()
        send(destination, metadata)
    }

    /// The recording ended without a last chunk (see `WatchRecorder.onRecordingEnded`).
    @discardableResult
    func sendEnd(_ end: WatchRecordingEnd) -> Bool {
        let recovery = recordingFolder(end.recordingID)
        // Failed live handoffs may still own audio here. Preserve their actual final boundary
        // even if the system queues the end before those files can enter the outbox.
        if FileManager.default.fileExists(atPath: recovery.path) {
            do { try preserveRecoveryEnd(end, in: recovery) } catch {
                Self.log.error("Recovery end not written: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: end.userInfo, format: .binary, options: 0)
            try data.write(to: makeFolder(end.recordingID).appendingPathComponent(Self.endName), options: .atomic)
        } catch {
            Self.log.error("End marker not written: \(error.localizedDescription, privacy: .public)")
            if transport.isActive() {
                transport.sendUserInfo(end.userInfo)
                removeCompletedRecovery(in: recovery)
                recount()
                return true
            }
            do { try preserveRecoveryEnd(end, in: recovery) } catch {
                Self.log.error("End recovery intent not written: \(error.localizedDescription, privacy: .public)")
            }
            recount()
            return false
        }
        flushEnds()
        removeCompletedRecovery(in: recovery)
        recount()
        return true
    }

    /// Once the session is active (at launch): queues every chunk the system is not already sending,
    /// and every end marker still waiting.
    func reconcileAtLaunch(outstanding: [WCSessionFileTransfer]) {
        for transfer in outstanding {
            remember(transfer.file.metadata.flatMap { try? WatchChunkMetadata(transferMetadata: $0) },
                     for: transfer.file.fileURL)
        }
        let queued = Set(outstanding.map(\.file.fileURL)).union(transport.outstandingURLs())
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
        // The recording screen hides Delete; also enforce that ownership at the model boundary.
        guard !recordingIsActive() else { return }
        transport.cancelOutstanding()
        for task in retries.values { task.cancel() }
        retries = [:]
        attempts = [:]
        known = [:]
        for folder in recordingFolders() { try? FileManager.default.removeItem(at: folder) }
        for folder in recoveryFolders { try? FileManager.default.removeItem(at: folder) }
        recoveryFolders = recoveryFolders.filter { FileManager.default.fileExists(atPath: $0.path) }
        recount()
    }

    // MARK: Sending

    private func send(_ url: URL, _ metadata: WatchChunkMetadata) {
        // Before activation completes, `reconcileAtLaunch` queues it instead.
        guard transport.isActive() else { return }
        transport.sendFile(url, metadata.transferMetadata)
    }

    private func retry(_ url: URL, key: String) {
        retries[key] = nil
        let outstanding = transport.outstandingURLs()
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
        guard transport.isActive() else { return }
        for folder in recordingFolders() {
            let url = folder.appendingPathComponent(Self.endName)
            guard let data = try? Data(contentsOf: url) else { continue }
            if let userInfo = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                transport.sendUserInfo(userInfo)
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
        var pending = Set(chunkURLs().map { $0.deletingLastPathComponent().lastPathComponent })
        for folder in recordingFolders() where FileManager.default.fileExists(atPath: folder.appendingPathComponent(Self.endName).path) {
            pending.insert(folder.lastPathComponent)
        }
        for folder in recoveryFolders where FileManager.default.fileExists(atPath: folder.path) {
            pending.insert(folder.lastPathComponent)
        }
        let count = pending.count
        guard count != waitingRecordings else { return }
        waitingRecordings = count
        onChange?()
    }
}

extension WatchOutbox {
    // MARK: Recovery

    /// A killed launch can leave chunks in `recordingRoot`. Only the highest index can be unfinished
    /// (a rotation closes a chunk before opening the next): it is sent if it can be read, otherwise
    /// deleted. Every lower one is complete, only never handed over, and is sent. The iPhone is then
    /// told the recording ended unexpectedly, naming the highest index, so a lost chunk shows as a gap.
    /// An empty folder is a run stopped by an interruption, whose last chunk already said so.
    private func recoverUnfinished(in recordingRoot: URL) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: recordingRoot, includingPropertiesForKeys: nil))
            ?? []
        for originalFolder in folders {
            let folder = normalizedDirectory(originalFolder)
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            recoveryFolders.insert(folder)
            var queueFailed = false
            defer {
                if !queueFailed { try? FileManager.default.removeItem(at: folder) }
                if !FileManager.default.fileExists(atPath: folder.path) { recoveryFolders.remove(folder) }
            }
            let savedEnd: WatchRecordingEnd?
            do {
                let intent = folder.appendingPathComponent(Self.recoveryEndName)
                savedEnd = FileManager.default.fileExists(atPath: intent.path) ? try recoveryEnd(at: intent) : nil
                if let savedEnd, savedEnd.recordingID != id { throw CocoaError(.fileReadCorruptFile) }
            } catch {
                queueFailed = true
                Self.log.error("Recovery end unreadable: \(error.localizedDescription, privacy: .public)")
                continue
            }
            let indices = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .compactMap { $0.hasSuffix(".m4a") ? Int($0.dropLast(4)) : nil }.sorted()
            guard let highest = indices.last else {
                if let savedEnd, !sendEnd(savedEnd) { queueFailed = true }
                continue
            }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            let continuedPastEnd = savedEnd.map { highest > $0.lastIndex } ?? false
            let end = WatchRecordingEnd(recordingID: id,
                startedAt: savedEnd?.startedAt ?? pendingMetadata(folder, highest)?.startedAt ?? created ?? Date(),
                lastIndex: max(savedEnd?.lastIndex ?? highest, highest),
                unexpected: (savedEnd?.unexpected ?? true) || continuedPastEnd)
            // Save the end before moving any audio. Retaining an empty folder alone cannot
            // recover the boundary if the final outbox end-marker write later fails.
            do { try preserveRecoveryEnd(end, in: folder) } catch {
                queueFailed = true
                Self.log.error("Recovery end not saved: \(error.localizedDescription, privacy: .public)")
                continue
            }
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
                    queueFailed = true
                    Self.log.error("Recovered chunk not queued: \(error.localizedDescription, privacy: .public)")
                    // Keep the tail here too, so a later launch still knows the real final index.
                    break
                }
            }
            // Keep the original audio/metadata for another launch and do not announce an end
            // while readable parts are still unable to enter the durable outbox.
            guard !queueFailed else { continue }
            // Nothing at all was recorded: there is nothing to tell the iPhone.
            guard highest > 0 || keptHighest else { continue }
            if !sendEnd(end) { queueFailed = true }
        }
    }

    private func preserveRecoveryEnd(_ end: WatchRecordingEnd, in folder: URL) throws {
        let folder = normalizedDirectory(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: WatchRecorder.protection)
        recoveryFolders.insert(folder)
        let data = try PropertyListSerialization.data(fromPropertyList: end.userInfo, format: .binary, options: 0)
        try data.write(to: folder.appendingPathComponent(Self.recoveryEndName), options: .atomic)
    }

    private func recoveryEnd(at url: URL) throws -> WatchRecordingEnd {
        guard let fields = try PropertyListSerialization.propertyList(from: Data(contentsOf: url),
                                                                      format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try WatchRecordingEnd(userInfo: fields)
    }

    /// Once the end is durable/queued, an intent without remaining audio is no longer pending.
    private func removeCompletedRecovery(in folder: URL) {
        let folder = normalizedDirectory(folder)
        guard recoveryFolders.contains(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              !names.contains(where: { $0.hasSuffix(".m4a") }) else { return }
        try? FileManager.default.removeItem(at: folder)
        if !FileManager.default.fileExists(atPath: folder.path) { recoveryFolders.remove(folder) }
    }

    private func finishSourceHandoff(_ source: URL, _ metadata: WatchChunkMetadata) {
        let folder = recordingFolder(metadata.recordingID)
        guard metadata.isLast, recoveryFolders.contains(folder),
              source.deletingLastPathComponent().standardizedFileURL.path == folder.path else { return }
        let old = try? recoveryEnd(at: folder.appendingPathComponent(Self.recoveryEndName))
        let end = WatchRecordingEnd(recordingID: metadata.recordingID, startedAt: metadata.startedAt,
                                    lastIndex: max(old?.lastIndex ?? metadata.index, metadata.index),
                                    unexpected: old?.unexpected ?? false)
        try? preserveRecoveryEnd(end, in: folder)
        removeCompletedRecovery(in: folder)
    }

    private func normalizedDirectory(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    private func recordingFolder(_ id: UUID) -> URL {
        normalizedDirectory(recordingRoot.appendingPathComponent(id.uuidString))
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
}
