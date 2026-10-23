import Foundation

/// Why a note could not be written. Every failure carries a sentence the app shows as-is; nothing
/// is dropped silently (issue #53).
public struct MarkdownVaultFailure: Error, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The bookmark no longer resolves, or the folder was moved, renamed or deleted.
        case folderMissing
        /// The system no longer lets the app write there (revoked access, read-only location).
        case accessDenied
        /// The note exists only as an iCloud placeholder; a download was requested.
        case iCloudPending
        case diskFull
        case other
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// True when retrying cannot help until the user picks the folder again.
    public var needsNewFolder: Bool { kind == .folderMissing || kind == .accessDenied }
}

public enum MarkdownVaultOutcome: Equatable, Sendable {
    case saved(fileName: String)
    /// The bytes on disk already match; nothing was written.
    case unchanged(fileName: String)
    case failed(MarkdownVaultFailure)
}

/// Writes notes into one user-chosen folder, identified by a bookmark so access survives relaunch
/// (on iOS the bookmark carries the document picker's security scope). An actor: writes happen off
/// the main thread, one at a time, and two saves of the same conversation never race.
public actor MarkdownVaultWriter {
    public typealias Write = @Sendable (Data, URL) throws -> Void

    /// The current bookmark. Replaced when the system reports the stored one as stale, so the app
    /// can persist the refreshed copy.
    public private(set) var bookmark: Data
    private let write: Write
    /// Bytes last written per conversation, so an unchanged note is not rewritten on every save.
    private var written: [String: (name: String, data: Data)] = [:]

    public init(bookmark: Data, write: @escaping Write = MarkdownVaultWriter.coordinatedWrite) {
        self.bookmark = bookmark
        self.write = write
    }

    /// A bookmark for a folder the user just picked. On iOS call it while the picked URL's
    /// security-scoped access is held.
    public static func makeBookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The folder's display name, or nil when the bookmark no longer resolves.
    public static func folderName(for bookmark: Data) -> String? {
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?
            .lastPathComponent
    }

    /// Creates or atomically replaces the conversation's note.
    public func save(_ note: MarkdownVaultNote) -> MarkdownVaultOutcome {
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                    bookmarkDataIsStale: &stale) else {
            return .failed(Self.missing(nil))
        }
        // `false` only means the URL needs no scope (macOS, unsandboxed); a real loss of access
        // surfaces as a permission error from the listing or the write below.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? Self.makeBookmark(for: folder) { bookmark = fresh }

        let names: [String]
        do {
            var isDirectory: ObjCBool = false
            // A bookmark follows a moved or renamed folder, including one moved to the Trash; notes
            // written there would be lost with the next Empty Trash.
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue, !folder.pathComponents.contains(".Trash")
            else { return .failed(Self.missing(folder.lastPathComponent)) }
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            return .failed(Self.failure(error, file: nil, folder: folder.lastPathComponent))
        }

        let marker = MarkdownVault.marker(for: note.id)
        // Legacy iCloud placeholders are hidden files named `.<name>.icloud`.
        if let placeholder = names.first(where: { $0.hasPrefix(".") && $0.hasSuffix(marker + ".icloud") }) {
            let name = String(placeholder.dropFirst().dropLast(".icloud".count))
            try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            return .failed(MarkdownVaultFailure(kind: .iCloudPending, message:
                "“\(name)” is still in iCloud and is downloading now. Tap Retry once it has downloaded."))
        }
        let name = names.filter { !$0.hasPrefix(".") && $0.hasSuffix(marker) }.min() ?? note.fileName
        let target = folder.appendingPathComponent(name)
        let data = Data(note.markdown.utf8)
        if let last = written[note.id], last.name == name, last.data == data,
           FileManager.default.fileExists(atPath: target.path) {
            return .unchanged(fileName: name)
        }
        do {
            try write(data, target)
        } catch {
            return .failed(Self.failure(error, file: name, folder: folder.lastPathComponent))
        }
        written[note.id] = (name, data)
        return .saved(fileName: name)
    }

    /// Atomic replace, coordinated so iCloud Drive and other file providers see one whole new version.
    public static let coordinatedWrite: Write = { data, url in
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
                                                         error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    static func missing(_ folder: String?) -> MarkdownVaultFailure {
        let name = folder.map { "“\($0)”" } ?? "The save folder"
        return MarkdownVaultFailure(kind: .folderMissing, message:
            "\(name) can't be found. It may have been moved, renamed or deleted. Choose the folder again.")
    }

    static func failure(_ error: Error, file: String?, folder: String) -> MarkdownVaultFailure {
        let what = file.map { "“\($0)”" } ?? "notes"
        let ns = error as NSError
        let posix = ns.domain == NSPOSIXErrorDomain ? Int32(ns.code)
            : (ns.userInfo[NSUnderlyingErrorKey] as? NSError)
                .flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
        let cocoa = ns.domain == NSCocoaErrorDomain ? CocoaError.Code(rawValue: ns.code) : nil
        if cocoa == .fileWriteOutOfSpace || posix == ENOSPC || posix == EDQUOT {
            return MarkdownVaultFailure(kind: .diskFull, message:
                "Not enough storage to save \(what) to “\(folder)”. Free up space, then tap Retry.")
        }
        if [.fileWriteNoPermission, .fileReadNoPermission, .fileWriteVolumeReadOnly].contains(cocoa)
            || [EACCES, EPERM, EROFS].contains(posix) {
            return MarkdownVaultFailure(kind: .accessDenied, message:
                "ListenToMe no longer has permission to save to “\(folder)”. Choose the folder again.")
        }
        if [.fileNoSuchFile, .fileReadNoSuchFile].contains(cocoa) || posix == ENOENT {
            return missing(folder)
        }
        return MarkdownVaultFailure(kind: .other, message:
            "Couldn't save \(what) to “\(folder)”: \(error.localizedDescription) Tap Retry.")
    }
}
