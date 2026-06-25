import AppKit

enum PDFExport {
    /// Renders Markdown text to a paginated US-Letter PDF via AppKit printing. The attributed
    /// string is laid out in an off-screen text view sized to the printable width, then
    /// `NSPrintOperation` paginates it across letter pages automatically. Returns nil on any
    /// parse/render failure.
    @MainActor
    static func data(fromMarkdown markdown: String, title: String) -> Data? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let attributed = try? NSAttributedString(
            AttributedString(markdown: markdown, options: options)) else { return nil }

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
