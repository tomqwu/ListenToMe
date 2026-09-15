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

    /// Plain text of the file, or throws when it cannot be read or decoded as text.
    public static func text(at url: URL) throws -> String {
        // An `.rtf` whose markup does not parse is not silently handed on as `{\rtf1…}` control
        // words — that is exactly the prompt pollution this reader exists to prevent.
        if isRichText(url) {
            guard let rich = try richText(at: url) else { throw CocoaError(.fileReadCorruptFile) }
            return rich
        }
        let data = try Data(contentsOf: url)
        if let decoded = decode(data) { return decoded }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Best-effort decoding of raw bytes: UTF-8, then the detected encoding, then ISO Latin-1 —
    /// but only for bytes that actually look like text. ISO Latin-1 maps every possible byte, so
    /// without the check below a renamed binary would be "read" as mojibake and fed to the model.
    public static func decode(_ data: Data) -> String? {
        // The binary check runs first: ISO Latin-1 (and often the detector) maps every byte, so a
        // renamed screenshot would otherwise "decode" into mojibake. UTF-16/32 text is full of NUL
        // bytes by design, so a Unicode BOM exempts the file from the check.
        guard hasUnicodeBOM(data) || looksLikeText(data) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var detected: NSString?
        if NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &detected,
                                   usedLossyConversion: nil) != 0, let detected {
            return detected as String
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Rejects binary content: any NUL byte, or more than 2% C0 control bytes other than tab, LF,
    /// CR and form feed, in the first 8 KB.
    static func looksLikeText(_ data: Data) -> Bool {
        let sample = data.prefix(8_192)
        guard !sample.isEmpty else { return true }
        var controls = 0
        for byte in sample {
            if byte == 0x00 { return false }
            if byte < 0x20, byte != 0x09, byte != 0x0A, byte != 0x0D, byte != 0x0C { controls += 1 }
        }
        return controls * 50 <= sample.count
    }

    static func hasUnicodeBOM(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(4))
        let boms: [[UInt8]] = [[0xEF, 0xBB, 0xBF], [0xFF, 0xFE], [0xFE, 0xFF],
                               [0xFF, 0xFE, 0x00, 0x00], [0x00, 0x00, 0xFE, 0xFF]]
        return boms.contains { head.count >= $0.count && Array(head.prefix($0.count)) == $0 }
    }

    /// `NSAttributedString`'s RTF importer is a pure parser (unlike the HTML one, which drives
    /// WebKit and must run on the main thread), so calling it from the loader's detached task is
    /// safe. Returns nil when the file is not rich text this platform can parse.
    private static func richText(at url: URL) throws -> String? {
        #if canImport(AppKit) || canImport(UIKit)
        if url.pathExtension.lowercased() == "rtfd" {   // a bundle, so it has to be read by URL
            return (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                            documentAttributes: nil))?.string
        }
        let data = try Data(contentsOf: url)   // a missing/unreadable file throws, as for plain text
        let attributed = try? NSAttributedString(data: data,
                                                 options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil)
        return attributed?.string
        #else
        return nil
        #endif
    }
}
