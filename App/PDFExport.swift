import AppKit

enum PDFExport {
    /// Renders Markdown text to a paginated US-Letter PDF via AppKit printing. The attributed
    /// string is laid out in an off-screen text view sized to the printable width, then
    /// `NSPrintOperation` paginates it across letter pages automatically. Returns nil on any
    /// parse/render failure.
    @MainActor
    static func data(fromMarkdown markdown: String, title: String) -> Data? {
        // Build the document block-by-block the same way the on-screen panes do: prose blocks get
        // heading/bullet preprocessing + inline markdown; fenced code blocks render verbatim in a
        // monospaced font (so diff/code lines aren't rewritten into bullets/headings).
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let attributed = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        for block in MarkdownText.blocks(markdown) {
            switch block {
            case .markdown(let prose):
                let prepared = MarkdownText.preprocess(prose)
                if let attr = try? NSAttributedString(AttributedString(markdown: prepared, options: options)) {
                    attributed.append(attr)
                } else {
                    attributed.append(NSAttributedString(string: prose))
                }
            case .code(let code):
                attributed.append(NSAttributedString(string: code, attributes: [.font: mono]))
            }
            attributed.append(NSAttributedString(string: "\n\n"))
        }
        guard attributed.length > 0 else { return nil }

        let pageWidth: CGFloat = 612, pageHeight: CGFloat = 792, margin: CGFloat = 48   // US Letter, 0.5in margins
        let textWidth = pageWidth - margin * 2
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 10))
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenToMe-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        let attributes = printInfo.dictionary()
        attributes[NSPrintInfo.AttributeKey.jobDisposition.rawValue] = NSPrintInfo.JobDisposition.save.rawValue
        attributes[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = tempURL

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { return nil }

        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try? Data(contentsOf: tempURL)
    }
}
