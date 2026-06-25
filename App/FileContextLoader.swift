import Foundation
import ListenToMeCore

/// Reads attached files and folders into reference `Document`s for prompt grounding. Folders are
/// enumerated recursively; only text/code files within size/count caps are included. Runs off the
/// main actor (file I/O). The app is not sandboxed, so plain paths work without security bookmarks.
enum FileContextLoader {
    /// File extensions treated as readable text/code.
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rtf", "swift", "py", "js", "ts", "tsx", "jsx", "json", "yaml",
        "yml", "toml", "html", "htm", "css", "scss", "c", "cc", "cpp", "h", "hpp", "m", "mm",
        "java", "kt", "go", "rs", "rb", "php", "sh", "bash", "zsh", "sql", "xml", "csv", "tsv",
        "ini", "conf", "cfg", "log", "tex", "r", "scala", "dart", "lua", "pl"
    ]
    static let maxFileBytes = 200_000   // skip very large individual files
    static let maxFiles = 60            // bound total files read across all selections

    /// Loads documents from the given URLs: files are read directly; directories are walked for
    /// matching text files. Best-effort — unreadable or oversized entries are skipped.
    static func load(_ urls: [URL]) -> [ReferenceBuilder.Document] {
        var documents: [ReferenceBuilder.Document] = []
        let fileManager = FileManager.default

        for url in urls {
            if documents.count >= maxFiles { break }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let base = url.standardizedFileURL.path
                let enumerator = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let entry = enumerator?.nextObject() as? URL {
                    if documents.count >= maxFiles { break }
                    let values = try? entry.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    // Never follow symlinks while walking a folder — they can point outside the
                    // selected tree (e.g. at secrets) and that content would be sent to the model.
                    if values?.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
                    guard values?.isRegularFile == true else { continue }
                    if let document = read(entry, displayBase: base) { documents.append(document) }
                }
            } else if let document = read(url, displayBase: nil) {
                documents.append(document)
            }
        }
        return documents
    }

    /// Reads a single file if it has a text extension and is within the size cap. `displayBase`,
    /// when set, makes the document name a path relative to the selected folder.
    private static func read(_ url: URL, displayBase: String?) -> ReferenceBuilder.Document? {
        guard textExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > 0, size <= maxFileBytes else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let name: String
        if let base = displayBase, url.standardizedFileURL.path.hasPrefix(base) {
            name = String(url.standardizedFileURL.path.dropFirst(base.count).drop(while: { $0 == "/" }))
        } else {
            name = url.lastPathComponent
        }
        return ReferenceBuilder.Document(name: name, content: content)
    }
}
