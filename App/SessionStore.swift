import Foundation
import Observation
import ListenToMeCore

/// On-device persistence for finished sessions, enabling cross-meeting search. Stores
/// `[SessionRecord]` as JSON under Application Support. Synchronous and main-actor; the JSON is
/// small (capped to the most-recent 200 sessions). Missing or corrupt files are tolerated.
@MainActor
@Observable
final class SessionStore {
    /// Most-recent sessions to retain; older ones are dropped on `add`.
    static let cap = 200

    private let fileURL: URL?

    init() {
        let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("ListenToMe", isDirectory: true)
        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("sessions.json")
        } else {
            fileURL = nil
        }
    }

    /// All persisted sessions, newest first. Returns `[]` if the file is missing or unreadable.
    func all() -> [SessionRecord] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    /// Prepends `record` and caps the store to the most-recent `cap` sessions.
    func add(_ record: SessionRecord) {
        var records = all()
        records.insert(record, at: 0)
        if records.count > Self.cap { records = Array(records.prefix(Self.cap)) }
        write(records)
    }

    /// Removes all persisted sessions.
    func clear() {
        write([])
    }

    private func write(_ records: [SessionRecord]) {
        guard let fileURL, let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
