import Foundation

/// The outcome of reading the archive: everything that could be decoded, plus a one-line warning
/// when something had to be set aside. A damaged file never hides the readable conversations.
public struct SessionArchiveResult: Sendable, Equatable {
    public let records: [SessionRecord]
    /// Human-readable, single line; `nil` when the whole archive read cleanly.
    public let warning: String?

    public init(records: [SessionRecord], warning: String? = nil) {
        self.records = records
        self.warning = warning
    }
}

/// One atomic file per conversation. Failures are surfaced, never interpreted as empty history.
/// Legacy history is copied once; the original is retained for rollback. Independent sessions do
/// not overwrite one shared JSON array. Callers serialize writes for the same conversation ID.
///
/// Damaged input is quarantined, never deleted: an undecodable `<id>.json` (or an undecodable
/// legacy `sessions.json`) is renamed to `<name>.corrupt-<timestamp>` so the remaining history
/// stays readable and saving/clearing keeps working.
public final class SessionArchive {
    private let directory: URL
    private let legacyURL: URL?
    private let ownsLegacyFile: Bool
    private let fileManager = FileManager.default

    public init(directory: URL, legacyURL: URL? = nil, ownsLegacyFile: Bool = false) {
        self.directory = directory
        self.legacyURL = legacyURL
        self.ownsLegacyFile = ownsLegacyFile
    }

    /// Every readable conversation, newest first, plus a warning about anything set aside.
    public func read() throws -> SessionArchiveResult {
        let migrationWarning = try prepare()
        var records: [SessionRecord] = []
        var quarantined: [String] = []
        var skipped = 0
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            where url.pathExtension == "json" {
            do {
                records.append(try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: url)))
            } catch {
                // Only ever rename a regular file; anything else is reported but left untouched.
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true, let moved = quarantine(url) {
                    quarantined.append("\(url.lastPathComponent) → \(moved.lastPathComponent)")
                } else {
                    skipped += 1
                }
            }
        }
        records.sort { $0.date > $1.date }

        var parts: [String] = []
        if let migrationWarning { parts.append(migrationWarning) }
        if !quarantined.isEmpty {
            let shown = quarantined.prefix(3).joined(separator: ", ")
            let extra = quarantined.count > 3 ? " +\(quarantined.count - 3) more" : ""
            parts.append("\(quarantined.count) unreadable history file(s) were set aside and skipped: \(shown)\(extra).")
        }
        if skipped > 0 { parts.append("\(skipped) history item(s) could not be read or set aside.") }
        return SessionArchiveResult(records: records, warning: parts.isEmpty ? nil : parts.joined(separator: " "))
    }

    /// Readable conversations only. Prefer `read()` when the caller can surface the warning.
    public func all() throws -> [SessionRecord] { try read().records }

    /// Saves one conversation. Returns a one-line warning when a legacy file had to be set aside.
    @discardableResult
    public func save(_ record: SessionRecord) throws -> String? {
        let warning = try prepare()
        try write(record)
        return warning
    }

    @discardableResult
    public func clear() throws -> String? {
        let warning = try prepare()
        if ownsLegacyFile, let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == "json" || url.lastPathComponent.contains(".json.corrupt-") {
            try fileManager.removeItem(at: url)
        }
        return warning
    }

    @discardableResult
    public func delete(id: String) throws -> String? {
        let warning = try prepare()
        let url = try location(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        return warning
    }

    /// Creates the directory and performs the one-time legacy migration. Migration failure never
    /// blocks saving, clearing or reading: the undecodable file is set aside, the marker is written
    /// so the attempt is not repeated, and a one-line warning is returned (once).
    private func prepare() throws -> String? {
        try PrivateStorage.createDirectory(at: directory)
        let marker = directory.appendingPathComponent("legacy-migrated")
        guard !fileManager.fileExists(atPath: marker.path) else { return nil }
        var warning: String?
        if let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            let legacy: [SessionRecord]?
            do {
                legacy = try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: legacyURL))
            } catch {
                legacy = nil
                let moved = quarantine(legacyURL)
                warning = "Couldn't read the older history file \(legacyURL.lastPathComponent); it was set aside"
                    + (moved.map { " as \($0.lastPathComponent)" } ?? "")
                    + " and the rest of your history is unaffected."
            }
            if let legacy {
                do {
                    for record in legacy {
                        let url = try location(record.id)
                        if !fileManager.fileExists(atPath: url.path) { try write(record) }
                    }
                } catch {
                    // The legacy file is fine but copying failed (disk full, permissions). Leave the
                    // marker unwritten so migration retries later, and don't block this operation.
                    return "Couldn't copy older conversations yet: \(error.localizedDescription)"
                }
            }
        }
        try? Data().write(to: marker, options: PrivateStorage.writingOptions)
        return warning
    }

    /// Renames a damaged file out of the way. Never deletes; returns the new location when moved.
    private func quarantine(_ url: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let base = url.deletingLastPathComponent()
        for attempt in 0..<20 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let target = base.appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)\(suffix)")
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do { try fileManager.moveItem(at: url, to: target); return target } catch { return nil }
        }
        return nil
    }

    private func location(_ id: String) throws -> URL {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return directory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func write(_ record: SessionRecord) throws {
        let url = try location(record.id)
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: PrivateStorage.writingOptions)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
