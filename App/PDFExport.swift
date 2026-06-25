import AppKit

enum PDFExport {
    /// Renders Markdown text to single-document PDF data via an attributed string in an off-screen
    /// text view. Returns nil if the markdown can't be parsed.
    @MainActor
    static func data(fromMarkdown markdown: String, title: String) -> Data? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let attributed = try? NSAttributedString(
            AttributedString(markdown: markdown, options: options)) else { return nil }
        let pageWidth: CGFloat = 612, margin: CGFloat = 48   // US Letter, 0.5in margins
        let textWidth = pageWidth - margin * 2
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 10))
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()
        let contentHeight = textView.frame.height
        let container = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: contentHeight + margin * 2))
        textView.frame = NSRect(x: margin, y: margin, width: textWidth, height: contentHeight)
        container.addSubview(textView)
        return container.dataWithPDF(inside: container.bounds)
    }
}
