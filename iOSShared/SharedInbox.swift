import Foundation

struct SharedImport: Codable, Sendable {
    struct File: Codable, Sendable {
        let name: String
        let storedName: String
    }
    let id: String
    let text: String
    let files: [File]
}

enum SharedInbox {
    static let group = "group.com.tomwu.ListenToMe.ios"
    static func root() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "SharedInbox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Shared import storage is unavailable. Open ListenToMe and try again."])
        }
        let root = url.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
