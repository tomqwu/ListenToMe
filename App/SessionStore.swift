import Foundation
import Observation
import ListenToMeCore

@MainActor
@Observable
final class SessionStore {
    private let archive: SessionArchive?
    private(set) var errorText: String?

    init() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            let legacy = base.appendingPathComponent("ListenToMe/sessions.json")
            let folder = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "ListenToMe Dev" : "ListenToMe"
            archive = SessionArchive(directory: base.appendingPathComponent(folder + "/Conversations"), legacyURL: legacy,
                                     ownsLegacyFile: folder == "ListenToMe")
        } catch {
            archive = nil
            errorText = error.localizedDescription
        }
    }

    func all() -> [SessionRecord] {
        do {
            guard let archive else { throw CocoaError(.fileReadUnknown) }
            let records = try archive.all()
            errorText = nil
            return records
        } catch { errorText = "Couldn't read history: \(error.localizedDescription)"; return [] }
    }

    @discardableResult
    func add(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            try archive.save(record)
            errorText = nil
            return true
        } catch { errorText = "Couldn't save: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            try archive.clear()
            errorText = nil
            return true
        } catch { errorText = "Couldn't clear history: \(error.localizedDescription)"; return false }
    }
}
