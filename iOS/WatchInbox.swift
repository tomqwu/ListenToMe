import AVFoundation
import Foundation
import ListenToMeCore
import os

/// Apple Watch audio waiting on this iPhone (issue #181): one folder per recording holding its
/// chunks as `<index>.m4a`, each chunk's metadata as `<index>.json`, and the recording's
/// `WatchCaptureLedger` as `manifest.json`.
///
/// Not main-actor: `accept` runs on the WatchConnectivity delegate queue, which may have woken the
/// app in the background. It only files bytes; it never starts audio or transcription. Every read
/// and write of a manifest holds one process-wide lock, so a chunk filed while the foreground drain
/// is transcribing is never lost when the drain saves its progress.
///
/// Delivered audio is never deleted because something about it could not be written: the watch
/// deletes its copy once the transfer succeeds. A chunk whose manifest entry is missing is adopted
/// by `tidy` before the next drain, from its metadata file or, failing that, a best guess.
struct WatchInbox: Sendable {
    enum Acceptance: Equatable {
        case stored, duplicate, rejected(String)
        /// The recording's conversation was deleted; see `removeRecording(_:tombstoneAt:)`.
        case discarded
    }

    private static let lock = NSRecursiveLock()
    private static let manifestName = "manifest.json"
    /// Left in a recording's folder when its conversation is deleted; see `removeRecording`.
    private static let deletedMarkerName = "deleted"
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios", category: "WatchInbox")
    /// How long a completed recording's tombstone manifest is kept for a late Continue or resend.
    static let tombstoneLifetime: TimeInterval = 7 * 86_400
    /// Stored audio gets the conversation archive's protection class.
    static var chunkAttributes: [FileAttributeKey: Any] { PrivateStorage.directoryAttributes }

    let root: URL
    /// Writes manifests and metadata files. Tests replace it to simulate a full disk.
    var writeFile: @Sendable (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: PrivateStorage.writingOptions)
    }
    /// Audio-file ownership transfer. Tests can fail this boundary after valid delivery preflight.
    var moveFile: @Sendable (URL, URL) throws -> Void = { source, destination in
        try FileManager.default.moveItem(at: source, to: destination)
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("WatchInbox", isDirectory: true)
    }

    /// Validates and files one delivered chunk. The file is moved before this returns: the system
    /// deletes it as soon as the delegate call ends. The stored name comes only from the parsed
    /// recording id and index, never from the metadata's text.
    func accept(fileAt url: URL, metadata: [String: Any], now: Date) -> Acceptance {
        // The watch deletes a part once it is delivered, so a refused part is gone: the copy says so
        // in plain words, and the technical reason goes only to the log.
        let chunk: WatchChunkMetadata
        do { chunk = try WatchChunkMetadata(transferMetadata: metadata) } catch {
            Self.log.error("Chunk metadata unreadable: \(String(describing: error), privacy: .public)")
            if case WatchLinkError.unsupportedVersion = error {
                return refuse("An Apple Watch recording part came from another version of ListenToMe, so it is "
                    + "missing from the recording. Update ListenToMe on your iPhone and Apple Watch.")
            }
            return refuse("An Apple Watch recording part could not be read, so it is missing from the recording.")
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return refuse("An Apple Watch recording part arrived without its audio.")
        }
        guard size <= WatchChunkMetadata.maximumFileBytes else {
            return refuse("An Apple Watch recording part was too large to keep.")
        }
        return Self.locked {
            if isDeleted(chunk.recordingID, now: now) { return .discarded }
            var ledger = readLedgerSettingAside(chunk.recordingID)
                ?? WatchCaptureLedger(recordingID: chunk.recordingID, startedAt: chunk.startedAt, at: now)
            guard ledger.receive(chunk, at: now) else { return .duplicate }
            let destination = chunkURL(recordingID: chunk.recordingID, index: chunk.index)
            do {
                try PrivateStorage.createDirectory(at: folder(chunk.recordingID))
                // A copy left by an earlier delivery whose manifest entry was never written.
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try moveFile(url, destination)
            } catch {
                Self.log.error("Chunk not stored: \(error.localizedDescription, privacy: .public)")
                return refuse("An Apple Watch recording part could not be stored on this iPhone, so it is missing "
                    + "from the recording. Free some space on this iPhone.")
            }
            // From here the audio is ours. Nothing below may delete it: a failure only costs the
            // index, which `tidy` rebuilds.
            do {
                try writeFile(try JSONEncoder().encode(chunk), metadataURL(chunk.recordingID, chunk.index))
            } catch {
                Self.log.error("Chunk metadata not written: \(error.localizedDescription, privacy: .public)")
            }
            if !Self.chunkAttributes.isEmpty {
                do {
                    try FileManager.default.setAttributes(Self.chunkAttributes, ofItemAtPath: destination.path)
                } catch {
                    Self.log.error("Chunk protection not set: \(error.localizedDescription, privacy: .public)")
                }
            }
            do { try write(ledger) } catch {
                let reason = error.localizedDescription
                Self.log.error("Manifest not written; the chunk is kept for later: \(reason, privacy: .public)")
            }
            excludeFromBackupUnlocked()
            return .stored
        }
    }

    /// The watch's note that a recording ended without a last chunk. It may arrive before any chunk.
    func acceptEnd(userInfo: [String: Any], now: Date) {
        guard let end = try? WatchRecordingEnd(userInfo: userInfo) else { return }
        Self.locked {
            guard !isDeleted(end.recordingID, now: now) else { return }
            var ledger = readLedgerSettingAside(end.recordingID)
                ?? WatchCaptureLedger(recordingID: end.recordingID, startedAt: end.startedAt, at: now)
            ledger.receiveEnd(end, at: now)
            do {
                try PrivateStorage.createDirectory(at: folder(end.recordingID))
                try write(ledger)
            } catch {
                Self.log.error("End marker not written: \(error.localizedDescription, privacy: .public)")
                return
            }
            excludeFromBackupUnlocked()
        }
    }

    /// Every readable recording, oldest first. An unreadable manifest is skipped, not deleted.
    func ledgers() -> [WatchCaptureLedger] {
        Self.locked {
            recordingFolders().compactMap { UUID(uuidString: $0.lastPathComponent).flatMap(readLedger) }
                .sorted { $0.startedAt < $1.startedAt }
        }
    }

    func ledger(_ id: UUID) -> WatchCaptureLedger? {
        Self.locked { readLedger(id) }
    }

    func save(_ ledger: WatchCaptureLedger) throws {
        try Self.locked { try write(ledger) }
    }

    /// Changes one recording's manifest as it is on disk now, so chunks filed since the caller last
    /// read it are kept. `nil` when the recording is no longer in the inbox.
    func update<T>(_ id: UUID, _ change: (inout WatchCaptureLedger) -> T) throws -> T? {
        try Self.locked {
            guard var ledger = readLedger(id) else { return nil }
            let result = change(&ledger)
            try write(ledger)
            return result
        }
    }

    func chunkURL(recordingID: UUID, index: Int) -> URL {
        folder(recordingID).appendingPathComponent("\(index).m4a")
    }

    /// Deletes chunks' audio (and their metadata files). Only for chunks whose text is saved.
    func deleteChunks(_ indices: [Int], of recordingID: UUID) {
        for index in indices {
            try? FileManager.default.removeItem(at: chunkURL(recordingID: recordingID, index: index))
            try? FileManager.default.removeItem(at: metadataURL(recordingID, index))
        }
    }

    /// Deletes a recording's audio and manifest: the user deleted it, or its conversation. With
    /// `deletedAt` (the conversation was deleted), a tombstone stays for `tombstoneLifetime`, so a part
    /// the watch sends again is discarded instead of starting a new conversation (#191). Without it
    /// (only the audio was deleted) a later Continue part reopens the conversation. Throws only when the
    /// audio could not be deleted: a tombstone that cannot be written is logged, since the audio is gone.
    func removeRecording(_ id: UUID, tombstoneAt deletedAt: Date? = nil) throws {
        try Self.locked {
            let folder = folder(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            guard let deletedAt else { return }
            do {
                try PrivateStorage.createDirectory(at: folder)
                try writeFile(Data(String(deletedAt.timeIntervalSince1970).utf8), deletedMarkerURL(id))
            } catch {
                let reason = error.localizedDescription
                Self.log.error("Deleted-recording tombstone not written: \(reason, privacy: .public)")
            }
            excludeFromBackupUnlocked()
        }
    }

    /// Marks a recording complete if, as it is on disk now, nothing is left to transcribe and it is
    /// over. The manifest stays as a tombstone (see `WatchCaptureLedger.completed`); any audio left
    /// over is deleted. A chunk filed since the caller last looked keeps the recording open, and so
    /// does audio the manifest never listed (a manifest write failed): it is adopted first, never
    /// swept away (#191).
    func completeRecording(_ id: UUID, now: Date) throws -> Bool {
        try Self.locked {
            adoptOrphans(id, now: now)
            guard var ledger = readLedger(id) else { return false }
            let batch = ledger.nextBatch(now: now)
            guard batch.finishes, batch.indices.isEmpty, batch.newGaps.isEmpty else { return false }
            ledger.markCompleted()
            try write(ledger)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder(id).path)) ?? []
            where name.hasSuffix(".m4a") || (name.hasSuffix(".json") && name != Self.manifestName) {
                try? FileManager.default.removeItem(at: folder(id).appendingPathComponent(name))
            }
            return true
        }
    }

    /// Housekeeping before a drain, in the foreground: sets aside unreadable manifests, adopts audio
    /// the manifest does not list, and drops tombstones older than `tombstoneLifetime`.
    func tidy(now: Date) {
        Self.locked {
            for folder in recordingFolders() {
                guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
                if FileManager.default.fileExists(atPath: deletedMarkerURL(id).path) {
                    if !isDeleted(id, now: now) { try? FileManager.default.removeItem(at: folder) }
                    continue
                }
                adoptOrphans(id, now: now)
                if let ledger = readLedger(id), ledger.completed,
                   now.timeIntervalSince(ledger.lastActivity) > Self.tombstoneLifetime,
                   audioIndices(id).isEmpty {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }

    /// Raw watch audio is transient and promised to stay on this iPhone: it is kept out of iCloud
    /// Backup whatever the conversations' backup setting says.
    func applyBackupExclusion() {
        Self.locked { excludeFromBackupUnlocked() }
    }

    // MARK: Problems shown in History

    /// Audio that could not be kept. Stored outside the inbox (it may be the inbox that failed) and
    /// shown in History until dismissed.
    func problems() -> [String] {
        UserDefaults.standard.stringArray(forKey: problemsKey) ?? []
    }

    func clearProblems() {
        UserDefaults.standard.removeObject(forKey: problemsKey)
    }

    private func refuse(_ text: String) -> Acceptance {
        Self.log.error("\(text, privacy: .public)")
        Self.locked {
            UserDefaults.standard.set(Array((problems() + [text]).suffix(10)), forKey: problemsKey)
        }
        return .rejected(text)
    }

    /// Stable across app updates, which move the app's container: the inbox's last two path parts.
    private var problemsKey: String {
        "watchInboxProblems:" + root.deletingLastPathComponent().lastPathComponent + "/" + root.lastPathComponent
    }

    // MARK: Helpers

    private func excludeFromBackupUnlocked() {
        try? PrivateStorage.createDirectory(at: root)
        try? PrivateStorage.setExcludedFromBackup(true, at: root)
        for folder in recordingFolders() { try? PrivateStorage.setExcludedFromBackup(true, at: folder) }
    }

    private func recordingFolders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }

    private func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(_ id: UUID) -> URL {
        folder(id).appendingPathComponent(Self.manifestName)
    }

    private func metadataURL(_ id: UUID, _ index: Int) -> URL {
        folder(id).appendingPathComponent("\(index).json")
    }

    private func deletedMarkerURL(_ id: UUID) -> URL {
        folder(id).appendingPathComponent(Self.deletedMarkerName)
    }

    /// The recording's conversation was deleted less than `tombstoneLifetime` before `now`. An expired
    /// tombstone is removed here, so the next delivery files normally.
    private func isDeleted(_ id: UUID, now: Date) -> Bool {
        let url = deletedMarkerURL(id)
        guard let data = try? Data(contentsOf: url) else { return false }
        if let text = String(bytes: data, encoding: .utf8), let seconds = Double(text),
           now.timeIntervalSince(Date(timeIntervalSince1970: seconds)) > Self.tombstoneLifetime {
            try? FileManager.default.removeItem(at: folder(id))
            return false
        }
        // An unreadable marker still means the user deleted the conversation.
        return true
    }

    private func readLedger(_ id: UUID) -> WatchCaptureLedger? {
        guard let data = try? Data(contentsOf: manifestURL(id)),
              let ledger = try? JSONDecoder().decode(WatchCaptureLedger.self, from: data),
              ledger.recordingID == id else { return nil }
        return ledger
    }

    /// Like `readLedger`, but a manifest that exists and cannot be read is renamed out of the way
    /// first, so writing a new one never destroys it. Its chunks are adopted again by `tidy`.
    private func readLedgerSettingAside(_ id: UUID) -> WatchCaptureLedger? {
        if let ledger = readLedger(id) { return ledger }
        let url = manifestURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let suffix = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
        let aside = url.deletingLastPathComponent().appendingPathComponent("\(Self.manifestName).corrupt-\(suffix)")
        do { try FileManager.default.moveItem(at: url, to: aside) } catch {
            Self.log.error("Unreadable manifest not set aside: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func write(_ ledger: WatchCaptureLedger) throws {
        try writeFile(try JSONEncoder().encode(ledger), manifestURL(ledger.recordingID))
    }

    private func audioIndices(_ id: UUID) -> [Int] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder(id).path)) ?? [])
            .compactMap { $0.hasSuffix(".m4a") ? Int($0.dropLast(4)) : nil }.sorted()
    }

    /// Lists audio the manifest does not: from its metadata file, or a best guess placed after the
    /// chunk before it. Audio the ledger turns down (already text) is deleted.
    private func adoptOrphans(_ id: UUID, now: Date) {
        var ledger = readLedgerSettingAside(id)
        var changed = false
        for index in audioIndices(id) where !(ledger?.chunks.contains { $0.index == index } ?? false) {
            guard (0...WatchChunkMetadata.maximumIndex).contains(index) else { continue }
            let chunk = sidecar(id, index) ?? guessedChunk(id, index, ledger: ledger, now: now)
            var adopted = ledger ?? WatchCaptureLedger(recordingID: id, startedAt: chunk.startedAt, at: now)
            if adopted.receive(chunk, at: now) {
                Self.log.notice("Adopted Apple Watch chunk \(index, privacy: .public) missing from its manifest")
            } else {
                deleteChunks([index], of: id)
            }
            ledger = adopted
            changed = true
        }
        guard changed, let ledger else { return }
        do { try write(ledger) } catch {
            Self.log.error("Adopted chunks not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sidecar(_ id: UUID, _ index: Int) -> WatchChunkMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(id, index)),
              let chunk = try? JSONDecoder().decode(WatchChunkMetadata.self, from: data),
              chunk.recordingID == id, chunk.index == index else { return nil }
        return chunk
    }

    private func guessedChunk(_ id: UUID, _ index: Int, ledger: WatchCaptureLedger?, now: Date) -> WatchChunkMetadata {
        let folderCreated = (try? folder(id).resourceValues(forKeys: [.creationDateKey]))?.creationDate
        let startedAt = ledger?.startedAt ?? folderCreated ?? now
        let previous = ledger?.chunks.last { $0.index < index }
        let file = try? AVAudioFile(forReading: chunkURL(recordingID: id, index: index))
        let seconds = file.map { Double($0.length) / max(1, $0.processingFormat.sampleRate) } ?? 300
        let duration = seconds > 0 && seconds < WatchChunkMetadata.maximumDuration ? seconds : 300
        return WatchChunkMetadata(recordingID: id, index: index,
                                  startOffset: previous?.end ?? Double(index) * 300, duration: duration,
                                  isLast: false, startedAt: startedAt, watchBuild: "unknown")
    }

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
