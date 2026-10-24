import Foundation

/// One preset domain vocabulary (issue #222): a short description for prompts, an optional summary
/// layout, and a curated term list the project writes itself. The first terms are the ones speech
/// engines mis-hear most, because only the first few reach the recognizer (`ActiveVocabulary`).
public struct VocabularyDomain: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// One sentence describing the kind of conversation, used in prompts.
    public let description: String
    /// A safety note shown wherever the vocabulary is offered (Medical: not a medical device).
    public let notice: String?
    /// Section headings a summary of this kind of conversation is organized under.
    public let summaryLayout: [String]
    public let terms: [String]

    public init(id: String, name: String, description: String, notice: String? = nil,
                summaryLayout: [String], terms: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.notice = notice
        self.summaryLayout = summaryLayout
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

    public init(domains: [VocabularyDomain]) { self.domains = domains }

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
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// True for an all-capitals abbreviation such as "CBC", "EC2" or "GD&T". The classifier matches
    /// these only in capitals, so "bid" (an offer) never counts as BID (twice a day).
    static func isAcronym(_ term: String) -> Bool {
        let letters = term.filter(\.isLetter)
        return letters.count >= 2 && !term.contains(where: \.isWhitespace) && letters.allSatisfy(\.isUppercase)
    }
}
