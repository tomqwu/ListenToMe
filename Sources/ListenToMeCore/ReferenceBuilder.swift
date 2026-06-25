import Foundation

/// Formats attached reference documents (file/folder contents) into a single prompt block,
/// capped to a character budget so large attachments can't blow the model's context. Pure (no
/// I/O) so it is fully unit-testable; the app layer reads files and supplies `Document`s.
public enum ReferenceBuilder {
    public struct Document: Sendable, Equatable {
        public let name: String
        public let content: String
        public init(name: String, content: String) {
            self.name = name
            self.content = content
        }
    }

    /// Joins documents into one block, each headed by `### <name>`, stopping once `maxChars` is
    /// reached (the document that overflows is included truncated if a useful amount fits). Returns
    /// nil when there is no non-empty content. Appends a truncation notice when content was dropped.
    public static func build(documents: [Document], maxChars: Int = 16_000) -> String? {
        var blocks: [String] = []
        var used = 0
        var truncated = false

        for document in documents {
            let body = document.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let header = "### \(document.name)\n"
            let separator = blocks.isEmpty ? 0 : 2   // "\n\n" between blocks
            let full = header.count + body.count + separator

            if used + full <= maxChars {
                blocks.append(header + body)
                used += full
            } else {
                // Include a partial block if a meaningful slice of the body still fits.
                let budget = maxChars - used - separator - header.count
                if budget >= 200 {
                    blocks.append(header + String(body.prefix(budget)))
                }
                truncated = true
                break
            }
        }

        guard !blocks.isEmpty else { return nil }
        var result = blocks.joined(separator: "\n\n")
        if truncated { result += "\n\n[reference material truncated to fit the context budget]" }
        return result
    }
}
