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
        /// A note this conversation would use belongs to another note or conversation; it is
        /// never overwritten.
        case nameTaken
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

    /// True when the failure is about the folder, so every other note would fail the same way.
    /// A per-note failure (placeholder, name taken, a one-off error) lets the other notes go on.
    public var stopsQueue: Bool { needsNewFolder || kind == .diskFull }
}

public enum MarkdownVaultOutcome: Equatable, Sendable {
    case saved(fileName: String)
    /// The bytes on disk already match; nothing was written.
    case unchanged(fileName: String)
    case failed(MarkdownVaultFailure)
}

/// Writes notes into one user-chosen folder, identified by a bookmark so access survives relaunch
/// (using an app-scoped bookmark on macOS and the document picker's scope on iOS). An actor: writes happen off
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
        #if os(macOS)
        return try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static func resolve(_ bookmark: Data, stale: inout Bool) throws -> URL {
        #if os(macOS)
        if let scoped = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) { return scoped }
        // Existing DMG bookmarks predate sandboxing. Resolving one cannot grant new access:
        // the OS still denies an inaccessible folder, which save reports as a reselect failure.
        #endif
        return try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The folder's display name, or nil when the bookmark no longer resolves.
    public static func folderName(for bookmark: Data) -> String? {
        var stale = false
        return (try? resolve(bookmark, stale: &stale))?
            .lastPathComponent
    }

    /// Creates or atomically replaces the conversation's note.
    public func save(_ note: MarkdownVaultNote) -> MarkdownVaultOutcome {
        var stale = false
        guard let folder = try? Self.resolve(bookmark, stale: &stale) else {
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

        let name: String
        switch locate(note, in: folder, names: names) {
        case .success(let found): name = found
        case .failure(let failure): return .failed(failure)
        }
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

    /// The note's file name: an existing note of this conversation, else a new name that no other
    /// file holds. A file whose front matter names another conversation, or none, is never chosen,
    /// so a short-key collision or a user's own note with a matching name is left alone.
    private func locate(_ note: MarkdownVaultNote, in folder: URL,
                        names: [String]) -> Result<String, MarkdownVaultFailure> {
        let short = MarkdownVault.marker(for: note.id), long = MarkdownVault.longMarker(for: note.id)
        // Legacy iCloud placeholders are hidden files named `.<name>.icloud`.
        if let placeholder = names.first(where: {
            $0.hasPrefix(".") && ($0.hasSuffix(short + ".icloud") || $0.hasSuffix(long + ".icloud"))
        }) {
            let name = String(placeholder.dropFirst().dropLast(".icloud".count))
            try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            return .failure(MarkdownVaultFailure(kind: .iCloudPending, message:
                "“\(name)” is still in iCloud and is downloading now. Tap Retry once it has downloaded."))
        }
        let candidates = names.filter { !$0.hasPrefix(".") && ($0.hasSuffix(short) || $0.hasSuffix(long)) }.sorted()
        // A name this writer wrote for the conversation in this run is already known to be its own.
        if let known = written[note.id]?.name, candidates.contains(known) { return .success(known) }
        var shortTaken = false
        for name in candidates {
            let owner: String?
            do { owner = try Self.owner(of: folder.appendingPathComponent(name)) } catch {
                return .failure(Self.failure(error, file: name, folder: folder.lastPathComponent))
            }
            if owner == note.id { return .success(name) }
            if name.hasSuffix(short) { shortTaken = true; continue }
            return .failure(MarkdownVaultFailure(kind: .nameTaken, message:
                "“\(name)” in “\(folder.lastPathComponent)” is another note, so it was not replaced. "
                + "Rename or move that file, then tap Retry."))
        }
        return .success(shortTaken ? String(note.fileName.dropLast(short.count)) + long : note.fileName)
    }

    /// The `listentome_id` in the first few kilobytes of an existing note.
    static func owner(of url: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var head = try handle.read(upToCount: 4096) ?? Data()
        // Whole lines only, so a character cut at the 4 KB boundary cannot make the text invalid.
        if head.count == 4096, let lastNewline = head.lastIndex(of: UInt8(ascii: "\n")) {
            head = head.prefix(upTo: lastNewline)
        }
        return String(bytes: head, encoding: .utf8).flatMap(MarkdownVault.ownerID(in:))
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
