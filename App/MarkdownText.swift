import SwiftUI

/// Renders LLM markdown output with inline styling (bold, italic, inline code, bullets, headings)
/// while rendering fenced code blocks (``` … ```) verbatim in a monospaced box. Splitting code
/// blocks out before parsing keeps the inline-only Markdown parser from reflowing or corrupting
/// code, and tolerates the partial/malformed markdown that arrives mid-stream.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                        )
                case .markdown(let md):
                    Text(Self.inlineAttributed(md))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Block: Equatable {
        case markdown(String)
        case code(String)
    }

    /// Splits the raw output into markdown and fenced-code blocks. Fence delimiter lines
    /// (``` / ~~~, with any language tag) are dropped from display. An unterminated fence at the
    /// end (common mid-stream) is flushed as a code block so partial code still renders.
    static func blocks(_ raw: String) -> [Block] {
        var result: [Block] = []
        var mdLines: [Substring] = []
        var codeLines: [String] = []
        var inFence = false

        func flushMarkdown() {
            if !mdLines.isEmpty {
                result.append(.markdown(mdLines.joined(separator: "\n")))
                mdLines.removeAll()
            }
        }
        func flushCode() {
            result.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll()
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " })
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence { inFence = false; flushCode() } else { inFence = true; flushMarkdown() }
                continue
            }
            if inFence { codeLines.append(String(line)) } else { mdLines.append(line) }
        }
        if inFence { flushCode() } else { flushMarkdown() }
        return result
    }

    /// Parses a fence-free markdown block into a styled `AttributedString`, preserving line breaks.
    static func inlineAttributed(_ markdown: String) -> AttributedString {
        let preprocessed = preprocess(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: preprocessed, options: options) {
            return attr
        }
        return AttributedString(markdown)
    }

    /// `.inlineOnlyPreservingWhitespace` keeps newlines and parses inline emphasis, but leaves
    /// block syntax (headings, bullets) as literal characters. Convert those per line so the
    /// inline parser produces readable output: headings become bold, bullet markers become "•".
    /// Caller has already removed fenced code blocks; here we only guard indentation-based code.
    static func preprocess(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop(while: { $0 == " " })
            let indent = String(line.prefix(line.count - trimmed.count))
            // Markdown treats lines indented by 4+ spaces as code blocks; leave them verbatim so
            // code/diff lines aren't rewritten. (Costs the "•" on deeply-nested bullets — a fair
            // trade against corrupting code.)
            if indent.filter({ $0 == " " }).count >= 4 { return String(line) }
            // Headings ("# " … "###### ") -> bold the heading text.
            if let heading = trimmed.range(of: "^#{1,6}[ \t]+", options: .regularExpression) {
                return "\(indent)**\(trimmed[heading.upperBound...])**"
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
