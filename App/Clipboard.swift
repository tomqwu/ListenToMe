import AppKit

enum Clipboard {
    /// Replaces the general pasteboard contents with `text`.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
