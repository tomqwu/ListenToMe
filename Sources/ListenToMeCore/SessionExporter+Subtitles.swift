import Foundation

/// One subtitle cue: a span of the recording, who spoke, and the words shown.
public struct SubtitleCue: Sendable, Equatable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speaker: String
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, speaker: String, text: String) {
        self.start = start; self.end = end; self.speaker = speaker; self.text = text
    }
}

/// SRT and WebVTT (issue #130). Only lines their engine timed become cues (`TranscriptTimestamp`); a
/// conversation without times yields an empty file, and the apps do not offer these formats for it.
extension SessionExporter {
    /// Readability limits, after common captioning guidance: at most two lines of 42 characters
    /// (16 for scripts written without spaces, such as Chinese or Japanese) and seven seconds a cue.
    static let maximumCueCharacters = 84
    static let maximumUnspacedCueCharacters = 32
    static let maximumLineCharacters = 42
    static let maximumUnspacedLineCharacters = 16
    static let maximumCueDuration: TimeInterval = 7
    /// Two short lines by the same speaker this close together are shown as one cue.
    static let mergeGap: TimeInterval = 1
    /// A line the engine timed with no length (start == end) is shown this long, or until the next cue.
    static let minimumCueDuration: TimeInterval = 1

    /// The cues for `segments`: timed lines in recording order, short neighbours by the same speaker
    /// merged, long lines split at word boundaries with their time shared by length.
    public static func cues(for segments: [TranscriptSegment]) -> [SubtitleCue] {
        let timed = segments.enumerated()
            .filter { TranscriptTimestamp.isTimed($0.element) && !MarkdownVault.singleLine($0.element.text).isEmpty }
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map { SubtitleCue(start: $0.element.start, end: max($0.element.start, $0.element.end),
                               speaker: MarkdownVault.singleLine($0.element.speakerLabel),
                               text: MarkdownVault.singleLine($0.element.text)) }
        var merged: [SubtitleCue] = []
        for cue in timed {
            let joiner = isUnspaced(merged.last?.text ?? "") && isUnspaced(cue.text) ? "" : " "
            if let last = merged.last, last.speaker == cue.speaker, cue.start - last.end <= mergeGap,
               (last.text + joiner + cue.text).count <= limit(for: last.text + joiner + cue.text),
               max(last.end, cue.end) - last.start <= maximumCueDuration {
                merged[merged.count - 1].text += joiner + cue.text
                merged[merged.count - 1].end = max(last.end, cue.end)
            } else {
                merged.append(cue)
            }
        }
        var cues = merged.flatMap(split)
        for index in cues.indices where cues[index].end - cues[index].start < minimumCueDuration / 2 {
            var end = cues[index].start + minimumCueDuration
            if index + 1 < cues.count, cues[index + 1].start > cues[index].start {
                end = min(end, cues[index + 1].start)
            }
            cues[index].end = max(cues[index].end, end)
        }
        return cues
    }

    /// SubRip: numbered cues, `HH:MM:SS,mmm` times, and the speaker's name in front of each cue when
    /// more than one person speaks.
    public static func srt(for record: SessionRecord) -> String {
        let cues = cues(for: record.segments ?? [])
        let named = Set(cues.map(\.speaker)).count > 1
        return cues.enumerated().map { index, cue in
            let text = (named ? "\(cue.speaker): " : "") + cue.text
            let body = wrap(text.replacingOccurrences(of: "-->", with: "->")).joined(separator: "\n")
            return "\(index + 1)\n\(TranscriptTimestamp.subtitle(cue.start, separator: ",")) --> "
                + "\(TranscriptTimestamp.subtitle(cue.end, separator: ","))\n\(body)\n"
        }.joined(separator: "\n")
    }

    /// WebVTT: `HH:MM:SS.mmm` times and a `<v Speaker>` voice tag on each cue when more than one person
    /// speaks. `&`, `<` and `>` are escaped, so the cue text can never close a tag or hold `-->`.
    public static func webVTT(for record: SessionRecord) -> String {
        let cues = cues(for: record.segments ?? [])
        let named = Set(cues.map(\.speaker)).count > 1
        let body = cues.map { cue in
            let lines = wrap(cue.text).map(escapeVTT).joined(separator: "\n")
            let voice = named ? "<v \(escapeVTT(cue.speaker))>" : ""
            return "\(TranscriptTimestamp.subtitle(cue.start, separator: ".")) --> "
                + "\(TranscriptTimestamp.subtitle(cue.end, separator: "."))\n\(voice)\(lines)\n"
        }
        return (["WEBVTT\n"] + body).joined(separator: "\n")
    }

    // MARK: Splitting and wrapping

    /// Text in a script written without spaces between words (Chinese, Japanese, Thai, Lao, Khmer,
    /// Burmese), which is split and wrapped at characters instead of words.
    static func isUnspaced(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        return text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF, 0x3040...0x30FF, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
            default: return false
            }
        }
    }

    private static func limit(for text: String) -> Int {
        isUnspaced(text) ? maximumUnspacedCueCharacters : maximumCueCharacters
    }

    /// A cue too long to read in one go becomes several, each given a share of its time by length.
    static func split(_ cue: SubtitleCue) -> [SubtitleCue] {
        let duration = cue.end - cue.start
        let byLength = Int((Double(cue.text.count) / Double(limit(for: cue.text))).rounded(.up))
        let byTime = Int((duration / maximumCueDuration).rounded(.up))
        let pieces = chunks(cue.text, into: max(1, byLength, byTime))
        guard pieces.count > 1 else { return [cue] }
        let total = Double(pieces.reduce(0) { $0 + $1.count })
        var start = cue.start, used = 0.0
        return pieces.enumerated().map { index, piece in
            used += Double(piece.count)
            let end = index == pieces.count - 1 ? cue.end : cue.start + duration * used / total
            defer { start = end }
            return SubtitleCue(start: start, end: end, speaker: cue.speaker, text: piece)
        }
    }

    /// Splits `text` into at most `count` pieces of similar length at word boundaries (at characters for
    /// unspaced scripts): each word goes to the piece its middle falls in.
    static func chunks(_ text: String, into count: Int) -> [String] {
        let unspaced = isUnspaced(text)
        let words = unspaced ? text.map(String.init) : text.split(separator: " ").map(String.init)
        guard count > 1, words.count > 1 else { return [text] }
        let separator = unspaced ? "" : " "
        let total = Double(text.count)
        var pieces: [[String]] = [], offset = 0.0, lastIndex = -1
        for word in words {
            let middle = offset + Double(word.count) / 2
            let index = min(count - 1, Int(middle / total * Double(count)))
            if index != lastIndex { pieces.append([]); lastIndex = index }
            pieces[pieces.count - 1].append(word)
            offset += Double(word.count + separator.count)
        }
        return pieces.map { $0.joined(separator: separator) }
    }

    /// One line, or two balanced lines split at the space nearest the middle; longer text wraps at the
    /// line limit.
    static func wrap(_ text: String) -> [String] {
        let unspaced = isUnspaced(text)
        let width = unspaced ? maximumUnspacedLineCharacters : maximumLineCharacters
        guard text.count > width else { return [text] }
        if unspaced {
            let characters = Array(text)
            let half = (characters.count + 1) / 2
            guard half > width else { return [String(characters[..<half]), String(characters[half...])] }
            return stride(from: 0, to: characters.count, by: width)
                .map { String(characters[$0..<min($0 + width, characters.count)]) }
        }
        let characters = Array(text)
        let spaces = characters.indices.filter { characters[$0] == " " }
        if let best = spaces.min(by: { abs($0 - characters.count / 2) < abs($1 - characters.count / 2) }),
           best <= width, characters.count - best - 1 <= width {
            return [String(characters[..<best]), String(characters[(best + 1)...])]
        }
        var lines: [String] = [], current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if !current.isEmpty, candidate.count > width {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func escapeVTT(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
