import Foundation

/// The user's vocabulary choices (issue #222), stored on this device with the app's other settings and
/// therefore included in the device backup like them. Nothing here is sent anywhere.
public struct VocabularySettings: Codable, Sendable, Equatable {
    /// Presets on for every conversation ("Use by default").
    public var defaultDomainIDs: [String]
    /// The user's own list: people, products, company jargon. Any language.
    public var myTerms: [String]
    public var myTermsEnabled: Bool
    /// Whether the on-device suggestion banner may appear at all.
    public var suggestionsEnabled: Bool
    /// Presets the user said "Don't suggest … again" for.
    public var mutedSuggestionIDs: [String]
    /// Organize summaries under the active domain's headings (Medical: History / Findings / Plan).
    public var domainSummaryLayout: Bool

    public static let myTermsLimit = 300
    public static let termCharacterLimit = 60

    public init(defaultDomainIDs: [String] = [], myTerms: [String] = [], myTermsEnabled: Bool = true,
                suggestionsEnabled: Bool = true, mutedSuggestionIDs: [String] = [], domainSummaryLayout: Bool = true) {
        self.defaultDomainIDs = defaultDomainIDs
        self.myTerms = myTerms
        self.myTermsEnabled = myTermsEnabled
        self.suggestionsEnabled = suggestionsEnabled
        self.mutedSuggestionIDs = mutedSuggestionIDs
        self.domainSummaryLayout = domainSummaryLayout
    }

    /// Tolerant decoding: a field added in a later version never discards the user's list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = VocabularySettings()
        defaultDomainIDs = try container.decodeIfPresent([String].self, forKey: .defaultDomainIDs) ?? fallback.defaultDomainIDs
        myTerms = try container.decodeIfPresent([String].self, forKey: .myTerms) ?? fallback.myTerms
        myTermsEnabled = try container.decodeIfPresent(Bool.self, forKey: .myTermsEnabled) ?? fallback.myTermsEnabled
        suggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled)
            ?? fallback.suggestionsEnabled
        mutedSuggestionIDs = try container.decodeIfPresent([String].self, forKey: .mutedSuggestionIDs)
            ?? fallback.mutedSuggestionIDs
        domainSummaryLayout = try container.decodeIfPresent(Bool.self, forKey: .domainSummaryLayout)
            ?? fallback.domainSummaryLayout
    }

    public func isDefault(_ id: String) -> Bool { defaultDomainIDs.contains(id) }
    public func isMuted(_ id: String) -> Bool { mutedSuggestionIDs.contains(id) }

    public mutating func setDefault(_ id: String, _ enabled: Bool) {
        defaultDomainIDs.removeAll { $0 == id }
        if enabled { defaultDomainIDs.append(id) }
    }

    public mutating func setMuted(_ id: String, _ muted: Bool) {
        mutedSuggestionIDs.removeAll { $0 == id }
        if muted { mutedSuggestionIDs.append(id) }
    }

    /// Why `term` cannot be added, or nil when it can.
    public func rejection(of term: String, replacing index: Int? = nil) -> String? {
        let cleaned = VocabularyText.normalizedTerm(term)
        if cleaned.isEmpty { return "Enter a word or short phrase." }
        if cleaned.count > Self.termCharacterLimit { return "Keep terms under \(Self.termCharacterLimit) characters." }
        if myTerms.enumerated().contains(where: { $0.offset != index && $0.element.lowercased() == cleaned.lowercased() }) {
            return "“\(cleaned)” is already in My terms."
        }
        if index == nil, myTerms.count >= Self.myTermsLimit { return "My terms holds up to \(Self.myTermsLimit) terms." }
        return nil
    }

    /// Adds a term (trimmed, case-insensitively unique). Returns false, changing nothing, when rejected.
    @discardableResult
    public mutating func addTerm(_ term: String) -> Bool {
        guard rejection(of: term) == nil else { return false }
        myTerms.append(VocabularyText.normalizedTerm(term))
        return true
    }

    @discardableResult
    public mutating func replaceTerm(at index: Int, with term: String) -> Bool {
        guard myTerms.indices.contains(index), rejection(of: term, replacing: index) == nil else { return false }
        myTerms[index] = VocabularyText.normalizedTerm(term)
        return true
    }

    public mutating func removeTerm(_ term: String) {
        myTerms.removeAll { $0.lowercased() == term.lowercased() }
    }

    /// Plain-text import: one term per line; blank lines and lines starting with "#" are skipped.
    /// Returns how many new terms were added.
    @discardableResult
    public mutating func importTerms(from text: String) -> Int {
        Self.parse(text).reduce(0) { added, term in added + (addTerm(term) ? 1 : 0) }
    }

    /// Plain-text export, one term per line, readable back by `importTerms`.
    public var exportedText: String { myTerms.joined(separator: "\n") + (myTerms.isEmpty ? "" : "\n") }

    static func parse(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map(VocabularyText.normalizedTerm)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

/// Reads and writes `VocabularySettings` in `UserDefaults`, as JSON under one key.
public struct VocabularySettingsStore {
    public static let key = "vocabularySettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> VocabularySettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(VocabularySettings.self, from: data) else { return VocabularySettings() }
        return settings
    }

    public func save(_ settings: VocabularySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The vocabularies in effect for one conversation: presets on by default plus any the user added for
/// this conversation, and My terms.
public struct ActiveVocabulary: Sendable, Equatable {
    public let domains: [VocabularyDomain]
    public let myTerms: [String]
    /// Whether summaries should follow the first domain's layout.
    public let usesSummaryLayout: Bool

    /// Apple's guidance for `AnalysisContext.contextualStrings`: no more than 100 phrases in total.
    public static let recognitionLimit = 100
    /// When a preset is also on, My terms take at most this many of the recognizer's slots, so the
    /// preset still gets the rest. With no preset on, My terms may use all of them.
    public static let myTermsRecognitionShare = 60
    /// Phrases longer than this are left out of recognition; Apple says long phrases rarely help.
    public static let recognitionPhraseWords = 3

    public init(domains: [VocabularyDomain], myTerms: [String], usesSummaryLayout: Bool = true) {
        self.domains = domains
        self.myTerms = myTerms
        self.usesSummaryLayout = usesSummaryLayout
    }

    public init(settings: VocabularySettings, conversationDomainIDs: Set<String> = [],
                catalog: VocabularyCatalog = .bundled) {
        let wanted = Set(settings.defaultDomainIDs).union(conversationDomainIDs)
        self.init(domains: catalog.domains.filter { wanted.contains($0.id) },
                  myTerms: settings.myTermsEnabled ? settings.myTerms : [],
                  usesSummaryLayout: settings.domainSummaryLayout)
    }

    public var isEmpty: Bool { domains.isEmpty && myTerms.isEmpty }

    /// The domain whose layout a summary follows, when layouts are on.
    public var layoutDomain: VocabularyDomain? { usesSummaryLayout ? domains.first : nil }

    /// The contextual strings for the speech recognizer, capped at `limit`: My terms first (up to
    /// `myTermsRecognitionShare` when a preset is on), then each preset's terms in turn, in the
    /// preset's order. Case-insensitive duplicates and phrases longer than three words are skipped.
    public func recognitionTerms(limit: Int = recognitionLimit) -> [String] {
        var seen = Set<String>()
        func fits(_ term: String) -> Bool {
            VocabularyText.words(in: term) <= Self.recognitionPhraseWords
                && term.count <= VocabularyCatalog.maximumTermCharacters && seen.insert(term.lowercased()).inserted
        }
        let mine = myTerms.filter(fits)
        let share = domains.isEmpty ? limit : min(limit, Self.myTermsRecognitionShare)
        var result = Array(mine.prefix(share))
        let presetLists = domains.map { $0.terms.filter(fits) }
        var index = 0
        while result.count < limit, presetLists.contains(where: { index < $0.count }) {
            for list in presetLists where index < list.count && result.count < limit { result.append(list[index]) }
            index += 1
        }
        // My terms the share held back fill any slots the presets left.
        result += mine.dropFirst(share).prefix(max(0, limit - result.count))
        return result
    }
}
