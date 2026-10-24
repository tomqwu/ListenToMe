import Foundation

/// The transcription languages a conversation was actually recorded in (issue #206), kept on its
/// `SessionRecord` so Save to folder and exports describe the conversation itself rather than whatever
/// the language setting says today.
///
/// `current` is the language its latest recording was transcribed in, including an Automatic switch
/// (#197/#199); `all` lists every language it was transcribed in, in order of first use. Identifiers are
/// stored as BCP-47 tags (`en-US`), so `en_US` and `en-US` are the same language.
public struct ConversationLanguages: Sendable, Equatable {
    public private(set) var current: String?
    public private(set) var all: [String]

    public init(current: String? = nil, all: [String] = []) {
        self.current = current.flatMap(Self.normalized)
        var seen: [String] = []
        for identifier in all.compactMap(Self.normalized) + [self.current].compactMap({ $0 })
        where !seen.contains(identifier) {
            seen.append(identifier)
        }
        self.all = seen
    }

    public var isEmpty: Bool { all.isEmpty }

    /// A recording, or the part after a switch, is transcribed in `identifier`.
    public mutating func record(_ identifier: String) {
        guard let tag = Self.normalized(identifier) else { return }
        current = tag
        if !all.contains(tag) { all.append(tag) }
    }

    /// Every line that was in `old` is now in `new`: a first-check switch that transcribed the whole
    /// conversation again, or an Undo that brought the original lines back. `new` takes `old`'s place.
    public mutating func replace(_ old: String, with new: String) {
        guard let from = Self.normalized(old), let to = Self.normalized(new) else { return }
        guard from != to else { return record(to) }
        if let index = all.firstIndex(of: from) {
            if all.contains(to) { all.remove(at: index) } else { all[index] = to }
        } else if !all.contains(to) {
            all.append(to)
        }
        current = to
    }

    /// What happened to a conversation's language while it was open, kept by the app until the next
    /// save. Re-applying the same changes to the saved languages gives the same result, so every save
    /// can apply all of them to whatever was saved last.
    public enum Change: Sendable, Equatable {
        case recorded(String)
        case replaced(String, with: String)
    }

    public mutating func apply(_ change: Change) {
        switch change {
        case .recorded(let identifier): record(identifier)
        case .replaced(let old, let new): replace(old, with: new)
        }
    }

    public func applying(_ changes: [Change]) -> ConversationLanguages {
        var copy = self
        changes.forEach { copy.apply($0) }
        return copy
    }

    /// A BCP-47 tag, or nil for an empty identifier.
    public static func normalized(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tag = Locale(identifier: trimmed).identifier(.bcp47)
        return tag.isEmpty ? trimmed : tag
    }
}

public extension SessionRecord {
    /// The languages this record says it was transcribed in; empty for records saved before #206.
    var conversationLanguages: ConversationLanguages {
        ConversationLanguages(current: language, all: languages ?? [])
    }

    /// The same record with its languages replaced; `nil` fields when none are known.
    func with(languages value: ConversationLanguages) -> SessionRecord {
        SessionRecord(id: id, title: title, date: date, transcript: transcript, summary: summary,
                      segments: segments, notes: notes, quickSuggestion: quickSuggestion,
                      deepAnswer: deepAnswer, isComplete: isComplete, attachments: attachments,
                      sourceImportID: sourceImportID, language: value.current,
                      languages: value.isEmpty ? nil : value.all)
    }

    /// The same record, noting that new lines were transcribed in `identifier` (an Apple Watch file).
    func recording(language identifier: String) -> SessionRecord {
        var value = conversationLanguages
        value.record(identifier)
        return with(languages: value)
    }
}
