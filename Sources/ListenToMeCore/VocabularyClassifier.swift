import Foundation
import NaturalLanguage

/// Scores how alike two texts are, from -1 to 1, or nil when no model is available. On device only.
public protocol TextSimilarityScoring: Sendable {
    func similarity(_ text: String, _ other: String) -> Double?
}

/// Apple's on-device English sentence embedding (NaturalLanguage). Nothing is downloaded or sent;
/// when the embedding is not on this device, `similarity` is nil and the classifier relies on terms.
public struct SentenceEmbeddingSimilarity: TextSimilarityScoring {
    public init() {}

    public func similarity(_ text: String, _ other: String) -> Double? {
        guard let embedding = Self.embedding,
              let left = embedding.vector(for: text), let right = embedding.vector(for: other) else { return nil }
        return Self.cosine(left, right)
    }

    nonisolated(unsafe) private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    static func cosine(_ left: [Double], _ right: [Double]) -> Double? {
        guard left.count == right.count, !left.isEmpty else { return nil }
        var dot = 0.0, leftNorm = 0.0, rightNorm = 0.0
        for (a, b) in zip(left, right) { dot += a * b; leftNorm += a * a; rightNorm += b * b }
        guard leftNorm > 0, rightNorm > 0 else { return nil }
        return dot / (leftNorm.squareRoot() * rightNorm.squareRoot())
    }
}

/// How strongly a transcript looks like one domain.
public struct VocabularyDomainScore: Sendable, Equatable {
    public let id: String
    /// Different preset terms heard.
    public let distinctTerms: Int
    /// Occurrences, each weighted by how few presets share the term.
    public let weightedHits: Double
    /// Weighted hits per 100 words.
    public let density: Double
}

/// Decides, on device and without any model call, whether a conversation sounds like one of the preset
/// domains (issue #222): term hits and their density first, then Apple's sentence embedding as a veto.
///
/// Thresholds are chosen to keep false positives low; a missed suggestion costs nothing, because the
/// user can turn a vocabulary on in Settings at any time:
/// - at least `minimumWords` words of final speech (about a minute);
/// - at least `minimumDistinctTerms` different terms of the domain, at `minimumDensity` weighted hits
///   per 100 words, and the domain must lead every other domain by `leadRatio`;
/// - the domain must rank in the top `embeddingRankWindow` by embedding similarity; with no embedding
///   available it needs `strictDistinctTerms` different terms instead.
public struct VocabularyClassifier: Sendable {
    public static let minimumWords = 150
    public static let minimumDistinctTerms = 4
    public static let strictDistinctTerms = 6
    public static let minimumDensity = 2.0
    public static let leadRatio = 1.5
    public static let embeddingRankWindow = 2
    /// Only the most recent speech is classified, so a long meeting stays cheap to check.
    public static let windowWords = 1_200

    private struct Index: Sendable {
        let id: String
        let profile: String
        /// Lowercased single words of four or more letters, and lowercased multi-word phrases.
        var phrases: [String: Double] = [:]
        /// Capitalized abbreviations, matched case-sensitively ("CBC", "EC2").
        var acronyms: [String: Double] = [:]
    }

    private let indexes: [Index]
    private let similarity: (any TextSimilarityScoring)?

    public init(catalog: VocabularyCatalog = .bundled,
                similarity: (any TextSimilarityScoring)? = SentenceEmbeddingSimilarity()) {
        self.similarity = similarity
        var owners: [String: Set<String>] = [:]
        let keyed = catalog.domains.map { domain in (domain, domain.terms.compactMap(Self.key)) }
        for (domain, keys) in keyed { for key in keys { owners[key.text, default: []].insert(domain.id) } }
        indexes = keyed.map { domain, keys in
            var index = Index(id: domain.id, profile: domain.description)
            for key in keys {
                // A term several presets share is weaker evidence for any one of them.
                let weight = 1 / Double(owners[key.text]?.count ?? 1)
                if key.acronym { index.acronyms[key.text] = weight } else { index.phrases[key.text] = weight }
            }
            return index
        }
    }

    private static func key(for term: String) -> (text: String, acronym: Bool)? {
        let tokens = VocabularyText.tokens(term)
        guard !tokens.isEmpty, tokens.count <= VocabularyCatalog.maximumTermWords + 1 else { return nil }
        if tokens.count == 1, VocabularyText.isAcronym(term) { return (tokens[0], true) }
        let text = tokens.joined(separator: " ").lowercased()
        // Short single words ("po", "ast", "som") collide with everyday speech.
        if tokens.count == 1, text.count < 4 { return nil }
        return (text, false)
    }

    /// Words of speech, counted the way the language's tokenizer splits them (so Chinese counts too).
    public static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in count += 1; return true }
        return count
    }

    public func scores(for text: String) -> [VocabularyDomainScore] {
        let tokens = Array(VocabularyText.tokens(text).suffix(Self.windowWords))
        let words = max(tokens.count, 1)
        let lower = tokens.map { $0.lowercased() }
        var grams: [String: Int] = [:]
        for length in 1...(VocabularyCatalog.maximumTermWords + 1) where length <= lower.count {
            for start in 0...(lower.count - length) {
                grams[lower[start..<(start + length)].joined(separator: " "), default: 0] += 1
            }
        }
        var capitals: [String: Int] = [:]
        for token in tokens where VocabularyText.isAcronym(token) { capitals[token, default: 0] += 1 }
        return indexes.map { index in
            var distinct = 0
            var weighted = 0.0
            for (phrase, weight) in index.phrases {
                if let count = grams[phrase] { distinct += 1; weighted += weight * Double(count) }
            }
            for (acronym, weight) in index.acronyms {
                if let count = capitals[acronym] { distinct += 1; weighted += weight * Double(count) }
            }
            return VocabularyDomainScore(id: index.id, distinctTerms: distinct, weightedHits: weighted,
                                         density: weighted * 100 / Double(words))
        }
    }

    /// Everyday speech the embedding ranking is measured against.
    static let neutralReference = "We talked about what to do this weekend, who is picking up the kids, " +
        "dinner plans and the weather."

    /// Every preset, most similar first: the sentence-embedding similarity of the recent speech to the
    /// preset's description, minus that of everyday small talk, so a description that is close to
    /// everything (Legal, in Apple's English embedding) does not always rank first. Nil when no
    /// embedding is on this device. The first call loads the embedding; run it off the main actor.
    public func embeddingRanking(for text: String) -> [String]? {
        guard let similarity else { return nil }
        let recent = VocabularyText.tokens(text).suffix(Self.windowWords).joined(separator: " ")
        var values: [(id: String, value: Double)] = []
        for index in indexes {
            guard let baseline = similarity.similarity(Self.neutralReference, index.profile),
                  let value = similarity.similarity(recent, index.profile) else { return nil }
            values.append((index.id, value - baseline))
        }
        return values.sorted { $0.value > $1.value }.map(\.id)
    }

    /// The domain to suggest for `text`, or nil. A domain in `excluding` (already on, already offered,
    /// or muted) is never returned, but it still competes: when it leads, nothing is suggested.
    public func suggestion(for text: String, excluding: Set<String> = []) -> String? {
        guard Self.wordCount(text) >= Self.minimumWords else { return nil }
        let ranked = scores(for: text).sorted { $0.weightedHits > $1.weightedHits }
        guard let best = ranked.first, !excluding.contains(best.id),
              best.distinctTerms >= Self.minimumDistinctTerms, best.density >= Self.minimumDensity else { return nil }
        if ranked.count > 1, best.weightedHits < ranked[1].weightedHits * Self.leadRatio { return nil }
        guard let order = embeddingRanking(for: text) else {
            return best.distinctTerms >= Self.strictDistinctTerms ? best.id : nil
        }
        return order.prefix(Self.embeddingRankWindow).contains(best.id) ? best.id : nil
    }
}

/// Per-conversation suggestion state: each preset is offered at most once per conversation, and the
/// classifier runs only once `VocabularyClassifier.minimumWords` of final speech have been heard, then
/// again after every `evaluationStep` more words.
public struct VocabularySuggestionTracker: Sendable, Equatable {
    public static let evaluationStep = 50

    public private(set) var conversationID: String
    /// Presets added for this conversation only.
    public private(set) var addedIDs: Set<String> = []
    public private(set) var offeredIDs: Set<String> = []
    /// Words of final speech heard in this conversation.
    public private(set) var heardWords = 0
    private var nextEvaluation = VocabularyClassifier.minimumWords

    public init(conversationID: String) { self.conversationID = conversationID }

    /// Starts over for another conversation; the same conversation keeps its state.
    public mutating func begin(conversationID: String) {
        guard conversationID != self.conversationID else { return }
        self = VocabularySuggestionTracker(conversationID: conversationID)
    }

    public mutating func markOffered(_ id: String) { offeredIDs.insert(id) }
    public mutating func add(_ id: String) { addedIDs.insert(id); offeredIDs.insert(id) }
    public mutating func remove(_ id: String) { addedIDs.remove(id) }

    /// Counts a newly finalized line of speech.
    public mutating func heard(_ speech: String) { heardWords += VocabularyClassifier.wordCount(speech) }

    /// When a check is due, the presets it must not suggest; nil when suggestions are off or not enough
    /// new speech has arrived. Each call that returns a set uses up that check.
    public mutating func dueCheck(settings: VocabularySettings) -> Set<String>? {
        guard settings.suggestionsEnabled, heardWords >= nextEvaluation else { return nil }
        nextEvaluation = heardWords + Self.evaluationStep
        return addedIDs.union(offeredIDs).union(settings.defaultDomainIDs).union(settings.mutedSuggestionIDs)
    }

    /// Counts `newSpeech`, and when a check is due classifies `recent` (the latest final speech). A
    /// returned preset is marked offered. Platforms run the classifier off the main actor instead,
    /// with `dueCheck` and `markOffered`.
    public mutating func evaluate(newSpeech: String, recent: String, settings: VocabularySettings,
                                  classifier: VocabularyClassifier) -> String? {
        heard(newSpeech)
        guard let excluded = dueCheck(settings: settings),
              let id = classifier.suggestion(for: recent, excluding: excluded) else { return nil }
        offeredIDs.insert(id)
        return id
    }
}
