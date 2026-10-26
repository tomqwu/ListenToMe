import Foundation

/// Prepares block markers for a renderer that only supports inline Markdown.
public enum InlineMarkdownPreprocessor {
    public static func preprocess(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop(while: { $0 == " " })
            let indent = String(line.prefix(line.count - trimmed.count))
            // Markdown treats lines indented by 4+ spaces as code blocks; leave them verbatim so
            // code/diff lines aren't rewritten. (Costs the "•" on deeply-nested bullets — a fair
            // trade against corrupting code.)
            if indent.filter({ $0 == " " }).count >= 4 { return String(line) }
            // Headings ("# " … "###### ") -> bold the heading text.
            if let heading = trimmed.range(of: "^#{1,6}[ \t]+", options: .regularExpression) {
                let title = trimmed[heading.upperBound...].trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? indent : "\(indent)**\(title)**"
            }
            // Unordered bullets ("* ", "- ", "+ ") -> "• ". Requires whitespace after the marker so
            // "**bold**" (starts with "**", no space) is left alone for the inline parser.
            if let bullet = trimmed.range(of: "^[*\\-+][ \t]+", options: .regularExpression) {
                return "\(indent)•  \(trimmed[bullet.upperBound...])"
            }
            return String(line)
        }.joined(separator: "\n")
    }
}
