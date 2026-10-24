import Foundation
import NaturalLanguage

/// One preset domain vocabulary (issue #222): a short description for prompts, an optional summary
/// layout, and a curated term list the project writes itself. The first terms are the ones speech
/// engines mis-hear most, because only the first few reach the recognizer (`ActiveVocabulary`).
public struct VocabularyDomain: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// How the suggestion names the conversation: "Sounds like a {topic} conversation".
    public let topic: String?
    /// One sentence describing the kind of conversation, used in prompts.
    public let description: String
    /// A safety note shown wherever the vocabulary is offered (Medical: not a medical device).
    public let notice: String?
    /// Section headings a summary of this kind of conversation is organized under.
    public let summaryLayout: [String]
    public let terms: [String]
    /// Project-authored Simplified Chinese recognition terms and classifier profile (#238).
    public let simplifiedChinese: VocabularyTranslation?

    public init(id: String, name: String, topic: String? = nil, description: String, notice: String? = nil,
                summaryLayout: [String], terms: [String], simplifiedChinese: VocabularyTranslation? = nil) {
        self.id = id
        self.name = name
        self.topic = topic
        self.description = description
        self.notice = notice
        self.summaryLayout = summaryLayout
        self.terms = terms
        self.simplifiedChinese = simplifiedChinese
    }

    /// The banner's question: "Sounds like a medical conversation — add the Medical vocabulary?"
    public var suggestionText: String {
        let subject = topic ?? name.lowercased()
        let article = subject.first.map { "aeiou".contains($0.lowercased()) } == true ? "an" : "a"
        return "Sounds like \(article) \(subject) conversation — add the \(name) vocabulary?"
    }
}

/// A localized term list keeps the preset's stable ID, UI name, safety notice and summary layout.
public struct VocabularyTranslation: Codable, Sendable, Equatable {
    public let description: String
    public let terms: [String]

    public init(description: String, terms: [String]) {
        self.description = description
        self.terms = terms
    }
}

public enum VocabularyCatalogError: LocalizedError, Equatable {
    case missing(String)
    case invalid(String, [String])

    public var errorDescription: String? {
        switch self {
        case .missing(let id): return "The \(id) vocabulary is missing from this build."
        case .invalid(let id, let problems):
            return "The \(id) vocabulary is invalid: " + problems.joined(separator: "; ")
        }
    }
}

/// The bundled preset vocabularies, loaded from `Resources/Vocabularies/<id>.json`.
public struct VocabularyCatalog: Sendable, Equatable {
    /// Every preset, in the order Settings lists them.
    public static let presetIDs = ["medical", "legal", "software-cloud", "engineering", "finance", "sales",
                                   "education-research"]
    public static let minimumTerms = 150
    public static let maximumTerms = 500
    /// Apple asks for short contextual strings; longer phrases are less likely to be recognized.
    public static let maximumTermCharacters = 40
    public static let maximumTermWords = 4
    public static let maximumLayoutSections = 6

    public let domains: [VocabularyDomain]
    public let languageIdentifier: String

    public init(domains: [VocabularyDomain], languageIdentifier: String = "en") {
        self.domains = domains
        self.languageIdentifier = languageIdentifier
    }

    /// Chinese uses the Simplified list for zh / zh-CN / zh-SG / zh-Hans. Traditional Chinese and
    /// languages without a curated list retain the original English terms; My terms stays untouched.
    public func localized(for identifier: String) -> VocabularyCatalog {
        let language = Locale(identifier: identifier).language
        guard language.languageCode?.identifier == "zh", language.script?.identifier != "Hant" else { return self }
        return VocabularyCatalog(domains: domains.map { domain in
            guard let translated = domain.simplifiedChinese else { return domain }
            return VocabularyDomain(id: domain.id, name: domain.name, topic: domain.topic,
                                    description: translated.description, notice: domain.notice,
                                    summaryLayout: domain.summaryLayout, terms: translated.terms,
                                    simplifiedChinese: translated)
        }, languageIdentifier: "zh-Hans")
    }

    public func domain(id: String) -> VocabularyDomain? { domains.first { $0.id == id } }

    /// The presets shipped in this build. Loaded once; an unreadable file leaves that preset out, and
    /// the catalog tests make sure no shipped file is unreadable.
    public static let bundled: VocabularyCatalog = {
        VocabularyCatalog(domains: presetIDs.compactMap { try? load(id: $0) })
    }()

    /// Loads and validates every preset; throws on the first missing or invalid one.
    public static func loadAll(from bundle: Bundle? = nil) throws -> VocabularyCatalog {
        VocabularyCatalog(domains: try presetIDs.map { try load(id: $0, from: bundle) })
    }

    static func load(id: String, from source: Bundle? = nil) throws -> VocabularyDomain {
        let bundle = source ?? .module
        guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "Vocabularies")
            ?? bundle.url(forResource: id, withExtension: "json") else { throw VocabularyCatalogError.missing(id) }
        return try decode(Data(contentsOf: url), expectedID: id)
    }

    /// Decodes one preset and rejects it unless `problems(in:)` finds nothing.
    public static func decode(_ data: Data, expectedID: String? = nil) throws -> VocabularyDomain {
        let domain = try JSONDecoder().decode(VocabularyDomain.self, from: data)
        var problems = problems(in: domain)
        if let expectedID, domain.id != expectedID { problems.insert("id \(domain.id) is not \(expectedID)", at: 0) }
        guard problems.isEmpty else { throw VocabularyCatalogError.invalid(expectedID ?? domain.id, problems) }
        return domain
    }

    /// Everything wrong with a preset: missing text, too few or too many terms, terms too long for the
    /// recognizer, duplicates, or a summary layout with no sections.
    public static func problems(in domain: VocabularyDomain) -> [String] {
        var problems: [String] = []
        if domain.id.isEmpty || domain.name.isEmpty || domain.description.isEmpty {
            problems.append("id, name and description are required")
        }
        if !(minimumTerms...maximumTerms).contains(domain.terms.count) {
            problems.append("\(domain.terms.count) terms; expected \(minimumTerms)–\(maximumTerms)")
        }
        if domain.summaryLayout.isEmpty || domain.summaryLayout.count > maximumLayoutSections
            || domain.summaryLayout.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            problems.append("summary layout needs 1–\(maximumLayoutSections) named sections")
        }
        var seen = Set<String>()
        for term in domain.terms {
            if term.isEmpty || term != term.trimmingCharacters(in: .whitespacesAndNewlines) {
                problems.append("empty or padded term \"\(term)\"")
            } else if term.count > maximumTermCharacters || VocabularyText.words(in: term) > maximumTermWords {
                problems.append("term too long: \(term)")
            }
            if !seen.insert(term.lowercased()).inserted { problems.append("duplicate term: \(term)") }
        }
        if let translation = domain.simplifiedChinese { problems += Self.problems(in: translation) }
        return problems
    }

    private static func problems(in translation: VocabularyTranslation) -> [String] {
        var problems: [String] = []
        if translation.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("Simplified Chinese description is required")
        }
        // These focused lists start with 50+ terms per domain, rather than padding them with
        // translations that add no recognition value. The original English lists remain intact.
        if !(50...maximumTerms).contains(translation.terms.count) {
            problems.append("Simplified Chinese needs 50–\(maximumTerms) terms")
        }
        var translated = Set<String>()
        for term in translation.terms {
            if term.isEmpty || term != term.trimmingCharacters(in: .whitespacesAndNewlines)
                || term.count > maximumTermCharacters || VocabularyText.words(in: term) > maximumTermWords {
                problems.append("invalid Simplified Chinese term: \(term)")
            }
            if !translated.insert(term.lowercased()).inserted {
                problems.append("duplicate Simplified Chinese term: \(term)")
            }
        }
        return problems
    }
}

/// Text helpers shared by the vocabulary types.
public enum VocabularyText {
    /// Whitespace-separated words, the unit the term-length limits use.
    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Trims and collapses inner whitespace, so "  Kubernetes   cluster " is stored as one spelling.
    public static func normalizedTerm(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Classifier tokens: runs of letters, digits and `+ # &`, so "C++", "C#" and "P&L" survive while
    /// "Node.js", "p-value" and "Bloom's" split the same way in a term and in a transcript.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "+" || character == "#" || character == "&" {
                if let previous = current.last, containsHan(String(previous)) != containsHan(String(character)) {
                    tokens.append(current)
                    current = ""
                }
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    /// Words and names in a transcript line worth offering for My terms: capitalized runs ("Liu Yang",
    /// "Acme Cloud") first, then other words of four or more letters that are not common English, in
    /// the order spoken. Text without spaces (Chinese, Japanese) is split by the language's tokenizer.
    public static func candidates(in line: String, limit: Int = 12) -> [String] {
        let words = wordTokens(line)
        var result: [String] = []
        var seen = Set<String>()
        func offer(_ term: String) {
            guard result.count < limit, seen.insert(term.lowercased()).inserted else { return }
            result.append(term)
        }
        var run: [String] = []
        for word in words + [""] {
            if word.first?.isUppercase == true, !commonWords.contains(word.lowercased()) {
                run.append(word)
            } else {
                if run.count > 1 { offer(run.prefix(maximumRun).joined(separator: " ")) }
                run = []
            }
        }
        for word in words where word.count >= 4 || (word.count >= 2 && !word.unicodeScalars.allSatisfy(\.isASCII)) {
            if !commonWords.contains(word.lowercased()) { offer(word) }
        }
        return result
    }

    private static let maximumRun = 3

    private static func wordTokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
    }

    /// Frequent English words that are never worth a My terms entry.
    static let commonWords: Set<String> = [
        "about", "after", "again", "also", "because", "been", "before", "being", "could", "does", "doing", "done",
        "each", "even", "every", "from", "going", "good", "have", "here", "into", "just", "know", "like", "make",
        "maybe", "more", "most", "much", "need", "next", "only", "other", "over", "really", "right", "said", "same",
        "should", "some", "something", "still", "such", "sure", "take", "than", "thank", "thanks", "that", "their",
        "them", "then", "there", "these", "they", "thing", "things", "think", "this", "those", "through", "time",
        "today", "very", "want", "well", "were", "what", "when", "where", "which", "while", "will", "with", "would",
        "yeah", "your", "okay", "alright", "i", "i'm", "we", "you", "the", "and", "but", "so", "a", "an", "it"
    ]

    /// True for an all-capitals abbreviation such as "CBC", "EC2" or "GD&T". The classifier matches
    /// these only in capitals, so "bid" (an offer) never counts as BID (twice a day).
    static func isAcronym(_ term: String) -> Bool {
        let letters = term.filter(\.isLetter)
        return letters.count >= 2 && !term.contains(where: \.isWhitespace) && letters.allSatisfy(\.isUppercase)
    }
}
