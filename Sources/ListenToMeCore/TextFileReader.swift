import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Reads a local text/rich-text file into plain text for prompt grounding.
///
/// `.rtf` is decoded to its text (never the `{\rtf1\ansi…}` markup, which would burn the reference
/// budget on control words). Other files try UTF-8 first, then the encoding the system detects, then
/// ISO Latin-1 — so a Windows-1252 or UTF-16 file from a colleague is included instead of silently
/// dropped. Everything stays on-device; nothing here reads anything but the given file.
public enum TextFileReader {
    /// A file that could not be included, with a short user-facing reason.
    public struct Skipped: Sendable, Equatable {
        public let name: String
        public let reason: String
        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public static func isRichText(_ url: URL) -> Bool {
        ["rtf", "rtfd"].contains(url.pathExtension.lowercased())
    }

    /// Plain text of the file, or throws when it cannot be read or decoded at all.
    public static func text(at url: URL) throws -> String {
        if isRichText(url), let rich = richText(at: url) { return rich }
        let data = try Data(contentsOf: url)
        if let decoded = decode(data) { return decoded }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Best-effort decoding of raw bytes: UTF-8, then detected encoding, then ISO Latin-1.
    public static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var detected: NSString?
        if NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &detected,
                                   usedLossyConversion: nil) != 0, let detected {
            return detected as String
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func richText(at url: URL) -> String? {
        #if canImport(AppKit) || canImport(UIKit)
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtfd" ? .rtfd : .rtf
        let attributed = try? NSAttributedString(url: url, options: [.documentType: type],
                                                 documentAttributes: nil)
        return attributed?.string
        #else
        return nil
        #endif
    }
}
