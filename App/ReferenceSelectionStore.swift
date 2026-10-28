import Foundation
import ListenToMeCore

/// Persists the Mac picker's scoped grants. A path by itself cannot restore a sandbox grant.
struct ReferenceSelectionStore {
    struct Restored {
        var urls: [URL] = []
        var skipped: [TextFileReader.Skipped] = []
    }
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func restore() -> Restored {
        var result = Restored()
        var bookmarks = defaults.dictionary(forKey: "referenceBookmarks") as? [String: Data] ?? [:]
        var refreshed = false
        for path in defaults.stringArray(forKey: "referencePaths") ?? [] {
            let legacy = URL(fileURLWithPath: path)
            guard let bookmark = bookmarks[path] else {
                // Preserve readable legacy DMG references. This cannot grant access in a sandbox.
                if FileManager.default.isReadableFile(atPath: path) { result.urls.append(legacy) }
                else { result.skipped.append(Self.reselect(legacy)) }
                continue
            }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else {
                result.skipped.append(Self.reselect(legacy))
                continue
            }
            result.urls.append(url)
            if stale {
                let acquired = url.startAccessingSecurityScopedResource()
                defer { if acquired { url.stopAccessingSecurityScopedResource() } }
                if let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarks[path] = fresh
                    refreshed = true
                }
            }
        }
        if refreshed { defaults.set(bookmarks, forKey: "referenceBookmarks") }
        return result
    }

    @discardableResult
    func save(_ urls: [URL]) -> [TextFileReader.Skipped] {
        var bookmarks: [String: Data] = [:]
        var skipped: [TextFileReader.Skipped] = []
        for url in urls {
            let acquired = url.startAccessingSecurityScopedResource()
            defer { if acquired { url.stopAccessingSecurityScopedResource() } }
            do {
                bookmarks[url.path] = try url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch { skipped.append(Self.reselect(url)) }
        }
        defaults.set(bookmarks, forKey: "referenceBookmarks")
        defaults.set(urls.map(\.path), forKey: "referencePaths")
        return skipped
    }

    private static func reselect(_ url: URL) -> TextFileReader.Skipped {
        .init(name: url.lastPathComponent, reason: "Access expired; choose file or folder again")
    }
}
