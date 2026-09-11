import Foundation

/// One atomic file per conversation. Failures are surfaced, never interpreted as empty history.
/// Legacy history is copied once; the original is retained for rollback. Independent sessions do
/// not overwrite one shared JSON array. Callers serialize writes for the same conversation ID.
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

    public func all() throws -> [SessionRecord] {
        try prepare()
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    public func save(_ record: SessionRecord) throws {
        try prepare()
        try write(record)
    }

    public func clear() throws {
        try prepare()
        if ownsLegacyFile, let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            try fileManager.removeItem(at: url)
        }
    }

    public func delete(id: String) throws {
        try prepare()
        let url = try location(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func prepare() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("legacy-migrated")
        guard !fileManager.fileExists(atPath: marker.path) else { return }
        if let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            let legacy = try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: legacyURL))
            for record in legacy {
                let url = try location(record.id)
                if !fileManager.fileExists(atPath: url.path) { try write(record) }
            }
        }
        try Data().write(to: marker, options: .atomic)
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
        try data.write(to: url, options: [.atomic])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
