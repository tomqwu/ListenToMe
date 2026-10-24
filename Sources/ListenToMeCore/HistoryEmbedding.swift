import Foundation
import NaturalLanguage

/// A vector from one on-device model. Vectors are only comparable when their `model` tags match:
/// the tag names the language and the model revision that produced them.
public struct HistoryVector: Sendable, Equatable {
    public let model: String
    public let values: [Float]
    public init(model: String, values: [Float]) {
        self.model = model
        self.values = HistoryVector.normalized(values)
    }

    static func normalized(_ values: [Float]) -> [Float] {
        let norm = values.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? values.map { $0 / norm } : values
    }
}

/// Turns text into vectors on this device. Nothing here may contact a server.
public protocol HistoryEmbedder: Sendable {
    /// Names the embedding method. Changing it invalidates every stored vector.
    var signature: String { get }
    /// The vector for a passage, or nil when no on-device model covers the passage's language.
    func embed(_ text: String) -> HistoryVector?
    /// Vectors for a search query, one per stored model the query plausibly belongs to. Queries are
    /// short, so the language is chosen among the models the index already holds.
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector]
}

/// Apple NaturalLanguage embeddings, entirely on device. A passage's language is detected per
/// passage (conversations often mix languages); its vector is the mean of its nouns'
/// `NLEmbedding.wordEmbedding` vectors, or `NLEmbedding.sentenceEmbedding` where only a sentence
/// model exists. Only nouns count, minus words every meeting uses ("meeting", "team", "week"…):
/// verbs, auxiliaries and filler pulled every passage towards the same "talking about plans"
/// direction, so unrelated questions looked related. A passage with too few of them (small talk,
/// "can you hear me?") gets no vector. `NaturalLanguageEmbedderTests` holds the paraphrase set this
/// has to keep finding and the unrelated set it must not. Languages with neither model get no
/// vector, and their conversations stay reachable through keyword search.
public final class NaturalLanguageEmbedder: HistoryEmbedder, @unchecked Sendable {
    public let signature = "nl-noun-mean+sentence-v2"
    private let lock = NSLock()
    private var words: [NLLanguage: NLEmbedding?] = [:]
    private var sentences: [NLLanguage: NLEmbedding?] = [:]
    private static let contentClasses: Set<NLTag> = [.noun, .otherWord]
    /// A passage needs this many content words (or, for a sentence model, twice as many words).
    static let minimumPassageWords = 3
    /// English nouns too common in meetings to say what one is about.
    static let genericNouns: Set<String> = [
        "thing", "things", "time", "times", "way", "lot", "lots", "bit", "kind", "sort", "stuff", "point",
        "day", "days", "week", "weeks", "month", "months", "year", "years", "today", "tomorrow", "yesterday",
        "morning", "afternoon", "minute", "minutes", "hour", "hours", "people", "person", "everyone",
        "someone", "anyone", "everything", "something", "anything", "nothing", "guys", "guy", "team",
        "meeting", "meetings", "call", "project", "plan", "plans", "status", "update", "question", "idea",
        "yeah", "okay", "ok", "um", "uh", "hmm"
    ]

    public init() {}

    public func embed(_ text: String) -> HistoryVector? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return embed(text, language: language, minimumWords: Self.minimumPassageWords)
    }

    public func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        let languages = Set(models.compactMap(Self.language(of:)))
        guard !languages.isEmpty else { return [] }
        let chosen: [NLLanguage]
        if languages.count == 1 {
            chosen = Array(languages)
        } else {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = Array(languages)
            recognizer.processString(query)
            let hypotheses = recognizer.languageHypotheses(withMaximum: languages.count)
            let top = hypotheses.max { $0.value < $1.value }?.key
            chosen = hypotheses.filter { $0.value >= 0.25 || $0.key == top }.map(\.key)
        }
        return chosen.compactMap { embed(query, language: $0) }.filter { models.contains($0.model) }
    }

    /// The vector for `text` in `language`, or nil when that language has no model or `text` has
    /// fewer than `minimumWords` content words in its vocabulary (queries pass 1).
    public func embed(_ text: String, language: NLLanguage, minimumWords: Int = 1) -> HistoryVector? {
        if let model = wordModel(language) {
            return meanWordVector(text, language: language, model: model, minimumWords: minimumWords)
                .map { HistoryVector(model: "w:\(language.rawValue):\(model.revision)", values: $0) }
        }
        if let model = sentenceModel(language), wordCount(text) >= minimumWords * 2,
           let values = model.vector(for: text) {
            return HistoryVector(model: "s:\(language.rawValue):\(model.revision)", values: values.map(Float.init))
        }
        return nil
    }

    private func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }

    /// Whether this device has any embedding for `language`.
    public func supports(_ language: NLLanguage) -> Bool {
        wordModel(language) != nil || sentenceModel(language) != nil
    }

    static func language(of model: String) -> NLLanguage? {
        let parts = model.split(separator: ":")
        return parts.count == 3 ? NLLanguage(rawValue: String(parts[1])) : nil
    }

    private func meanWordVector(_ text: String, language: NLLanguage, model: NLEmbedding,
                                minimumWords: Int) -> [Float]? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            // Languages the tagger cannot classify yield nil tags: every word counts there.
            if let tag, !Self.contentClasses.contains(tag) { return true }
            let word = text[range].lowercased()
            if language == .english && Self.genericNouns.contains(word) { return true }
            if let vector = model.vector(for: word) {
                for index in vector.indices { sum[index] += vector[index] }
                count += 1
            }
            return true
        }
        return count < max(minimumWords, 1) ? nil : sum.map { Float($0 / Double(count)) }
    }

    private func wordModel(_ language: NLLanguage) -> NLEmbedding? {
        lock.lock(); defer { lock.unlock() }
        if let cached = words[language] { return cached }
        let model = NLEmbedding.wordEmbedding(for: language)
        words[language] = model
        return model
    }

    private func sentenceModel(_ language: NLLanguage) -> NLEmbedding? {
        lock.lock(); defer { lock.unlock() }
        if let cached = sentences[language] { return cached }
        let model = NLEmbedding.sentenceEmbedding(for: language)
        sentences[language] = model
        return model
    }
}
