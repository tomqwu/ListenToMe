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

    /// Documents that made it into the prompt, plus the entries that did not (with a reason) so the
    /// UI can tell the user what the model will not see.
    struct Result: Sendable {
        var documents: [ReferenceBuilder.Document] = []
        var skipped: [TextFileReader.Skipped] = []
    }

    /// Loads documents from the given URLs: files are read directly; directories are walked for
    /// matching text files. Entries that cannot be read, are empty or are oversized are reported in
    /// `Result.skipped` instead of being dropped silently.
    static func load(_ urls: [URL]) -> Result {
        var result = Result()
        let fileManager = FileManager.default

        for url in urls {
            if result.documents.count >= maxFiles { break }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                result.skipped.append(.init(name: url.lastPathComponent, reason: "not found"))
                continue
            }

            if isDirectory.boolValue {
                let base = url.standardizedFileURL.path
                let enumerator = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let entry = enumerator?.nextObject() as? URL {
                    if result.documents.count >= maxFiles { break }
                    let values = try? entry.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    // Never follow symlinks while walking a folder — they can point outside the
                    // selected tree (e.g. at secrets) and that content would be sent to the model.
                    if values?.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
                    guard values?.isRegularFile == true else { continue }
                    // Inside a folder, files without a text extension are an expected non-match and
                    // are not reported; only readable-but-failed entries are.
                    switch read(entry, displayBase: base) {
                    case .success(let document): result.documents.append(document)
                    case .skipped(let skipped): result.skipped.append(skipped)
                    case .notText: break
                    }
                }
            } else {
                switch read(url, displayBase: nil) {
                case .success(let document): result.documents.append(document)
                case .skipped(let skipped): result.skipped.append(skipped)
                case .notText:
                    result.skipped.append(.init(name: url.lastPathComponent, reason: "unsupported file type"))
                }
            }
        }
        return result
    }

    enum ReadOutcome {
        case success(ReferenceBuilder.Document)
        case skipped(TextFileReader.Skipped)
        case notText
    }

    /// Reads a single file if it has a text extension and is within the size cap. `displayBase`,
    /// when set, makes the document name a path relative to the selected folder.
    private static func read(_ url: URL, displayBase: String?) -> ReadOutcome {
        guard textExtensions.contains(url.pathExtension.lowercased()) else { return .notText }
        let name: String
        if let base = displayBase, url.standardizedFileURL.path.hasPrefix(base) {
            name = String(url.standardizedFileURL.path.dropFirst(base.count).drop(while: { $0 == "/" }))
        } else {
            name = url.lastPathComponent
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return .skipped(.init(name: name, reason: "unreadable"))
        }
        guard size > 0 else { return .skipped(.init(name: name, reason: "empty")) }
        guard size <= maxFileBytes else { return .skipped(.init(name: name, reason: "larger than 200 KB")) }
        // RTF is converted to its text; other encodings fall back to detected/ISO Latin-1 instead of
        // being dropped for not being valid UTF-8.
        guard let content = try? TextFileReader.text(at: url), !content.isEmpty else {
            return .skipped(.init(name: name, reason: "unreadable text"))
        }
        return .success(ReferenceBuilder.Document(name: name, content: content))
    }
}
