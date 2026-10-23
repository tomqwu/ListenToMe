import Foundation
import ListenToMeCore

/// Apple Watch audio waiting on this iPhone (issue #181): one folder per recording holding its
/// chunks as `<index>.m4a` and its `WatchCaptureLedger` as `manifest.json`.
///
/// Not main-actor: `accept` runs on the WatchConnectivity delegate queue, which may have woken the
/// app in the background. It only files bytes; it never starts audio or transcription. Every read
/// and write of a manifest holds one process-wide lock, so a chunk filed while the foreground drain
/// is transcribing is never lost when the drain saves its progress.
struct WatchInbox: Sendable {
    enum Acceptance: Equatable {
        case stored, duplicate, rejected(String)
    }

    private static let lock = NSLock()
    private static let manifestName = "manifest.json"
    /// Stored audio gets the conversation archive's protection class.
    static var chunkAttributes: [FileAttributeKey: Any] { PrivateStorage.directoryAttributes }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("WatchInbox", isDirectory: true)
    }

    /// Validates and files one delivered chunk. The file is moved before this returns: the system
    /// deletes it as soon as the delegate call ends. The stored name comes only from the parsed
    /// recording id and index, never from the metadata's text.
    func accept(fileAt url: URL, metadata: [String: Any], now: Date) -> Acceptance {
        let chunk: WatchChunkMetadata
        do { chunk = try WatchChunkMetadata(transferMetadata: metadata) } catch {
            return .rejected("Unreadable Apple Watch chunk: \(error)")
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return .rejected("The delivered Apple Watch audio is missing.")
        }
        guard size <= WatchChunkMetadata.maximumFileBytes else {
            return .rejected("The delivered Apple Watch audio is too large.")
        }
        return Self.locked {
            var ledger = readLedger(chunk.recordingID)
                ?? WatchCaptureLedger(recordingID: chunk.recordingID, startedAt: chunk.startedAt, at: now)
            guard ledger.receive(chunk, at: now) else { return .duplicate }
            let folder = folder(chunk.recordingID)
            let destination = chunkURL(recordingID: chunk.recordingID, index: chunk.index)
            do {
                try PrivateStorage.createDirectory(at: folder)
                // A file left by an earlier delivery whose manifest write failed.
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: url, to: destination)
                if !Self.chunkAttributes.isEmpty {
                    try FileManager.default.setAttributes(Self.chunkAttributes, ofItemAtPath: destination.path)
                }
                try write(ledger)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                return .rejected("Could not store Apple Watch audio: \(error.localizedDescription)")
            }
            // Read here, not from a session: the app may be running in the background with none.
            applyBackupExclusionUnlocked(UserDefaults.standard.bool(forKey: MobileSession.excludeBackupKey))
            return .stored
        }
    }

    /// The watch's note that a recording ended without a last chunk. It may arrive before any chunk.
    func acceptEnd(userInfo: [String: Any], now: Date) {
        guard let end = try? WatchRecordingEnd(userInfo: userInfo) else { return }
        Self.locked {
            var ledger = readLedger(end.recordingID)
                ?? WatchCaptureLedger(recordingID: end.recordingID, startedAt: end.startedAt, at: now)
            ledger.receiveEnd(end, at: now)
            do {
                try PrivateStorage.createDirectory(at: folder(end.recordingID))
                try write(ledger)
            } catch { return }
            applyBackupExclusionUnlocked(UserDefaults.standard.bool(forKey: MobileSession.excludeBackupKey))
        }
    }

    /// Every readable recording, oldest first. An unreadable manifest is skipped, not deleted.
    func ledgers() -> [WatchCaptureLedger] {
        Self.locked {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return folders.compactMap { UUID(uuidString: $0.lastPathComponent).flatMap(readLedger) }
                .sorted { $0.startedAt < $1.startedAt }
        }
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

    func deleteChunks(_ indices: [Int], of recordingID: UUID) {
        for index in indices { try? FileManager.default.removeItem(at: chunkURL(recordingID: recordingID, index: index)) }
    }

    func removeRecording(_ id: UUID) throws {
        try Self.locked {
            let folder = folder(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }

    /// Applies the conversations' backup choice to audio that has not become a conversation yet.
    func applyBackupExclusion(_ excluded: Bool) {
        Self.locked { applyBackupExclusionUnlocked(excluded) }
    }

    // MARK: Helpers

    private func applyBackupExclusionUnlocked(_ excluded: Bool) {
        try? PrivateStorage.createDirectory(at: root)
        try? PrivateStorage.setExcludedFromBackup(excluded, at: root)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders { try? PrivateStorage.setExcludedFromBackup(excluded, at: folder) }
    }

    private func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func readLedger(_ id: UUID) -> WatchCaptureLedger? {
        let url = folder(id).appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(WatchCaptureLedger.self, from: data),
              ledger.recordingID == id else { return nil }
        return ledger
    }

    private func write(_ ledger: WatchCaptureLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        try data.write(to: folder(ledger.recordingID).appendingPathComponent(Self.manifestName),
                       options: PrivateStorage.writingOptions)
    }

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
