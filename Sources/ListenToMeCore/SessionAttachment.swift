import Foundation

public struct SessionAttachment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let storedName: String
    public let byteCount: Int

    public init(id: String, name: String, storedName: String, byteCount: Int) {
        self.id = id; self.name = name; self.storedName = storedName; self.byteCount = byteCount
    }
}

/// Original attachments stay on disk, outside the frequently updated conversation JSON.
public struct SessionAttachmentStore {
    public static let maximumBytes = 20 * 1024 * 1024
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func add(data: Data, name: String) throws -> SessionAttachment {
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let id = UUID().uuidString
        let cleanName = URL(fileURLWithPath: name).lastPathComponent
        let ext = URL(fileURLWithPath: cleanName).pathExtension
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12)
        let storedName = id + (ext.isEmpty ? "" : "." + ext)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(storedName), options: .atomic)
        return SessionAttachment(id: id, name: cleanName, storedName: storedName, byteCount: data.count)
    }

    public func url(for attachment: SessionAttachment) throws -> URL {
        guard !attachment.storedName.isEmpty, attachment.storedName != ".", attachment.storedName != "..",
              !attachment.storedName.contains("/"), !attachment.storedName.contains("\\") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appendingPathComponent(attachment.storedName)
    }

    public func remove(_ attachment: SessionAttachment) throws {
        let file = try url(for: attachment)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
