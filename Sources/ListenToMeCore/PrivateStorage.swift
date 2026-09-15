import Foundation

/// How conversation and attachment bytes are written. Transcripts are the most private thing this
/// app holds, so on iOS every file is marked "complete until first user authentication": after a
/// reboot the files stay encrypted until the device has been unlocked once. macOS has no data
/// protection classes and keeps plain atomic writes.
public enum PrivateStorage {
    public static var writingOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }

    /// Directory attributes that give newly created files the same protection class by default.
    public static var directoryAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [:]
        #endif
    }

    public static func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: directoryAttributes)
    }

    /// Adds or removes the iCloud/iTunes backup exclusion flag. Missing paths are ignored: the flag
    /// is re-applied whenever the directory is created.
    public static func setExcludedFromBackup(_ excluded: Bool, at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var target = URL(fileURLWithPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try target.setResourceValues(values)
    }

    /// Read from disk, never from the URL's cache: a URL caches resource values it has read, and the
    /// flag is usually written through a different URL instance than the one asking about it.
    public static func isExcludedFromBackup(_ url: URL) -> Bool {
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        return (try? fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }
}
