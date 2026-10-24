import Foundation

extension SessionExporter {
    /// The longest title kept in a file name, in characters, for readability.
    static let maximumTitleLength = 60
    /// The longest whole file name, in UTF-8 bytes: APFS, ext4 and most cloud folders allow 255, and a
    /// title in a script of 3–4 bytes a character (or emoji of up to 25) would pass that within 60
    /// characters. The title is cut at a character (grapheme) boundary to fit.
    static let maximumNameBytes = 200

    /// `Weekly sync 2026-10-23 1435.srt`: the conversation's title, made safe for any file system, then
    /// its date, so three exports in one day no longer differ only by clock time. A generated or empty
    /// title becomes `Conversation`. `suffix` marks a variant, such as `recap`.
    public static func fileName(title: String, date: Date, fileExtension: String, suffix: String? = nil,
                                timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d%02d", parts.year ?? 0, parts.month ?? 0,
                           parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        let tail = ([stamp] + [suffix.map { safeTitle($0) }].compactMap { $0 }).joined(separator: " ")
            + "." + fileExtension
        let budget = max(16, maximumNameBytes - tail.utf8.count - 1)
        return safeTitle(title, maximumBytes: budget) + " " + tail
    }

    public static func fileName(for record: SessionRecord, format: SessionExportFormat,
                                timeZone: TimeZone = .current) -> String {
        fileName(title: record.title, date: record.date, fileExtension: format.fileExtension, timeZone: timeZone)
    }

    /// The title with path separators, characters Windows and FAT reject, control characters and line
    /// breaks replaced, runs of spaces collapsed, and leading dots or dashes dropped (no hidden files,
    /// nothing a shell reads as an option), cut to `maximumTitleLength` characters and `maximumBytes`
    /// UTF-8 bytes. Never empty.
    static func safeTitle(_ title: String, maximumBytes: Int = maximumNameBytes) -> String {
        let generated = ConversationTitle.isGenerated(title) || title == "New conversation"
        // Control characters (Cc) and bidirectional overrides go, but not other format characters: the
        // zero-width joiner holds emoji such as 👨‍👩‍👧 together.
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}"
                                     + "\u{2066}\u{2067}\u{2068}\u{2069}").union(.newlines).union(.illegalCharacters)
        var cleaned = ""
        for scalar in (generated ? "" : title).unicodeScalars {
            let drop = forbidden.contains(scalar) || scalar.properties.generalCategory == .control
            cleaned.unicodeScalars.append(drop ? " " : scalar)
        }
        var words = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let first = words.first, first == "." || first == "-" || first == " " { words.removeFirst() }
        if words.count > maximumTitleLength { words = String(words.prefix(maximumTitleLength)) }
        while words.utf8.count > maximumBytes { words.removeLast() }   // whole characters only
        while let last = words.last, last == "." || last == " " { words.removeLast() }
        return words.isEmpty ? "Conversation" : words
    }
}
