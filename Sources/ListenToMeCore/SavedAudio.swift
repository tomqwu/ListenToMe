import Foundation

/// Saving the raw audio of a recording (issue #55). Off by default: transcripts are what this app
/// keeps, and audio is kept only when the user turns Save audio recordings on. Audio never leaves the
/// device through this feature; it is written next to the conversations, can be played back and
/// shared from the share sheet, and is deleted with its conversation, by Delete all saved audio, or
/// after the retention the user chose.
///
/// Format: AAC in an `.m4a` file, 16 kHz mono at 24 kbit/s (about 12 MB per hour per track). 16 kHz is
/// the rate every transcriber and the speaker and language buffers already use, it is the same whatever
/// microphone is connected (a headset changes the native rate mid-recording), and it keeps a long
/// meeting small. It is speech quality, not music quality.
public enum SavedAudioPolicy {
    /// UserDefaults key for the opt-in. Absent means off.
    public static let enabledKey = "saveRawAudio"
    /// UserDefaults key for automatic deletion, in days; 0 keeps audio until the user deletes it.
    public static let retentionDaysKey = "savedAudioRetentionDays"
    /// The automatic-deletion choices offered in Settings.
    public static let retentionChoices = [0, 7, 30, 90]
    public static let sampleRate: Double = 16_000
    public static let bitRate = 24_000
    public static let fileExtension = "m4a"
    /// Measured: 24 kbit/s AAC plus the container is about 204 KB per minute.
    public static let bytesPerHour: Int64 = 12_250_000
    /// Below this much free storage a recording does not start saving audio (the transcript still runs).
    public static let lowStorageBytes: Int64 = 100_000_000

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// The stored retention, or 0 (keep) when nothing valid is stored.
    public static func retentionDays(in defaults: UserDefaults = .standard) -> Int {
        let days = defaults.integer(forKey: retentionDaysKey)
        return retentionChoices.contains(days) ? days : 0
    }

    public static func retentionLabel(_ days: Int) -> String {
        days <= 0 ? "Keep until I delete it" : "Delete after \(days) days"
    }

    /// "Saved audio uses 24 MB on this device." Byte counts use the file-size style Finder and Files use.
    public static func usageText(bytes: Int64, device: String = "this device") -> String {
        guard bytes > 0 else { return "No saved audio on \(device)." }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "Saved audio uses \(size) on \(device)."
    }

    /// How much one hour of recording costs, for the setting's explanation.
    public static func estimateText(tracks: Int = 1) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytesPerHour * Int64(max(1, tracks)), countStyle: .file)
        return "About \(size) per hour of recording"
    }

    /// Why audio is not saved for a recording that is about to start, or `nil` when it can be.
    public static func startBlockedReason(availableBytes: Int64?) -> String? {
        guard let availableBytes, availableBytes < lowStorageBytes else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: lowStorageBytes, countStyle: .file)
        return "Audio is not being saved: less than \(size) of storage is free. Transcription continues."
    }

    /// What the user sees when writing stops part-way. Transcription is never stopped for it.
    public static func failureMessage(_ error: Error, availableBytes: Int64?) -> String {
        if isOutOfSpace(error) || (availableBytes.map { $0 < lowStorageBytes / 10 } ?? false) {
            return "Saving audio stopped: storage is full. Transcription continues; audio recorded so far is kept."
        }
        return "Saving audio stopped: \(error.localizedDescription) Transcription continues; "
            + "audio recorded so far is kept."
    }

    /// "4:05", or "1:02:03" from an hour on, for the player and the lines that seek.
    public static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3_600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// The writer could not keep up with the microphone, so it stopped rather than buffer without limit.
    public static let fellBehindMessage =
        "Saving audio stopped: the device could not write audio fast enough. Transcription continues."

    static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileWriteOutOfSpace.rawValue { return true }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}

/// One saved file: one source of one recording run. A conversation started several times has several
/// runs; on a Mac each run has a microphone file and, when system audio was captured, a system file.
public struct SavedAudioRun: Codable, Equatable, Sendable, Identifiable {
    public var id: String { fileName }
    /// 1-based; the files of one run share it.
    public let index: Int
    public let source: SpeakerSource
    public let fileName: String
    public let startedAt: Date
    /// The transcript time at which the file's first sample plays. On iPhone, the time the run's lines
    /// start from; on a Mac, the capture time of the first audio the source delivered.
    public var timelineOffset: TimeInterval
    /// Whether the lines' times come from the audio itself, so a line can seek into this file. True
    /// on iPhone and for WhisperKit on a Mac; the Mac's Apple speech engines do not report times.
    public let timesMatchAudio: Bool
    /// The index of the run's first transcript line. Set on a Mac, where line times restart with each
    /// run; `nil` on iPhone, where they continue across runs and `timelineOffset` places the run.
    public var firstSegment: Int?
    /// Seconds written; `nil` while recording, or when the app ended before the file was closed.
    public var duration: TimeInterval?
    /// Why writing stopped early, when it did.
    public var failure: String?
    /// Origin of imported audio; absent in older microphone/system manifests.
    public var deviceName: String?

    public init(index: Int, source: SpeakerSource, fileName: String, startedAt: Date, timelineOffset: TimeInterval,
                timesMatchAudio: Bool, firstSegment: Int? = nil, duration: TimeInterval? = nil,
                failure: String? = nil, deviceName: String? = nil) {
        self.deviceName = deviceName
        self.index = index
        self.source = source
        self.fileName = fileName
        self.startedAt = startedAt
        self.timelineOffset = timelineOffset
        self.timesMatchAudio = timesMatchAudio
        self.firstSegment = firstSegment
        self.duration = duration
        self.failure = failure
    }

    /// "Part 2 · System audio", for the player's picker.
    public func title(partCount: Int) -> String {
        let name = deviceName ?? (source == .you ? "Microphone" : "System audio")
        return partCount > 1 ? "Part \(index) · \(name)" : name
    }
}

/// What a finished writer reports.
public struct SavedAudioRunResult: Sendable, Equatable {
    public let duration: TimeInterval
    /// The capture time of the first sample, when the capture stamps its audio (the Mac).
    public let firstTimestamp: TimeInterval?
    public let failure: String?

    public init(duration: TimeInterval, firstTimestamp: TimeInterval? = nil, failure: String? = nil) {
        self.duration = duration
        self.firstTimestamp = firstTimestamp
        self.failure = failure
    }
}

/// Where a transcript line plays from.
public enum SavedAudioSeek {
    public struct Target: Equatable, Sendable {
        public let run: SavedAudioRun
        public let time: TimeInterval
    }

    /// The file and time for the line at `index`, or `nil` when its times cannot be trusted or no saved
    /// file covers it. Runs placed by line index (the Mac) win over runs placed by time (iPhone).
    public static func target(for segment: TranscriptSegment, index: Int, in runs: [SavedAudioRun]) -> Target? {
        // A line the engine gave no time (Apple's Mac engines) can never point into the audio.
        guard TranscriptTimestamp.isTimed(segment) else { return nil }
        let candidates = runs.filter { $0.source == segment.source }.sorted { $0.index < $1.index }
        if candidates.contains(where: { $0.firstSegment != nil }) {
            guard let run = candidates.last(where: { ($0.firstSegment ?? Int.max) <= index }),
                  run.timesMatchAudio else { return nil }
            return target(segment.start, in: run)
        }
        guard let run = candidates.last(where: { $0.timelineOffset <= segment.start + 0.05 }),
              run.timesMatchAudio else { return nil }
        return target(segment.start, in: run)
    }

    private static func target(_ start: TimeInterval, in run: SavedAudioRun) -> Target? {
        let time = max(0, start - run.timelineOffset)
        if let duration = run.duration, time > duration + 1 { return nil }
        return Target(run: run, time: time)
    }
}

/// The saved audio of every conversation: `<root>/<conversation id>/audio.json` lists the runs, beside
/// one `.m4a` per run and source. Safe to call from any thread; manifest updates are serialized, and the
/// runs of each conversation are cached in memory so History does not read the disk for every row.
public final class SavedAudioLibrary: @unchecked Sendable {
    public let root: URL
    private let excludeFromBackup: Bool
    private let lock = NSLock()
    private let fileManager = FileManager.default
    static let manifestName = "audio.json"
    /// The playable runs of each conversation, as `runs(for:)` returns them. Guarded by `lock`;
    /// every write through this library invalidates the entries it touches.
    private var cache: [String: [SavedAudioRun]] = [:]

    private struct Manifest: Codable {
        var runs: [SavedAudioRun]
    }

    /// `excludeFromBackup` keeps the audio out of iCloud and Finder backups (always on iPhone).
    public init(root: URL, excludeFromBackup: Bool) {
        self.root = root
        self.excludeFromBackup = excludeFromBackup
    }

    /// Conversation IDs are UUIDs; anything else could escape the folder.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public func directory(for conversationID: String) throws -> URL {
        guard Self.isValidID(conversationID) else { throw CocoaError(.fileWriteInvalidFileName) }
        return root.appendingPathComponent(conversationID, isDirectory: true)
    }

    /// Adds one run with a file per source and returns them; the files are created by their writers.
    public func beginRun(conversationID: String, sources: [SpeakerSource], startedAt: Date,
                         timelineOffset: TimeInterval, timesMatchAudio: Bool) throws -> [SavedAudioRun] {
        let folder = try directory(for: conversationID)
        return try lock.withLock {
            try PrivateStorage.createDirectory(at: root)
            try PrivateStorage.createDirectory(at: folder)
            if excludeFromBackup { try? PrivateStorage.setExcludedFromBackup(true, at: root) }
            var manifest = readLocked(folder) ?? Manifest(runs: [])
            let index = (manifest.runs.map(\.index).max() ?? 0) + 1
            let runs = sources.map { source in
                SavedAudioRun(index: index, source: source,
                              fileName: "part-\(String(format: "%03d", index))-"
                                + "\(source == .you ? "microphone" : "system").\(SavedAudioPolicy.fileExtension)",
                              startedAt: startedAt, timelineOffset: timelineOffset, timesMatchAudio: timesMatchAudio)
            }
            manifest.runs += runs
            try writeLocked(manifest, to: folder)
            cache[conversationID] = nil
            return runs
        }
    }

    /// Copies a Watch part before its inbox copy can be deleted. The stable name makes retries
    /// idempotent, including a crash between the file move and the atomic manifest write.
    /// Never replaces an unreadable existing index or a successfully imported part.
    @discardableResult
    public func importWatchChunk(from source: URL, conversationID: String, recordingID: UUID, chunkIndex: Int,
                                 startedAt: Date, timelineOffset: TimeInterval,
                                 duration: TimeInterval) throws -> SavedAudioRun {
        guard chunkIndex >= 0, timelineOffset.isFinite, timelineOffset >= 0,
              duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let folder = try directory(for: conversationID)
        return try lock.withLock {
            try PrivateStorage.createDirectory(at: root)
            try PrivateStorage.createDirectory(at: folder)
            if excludeFromBackup { try PrivateStorage.setExcludedFromBackup(true, at: root) }
            let manifestURL = folder.appendingPathComponent(Self.manifestName)
            var manifest = fileManager.fileExists(atPath: manifestURL.path)
                ? try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) : Manifest(runs: [])
            let name = "watch-\(recordingID.uuidString)-\(chunkIndex).m4a"
            let destination = folder.appendingPathComponent(name)
            let existing = manifest.runs.first { $0.fileName == name }
            if let existing, fileManager.fileExists(atPath: destination.path) { return existing }
            // A leftover unindexed destination may be an interrupted import. Copy again from the
            // still-owned inbox file rather than trusting incomplete or corrupt bytes.
            let temporary = folder.appendingPathComponent(".watch-import-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: temporary) }
            try fileManager.copyItem(at: source, to: temporary)
            try fileManager.setAttributes(PrivateStorage.directoryAttributes, ofItemAtPath: temporary.path)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporary, to: destination)
            let run = existing ?? SavedAudioRun(index: (manifest.runs.map(\.index).max() ?? 0) + 1,
                source: .you, fileName: name, startedAt: startedAt, timelineOffset: timelineOffset,
                timesMatchAudio: true, duration: duration, deviceName: "Apple Watch")
            if existing == nil { manifest.runs.append(run) }
            try writeLocked(manifest, to: folder)
            cache[conversationID] = nil
            return run
        }
    }

    /// Records how a file ended. A file with no audio is removed. Nothing is recreated for a
    /// conversation whose audio was deleted meanwhile.
    public func finishRun(conversationID: String, fileName: String, result: SavedAudioRunResult) {
        guard let folder = try? directory(for: conversationID) else { return }
        lock.withLock {
            guard var manifest = readLocked(folder),
                  let position = manifest.runs.firstIndex(where: { $0.fileName == fileName }) else { return }
            let file = folder.appendingPathComponent(fileName)
            if result.duration <= 0 || !fileManager.fileExists(atPath: file.path) {
                try? fileManager.removeItem(at: file)
                manifest.runs.remove(at: position)
            } else {
                manifest.runs[position].duration = result.duration
                manifest.runs[position].failure = result.failure
                if let first = result.firstTimestamp { manifest.runs[position].timelineOffset += first }
            }
            try? removeOrWriteLocked(manifest, folder: folder)
            cache[conversationID] = nil
        }
    }

    /// Records the index of a run's first line once its capture has started (the Mac).
    public func anchor(conversationID: String, index: Int, firstSegment: Int) {
        guard let folder = try? directory(for: conversationID) else { return }
        lock.withLock {
            guard var manifest = readLocked(folder) else { return }
            for position in manifest.runs.indices where manifest.runs[position].index == index {
                manifest.runs[position].firstSegment = firstSegment
            }
            try? writeLocked(manifest, to: folder)
            cache[conversationID] = nil
        }
    }

    /// The runs that can be played: their file exists and was finished (or repaired after the app was
    /// killed, see `repairUnfinished`), in recording order, microphone before system audio. A run still
    /// being recorded is not listed, so it can neither be played nor shared half-written.
    public func runs(for conversationID: String) -> [SavedAudioRun] {
        guard let folder = try? directory(for: conversationID) else { return [] }
        return lock.withLock {
            if let cached = cache[conversationID] { return cached }
            let runs = (readLocked(folder)?.runs ?? [])
                .filter { run in
                    let file = folder.appendingPathComponent(run.fileName)
                    return (run.duration ?? 0) > 0 && fileManager.fileExists(atPath: file.path)
                }
                .sorted { ($0.index, $0.source == .you ? 0 : 1) < ($1.index, $1.source == .you ? 0 : 1) }
            cache[conversationID] = runs
            return runs
        }
    }

    public func url(for run: SavedAudioRun, conversationID: String) -> URL? {
        guard let folder = try? directory(for: conversationID), !run.fileName.contains("/") else { return nil }
        return folder.appendingPathComponent(run.fileName)
    }

    /// Update playback alignment together with the archive commit. If the archive rejects the
    /// replacement, restore the original manifest; never delete or rewrite the audio itself.
    public func commitRetranscription(conversationID: String, runs: [SavedAudioRun],
                                      commit: () throws -> Void) throws {
        let folder = try directory(for: conversationID)
        try lock.withLock {
            guard let original = readLocked(folder), !runs.isEmpty,
                  Set(original.runs.map(\.fileName)) == Set(runs.map(\.fileName)),
                  runs.allSatisfy({ fileManager.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try writeLocked(Manifest(runs: runs), to: folder)
            cache[conversationID] = nil
            do { try commit() }
            catch {
                try writeLocked(original, to: folder)
                cache[conversationID] = nil
                throw error
            }
        }
    }

    /// Every playable file of a conversation, for the share sheet.
    public func fileURLs(for conversationID: String) -> [URL] {
        runs(for: conversationID).compactMap { url(for: $0, conversationID: conversationID) }
    }

    public func hasAudio(_ conversationID: String) -> Bool { !runs(for: conversationID).isEmpty }

    /// Every conversation that has an audio folder.
    public func conversationIDs() -> [String] {
        lock.withLock { folderIDsLocked() }
    }

    /// Deletes a conversation's audio. Missing audio is not an error.
    public func delete(conversationID: String) throws {
        let folder = try directory(for: conversationID)
        try lock.withLock {
            cache[conversationID] = nil
            if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        }
    }

    /// Deletes every saved recording.
    public func deleteAll() throws {
        try lock.withLock {
            cache = [:]
            for item in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                try fileManager.removeItem(at: item)
            }
        }
    }

    /// Deletes the audio of conversations that are not in `keeping` (the readable history plus the one
    /// being recorded): a recording that never became a saved conversation, or one deleted while the
    /// app could not delete its audio. Returns how many conversations' audio went.
    @discardableResult
    public func deleteOrphans(keeping: Set<String>) -> Int {
        lock.withLock {
            var removed = 0
            for id in folderIDsLocked() where !keeping.contains(id) {
                cache[id] = nil
                if (try? fileManager.removeItem(at: root.appendingPathComponent(id, isDirectory: true))) != nil {
                    removed += 1
                }
            }
            return removed
        }
    }

    /// Runs the app never finished — it was killed while recording — get their real length from
    /// `duration` (the file is written in fragments, so what was written before the kill plays); a file
    /// it cannot read is deleted. `skipping` is the conversation being recorded. Returns the files changed.
    @discardableResult
    public func repairUnfinished(skipping: String? = nil, duration probe: (URL) -> TimeInterval?) -> Int {
        lock.withLock {
            var changed = 0
            for id in folderIDsLocked() where id != skipping {
                let folder = root.appendingPathComponent(id, isDirectory: true)
                guard var manifest = readLocked(folder),
                      manifest.runs.contains(where: { $0.duration == nil }) else { continue }
                for position in manifest.runs.indices.reversed() where manifest.runs[position].duration == nil {
                    let file = folder.appendingPathComponent(manifest.runs[position].fileName)
                    if fileManager.fileExists(atPath: file.path), let seconds = probe(file), seconds > 0 {
                        manifest.runs[position].duration = seconds
                    } else {
                        try? fileManager.removeItem(at: file)
                        manifest.runs.remove(at: position)
                    }
                    changed += 1
                }
                try? removeOrWriteLocked(manifest, folder: folder)
                cache[id] = nil
            }
            return changed
        }
    }

    public func bytes(for conversationID: String) -> Int64 {
        guard let folder = try? directory(for: conversationID) else { return 0 }
        return lock.withLock { size(of: folder) }
    }

    public func totalBytes() -> Int64 { lock.withLock { size(of: root) } }

    /// Deletes the runs recorded more than `retentionDays` days before `now`; 0 keeps everything. A
    /// folder whose `audio.json` is missing or unreadable is aged by its files' modification dates, so
    /// a damaged index never keeps audio past the retention. Returns how many files were deleted.
    @discardableResult
    public func deleteExpired(retentionDays: Int, now: Date = Date()) -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays) * 24 * 60 * 60)
        return lock.withLock {
            var removed = 0
            for id in folderIDsLocked() {
                let folder = root.appendingPathComponent(id, isDirectory: true)
                guard var manifest = readLocked(folder) else {
                    removed += deleteFilesLocked(in: folder, modifiedBefore: cutoff)
                    cache[id] = nil
                    continue
                }
                let expired = manifest.runs.filter { $0.startedAt < cutoff }
                guard !expired.isEmpty else { continue }
                for run in expired { try? fileManager.removeItem(at: folder.appendingPathComponent(run.fileName)) }
                removed += expired.count
                manifest.runs.removeAll { $0.startedAt < cutoff }
                try? removeOrWriteLocked(manifest, folder: folder)
                cache[id] = nil
            }
            return removed
        }
    }

    // MARK: Locked helpers

    private func folderIDsLocked() -> [String] {
        ((try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .map(\.lastPathComponent).filter(Self.isValidID)
    }

    /// `nil` when the index is missing or cannot be decoded.
    private func readLocked(_ folder: URL) -> Manifest? {
        let url = folder.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func writeLocked(_ manifest: Manifest, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(Self.manifestName),
                                           options: PrivateStorage.writingOptions)
    }

    /// A conversation left with no runs loses its folder too.
    private func removeOrWriteLocked(_ manifest: Manifest, folder: URL) throws {
        if manifest.runs.isEmpty {
            try fileManager.removeItem(at: folder)
        } else {
            try writeLocked(manifest, to: folder)
        }
    }

    /// Deletes the audio files older than `cutoff`, and the folder once no audio is left in it.
    private func deleteFilesLocked(in folder: URL, modifiedBefore cutoff: Date) -> Int {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        var removed = 0
        for file in files where file.pathExtension == SavedAudioPolicy.fileExtension {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff, (try? fileManager.removeItem(at: file)) != nil { removed += 1 }
        }
        let left = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        if !left.contains(where: { $0.pathExtension == SavedAudioPolicy.fileExtension }) {
            try? fileManager.removeItem(at: folder)
        }
        return removed
    }

    private func size(of folder: URL) -> Int64 {
        guard let items = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in items {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
