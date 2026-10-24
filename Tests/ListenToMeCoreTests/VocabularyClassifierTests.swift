import NaturalLanguage
import XCTest
@testable import ListenToMeCore

/// The on-device suggestion classifier and its once-per-conversation tracker (issue #222).
final class VocabularyClassifierTests: XCTestCase {
    /// Ranks presets by a fixed order, so a test decides what the "embedding" prefers.
    private struct RankedSimilarity: TextSimilarityScoring {
        let preferred: [String]
        func similarity(_ text: String, _ other: String) -> Double? {
            guard text != VocabularyClassifier.neutralReference else { return 0 }
            let id = VocabularyCatalog.bundled.domains.first { $0.description == other }?.id ?? ""
            return Double(preferred.count - (preferred.firstIndex(of: id) ?? preferred.count))
        }
    }

    private struct NoSimilarity: TextSimilarityScoring {
        func similarity(_ text: String, _ other: String) -> Double? { nil }
    }

    private let termsOnly = VocabularyClassifier(similarity: nil)

    func testEveryPresetFixtureIsRecognizedFromItsTerms() {
        for (id, text) in VocabularyFixtures.positives {
            XCTAssertGreaterThanOrEqual(VocabularyClassifier.wordCount(text), VocabularyClassifier.minimumWords, id)
            XCTAssertEqual(termsOnly.suggestion(for: text), id, id)
            let best = termsOnly.scores(for: text).max { $0.weightedHits < $1.weightedHits }
            XCTAssertEqual(best?.id, id)
            XCTAssertGreaterThanOrEqual(best?.distinctTerms ?? 0, VocabularyClassifier.strictDistinctTerms, id)
        }
    }

    func testEverydayConversationsAndOrdinaryMeetingsAreNeverSuggested() {
        for (index, text) in VocabularyFixtures.negatives.enumerated() {
            XCTAssertNil(termsOnly.suggestion(for: text), "negative \(index)")
            XCTAssertNil(VocabularyClassifier(similarity: RankedSimilarity(preferred: VocabularyCatalog.presetIDs))
                .suggestion(for: text), "negative \(index)")
            let strongest = termsOnly.scores(for: text).map(\.distinctTerms).max() ?? 0
            XCTAssertLessThan(strongest, VocabularyClassifier.minimumDistinctTerms, "negative \(index)")
        }
    }

    /// The real on-device embedding, calibrated against the fixtures. Skipped where the English
    /// sentence embedding is not installed.
    func testAppleSentenceEmbeddingAgreesWithTheFixtures() throws {
        try XCTSkipIf(NLEmbedding.sentenceEmbedding(for: .english) == nil, "No English sentence embedding on this Mac")
        let classifier = VocabularyClassifier()
        for (id, text) in VocabularyFixtures.positives {
            XCTAssertEqual(classifier.suggestion(for: text), id, id)
            XCTAssertTrue(classifier.embeddingRanking(for: text)?.prefix(2).contains(id) == true, id)
        }
        for text in VocabularyFixtures.negatives { XCTAssertNil(classifier.suggestion(for: text)) }
        XCTAssertNotNil(SentenceEmbeddingSimilarity().similarity("a", "b"))
    }

    func testTheEmbeddingVetoesADomainItDoesNotRankNearTheTop() throws {
        let text = try XCTUnwrap(VocabularyFixtures.positives["medical"])
        let agrees = VocabularyClassifier(similarity: RankedSimilarity(preferred: ["legal", "medical"]))
        XCTAssertEqual(agrees.suggestion(for: text), "medical")
        XCTAssertEqual(agrees.embeddingRanking(for: text)?.prefix(2), ["legal", "medical"])
        let disagrees = VocabularyClassifier(similarity: RankedSimilarity(preferred: ["legal", "sales", "medical"]))
        XCTAssertNil(disagrees.suggestion(for: text))
    }

    func testWithoutAnEmbeddingMoreDistinctTermsAreRequired() {
        let unavailable = VocabularyClassifier(similarity: NoSimilarity())
        XCTAssertNil(unavailable.embeddingRanking(for: "anything"))
        let five = "we reviewed apixaban metoprolol furosemide troponin and echocardiogram results today. "
        let text = five + String(repeating: "and then we talked about the weekend plans and lunch. ", count: 3)
        // Five distinct terms in ~45 words: dense enough, but short of six without the embedding's support.
        let padded = text + String(repeating: text, count: 3)
        XCTAssertEqual(termsOnly.scores(for: padded).first { $0.id == "medical" }?.distinctTerms, 5)
        XCTAssertNil(unavailable.suggestion(for: padded))
        XCTAssertEqual(VocabularyClassifier(similarity: RankedSimilarity(preferred: ["medical"])).suggestion(for: padded),
                       "medical")
    }

    func testShortSpeechIsNotClassified() {
        let short = "metoprolol apixaban furosemide troponin echocardiogram dyspnea crackles creatinine"
        XCTAssertNil(termsOnly.suggestion(for: short))
    }

    func testAnExcludedLeaderBlocksOtherSuggestions() throws {
        let text = try XCTUnwrap(VocabularyFixtures.positives["finance"])
        XCTAssertNil(termsOnly.suggestion(for: text, excluding: ["finance"]))
    }

    func testTwoEqualDomainsAreTooAmbiguousToSuggest() throws {
        let legal = try XCTUnwrap(VocabularyFixtures.positives["legal"])
        let medical = try XCTUnwrap(VocabularyFixtures.positives["medical"])
        XCTAssertNil(termsOnly.suggestion(for: legal + " " + medical))
    }

    func testAbbreviationsCountOnlyInCapitals() {
        let catalog = VocabularyCatalog(domains: [VocabularyDomain(
            id: "medical", name: "Medical", description: "Clinical.", summaryLayout: ["A"],
            terms: ["BID", "CBC", "po", "dyspnea", "pitting edema"])])
        let classifier = VocabularyClassifier(catalog: catalog, similarity: nil)
        XCTAssertEqual(classifier.scores(for: "we placed a bid on the cbc po box").first?.distinctTerms, 0)
        let score = classifier.scores(for: "CBC twice, CBC again, BID dosing, dyspnea and pitting edema").first
        XCTAssertEqual(score?.distinctTerms, 4)
        XCTAssertEqual(score?.weightedHits, 5)
    }

    func testSharedTermsWeighLess() {
        let shared = VocabularyCatalog(domains: [
            VocabularyDomain(id: "sales", name: "Sales", description: "S.", summaryLayout: ["A"], terms: ["ARR", "quota"]),
            VocabularyDomain(id: "finance", name: "Finance", description: "F.", summaryLayout: ["A"], terms: ["ARR", "EBITDA"])
        ])
        let scores = VocabularyClassifier(catalog: shared, similarity: nil).scores(for: "ARR and EBITDA")
        XCTAssertEqual(scores.first { $0.id == "sales" }?.weightedHits, 0.5)
        XCTAssertEqual(scores.first { $0.id == "finance" }?.weightedHits, 1.5)
    }

    func testWordCountUsesTheLanguagesTokenizer() {
        XCTAssertEqual(VocabularyClassifier.wordCount("one two three"), 3)
        XCTAssertGreaterThan(VocabularyClassifier.wordCount("我们今天讨论项目计划"), 2)
        XCTAssertEqual(VocabularyClassifier.wordCount(""), 0)
        XCTAssertNil(SentenceEmbeddingSimilarity.cosine([1, 0], [1]))
        XCTAssertNil(SentenceEmbeddingSimilarity.cosine([0, 0], [1, 0]))
        XCTAssertEqual(SentenceEmbeddingSimilarity.cosine([1, 0], [2, 0]), 1)
    }

    // MARK: - Tracker

    func testEachPresetIsOfferedOncePerConversation() throws {
        let text = try XCTUnwrap(VocabularyFixtures.positives["legal"])
        var tracker = VocabularySuggestionTracker(conversationID: "a")
        let settings = VocabularySettings()
        XCTAssertEqual(tracker.evaluate(text: text, settings: settings, classifier: termsOnly), "legal")
        XCTAssertEqual(tracker.offeredIDs, ["legal"])
        XCTAssertNil(tracker.evaluate(text: text + " " + text, settings: settings, classifier: termsOnly))
        tracker.begin(conversationID: "a")
        XCTAssertEqual(tracker.offeredIDs, ["legal"], "the same conversation keeps its state")
        tracker.begin(conversationID: "b")
        XCTAssertEqual(tracker.offeredIDs, [])
        XCTAssertEqual(tracker.conversationID, "b")
        XCTAssertEqual(tracker.evaluate(text: text, settings: settings, classifier: termsOnly), "legal")
    }

    func testTheClassifierWaitsForEnoughNewSpeech() throws {
        let text = try XCTUnwrap(VocabularyFixtures.positives["legal"])
        let words = text.split(separator: " ")
        var tracker = VocabularySuggestionTracker(conversationID: "a")
        let opening = words.prefix(100).joined(separator: " ")
        XCTAssertNil(tracker.evaluate(text: opening, settings: VocabularySettings(), classifier: termsOnly))
        XCTAssertEqual(tracker.evaluate(text: text, settings: VocabularySettings(), classifier: termsOnly), "legal")
    }

    func testSuggestionsRespectSettingsAndThisConversationsChoices() throws {
        let text = try XCTUnwrap(VocabularyFixtures.positives["sales"])
        var tracker = VocabularySuggestionTracker(conversationID: "a")
        XCTAssertNil(tracker.evaluate(text: text, settings: VocabularySettings(suggestionsEnabled: false),
                                      classifier: termsOnly))
        XCTAssertNil(tracker.evaluate(text: text, settings: VocabularySettings(mutedSuggestionIDs: ["sales"]),
                                      classifier: termsOnly))
        tracker = VocabularySuggestionTracker(conversationID: "a")
        XCTAssertNil(tracker.evaluate(text: text, settings: VocabularySettings(defaultDomainIDs: ["sales"]),
                                      classifier: termsOnly))
        tracker = VocabularySuggestionTracker(conversationID: "a")
        tracker.add("sales")
        XCTAssertEqual(tracker.addedIDs, ["sales"])
        XCTAssertNil(tracker.evaluate(text: text, settings: VocabularySettings(), classifier: termsOnly))
        tracker.remove("sales")
        XCTAssertEqual(tracker.addedIDs, [])
        XCTAssertTrue(tracker.offeredIDs.contains("sales"), "removing it does not offer it again")
        tracker.markOffered("medical")
        XCTAssertTrue(tracker.offeredIDs.contains("medical"))
    }
}
