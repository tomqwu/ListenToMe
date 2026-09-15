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
    /// Shared payloads are conversation content before they are imported, so they get the same
    /// protection class as the app's own files: unreadable until the device is unlocked once.
    static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    static var directoryAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    static func root() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "SharedInbox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Shared import storage is unavailable. Open ListenToMe and try again."])
        }
        let root = url.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: directoryAttributes)
        return root
    }
}
