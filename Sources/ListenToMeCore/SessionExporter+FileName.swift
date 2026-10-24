import Foundation

extension SessionExporter {
    /// The longest title kept in a file name, in characters, so the whole name stays well under the
    /// 255-byte limit of APFS and most cloud folders even in a script that takes 3–4 bytes a character.
    static let maximumTitleLength = 60

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
        let name = [safeTitle(title), stamp, suffix.map(safeTitle)].compactMap { $0 }.joined(separator: " ")
        return name + "." + fileExtension
    }

    public static func fileName(for record: SessionRecord, format: SessionExportFormat,
                                timeZone: TimeZone = .current) -> String {
        fileName(title: record.title, date: record.date, fileExtension: format.fileExtension, timeZone: timeZone)
    }

    /// The title with path separators, characters Windows and FAT reject, control characters and line
    /// breaks replaced, runs of spaces collapsed, and leading dots or dashes dropped (no hidden files,
    /// nothing a shell reads as an option). Never empty.
    static func safeTitle(_ title: String) -> String {
        let generated = ConversationTitle.isGenerated(title) || title == "New conversation"
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
            .union(.newlines).union(.illegalCharacters)
        var cleaned = ""
        for scalar in (generated ? "" : title).unicodeScalars {
            cleaned.unicodeScalars.append(forbidden.contains(scalar) ? " " : scalar)
        }
        var words = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let first = words.first, first == "." || first == "-" || first == " " { words.removeFirst() }
        if words.count > maximumTitleLength {
            words = String(words.prefix(maximumTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        while let last = words.last, last == "." || last == " " { words.removeLast() }
        return words.isEmpty ? "Conversation" : words
    }
}
