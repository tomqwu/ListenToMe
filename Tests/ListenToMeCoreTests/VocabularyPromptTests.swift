import XCTest
@testable import ListenToMeCore

/// Vocabulary guidance in Summary/Quick/Deep prompts and the correction glossary (issue #222).
final class VocabularyPromptTests: XCTestCase {
    private var medical: VocabularyDomain { VocabularyCatalog.bundled.domain(id: "medical")! }
    private var cloud: VocabularyDomain { VocabularyCatalog.bundled.domain(id: "software-cloud")! }

    func testNoVocabularyMeansNoGuidance() {
        XCTAssertNil(VocabularyPrompt.guidance(for: ActiveVocabulary(domains: [], myTerms: [])))
        XCTAssertNil(VocabularyPrompt.guidance(for: ActiveVocabulary(domains: [medical], myTerms: []), characterLimit: 0))
    }

    func testGuidanceCarriesDomainLayoutAndGlossaryWithinTheLimit() throws {
        let active = ActiveVocabulary(domains: [medical], myTerms: ["Dr. Okafor"])
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 1_500, includeLayout: true))
        XCTAssertTrue(guidance.hasPrefix("Domain: Medical — A clinical or health-care conversation"))
        XCTAssertTrue(guidance.contains("organize it under these headings: History, Findings, Plan."))
        XCTAssertTrue(guidance.contains("never add a term nobody said"))
        XCTAssertTrue(guidance.contains("Glossary (") && guidance.contains("Dr. Okafor, metoprolol"))
        XCTAssertLessThanOrEqual(guidance.count, 1_500)
        let compact = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 400))
        XCTAssertLessThanOrEqual(compact.count, 400)
        let noLayout = try XCTUnwrap(VocabularyPrompt.guidance(for: active))
        XCTAssertFalse(noLayout.contains("headings"), "headings are for summaries only, and opt-in")
        XCTAssertNil(VocabularyPrompt.guidance(for: active, characterLimit: 30), "nothing useful fits, nothing is sent")
    }

    /// Apple Intelligence's 400 characters: the glossary — My terms first — always keeps at least half,
    /// so the domain line and headings can never squeeze My terms out (#222 review).
    func testEveryPresetKeepsMyTermsAndAGlossaryAtTheAppleCap() throws {
        for domain in VocabularyCatalog.bundled.domains {
            let active = ActiveVocabulary(domains: [domain], myTerms: ["Dr. Okafor", "Acme Cloud", "张伟"])
            let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 400, includeLayout: true))
            XCTAssertLessThanOrEqual(guidance.count, 400, domain.id)
            XCTAssertTrue(guidance.contains("Domain: \(domain.name)."), domain.id)
            XCTAssertTrue(guidance.contains("Summary headings: "), domain.id)
            let glossary = try XCTUnwrap(guidance.components(separatedBy: "never add unsaid ones): ").last)
            let terms = glossary.dropLast().components(separatedBy: ", ")
            XCTAssertEqual(Array(terms.prefix(3)), ["Dr. Okafor", "Acme Cloud", "张伟"], domain.id)
            XCTAssertGreaterThanOrEqual(terms.count, 10, "\(domain.id): \(terms.count) terms")
        }
        // Two presets with headings still leave the glossary its half.
        let both = ActiveVocabulary(domains: Array(VocabularyCatalog.bundled.domains.prefix(2)), myTerms: ["Acme"])
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: both, characterLimit: 400, includeLayout: true))
        XCTAssertGreaterThanOrEqual(guidance.components(separatedBy: "unsaid ones): ").last?.count ?? 0, 190)
    }

    func testTheLayoutSentenceComesOnlyFromLayoutInstruction() {
        let medical = ActiveVocabulary(domains: [medical], myTerms: [])
        XCTAssertEqual(VocabularyPrompt.layoutInstruction(for: medical),
                       "When writing a summary or meeting record, organize it under these headings: History, Findings, Plan.")
        XCTAssertEqual(VocabularyPrompt.layoutInstruction(for: medical, compact: true),
                       "Summary headings: History, Findings, Plan.")
        XCTAssertNil(VocabularyPrompt.layoutInstruction(for: ActiveVocabulary(domains: [], myTerms: ["Acme"])))
        XCTAssertNil(VocabularyPrompt.layoutInstruction(for: ActiveVocabulary(domains: [self.medical], myTerms: [],
                                                                              usesSummaryLayout: false)))
    }

    func testMyTermsAloneStillProduceAGlossary() throws {
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: ActiveVocabulary(domains: [], myTerms: ["Acme"])))
        XCTAssertTrue(guidance.hasPrefix("Glossary ("))
        XCTAssertTrue(guidance.hasSuffix("Acme."))
    }

    func testTermsHeardInTheTranscriptAreListedBeforeTheRest() throws {
        let active = ActiveVocabulary(domains: [cloud], myTerms: [])
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: active, transcript: "we moved the queue to Kafka",
                                                                characterLimit: 1_000))
        let glossary = try XCTUnwrap(guidance.components(separatedBy: "nobody said): ").last)
        XCTAssertTrue(glossary.hasPrefix("Kafka, Kubernetes"), glossary)
    }

    func testGuidanceBudgetFollowsTheProviderWindow() {
        XCTAssertEqual(VocabularyPrompt.characterLimit(forPromptWindow: nil), 1_500)
        XCTAssertEqual(VocabularyPrompt.characterLimit(forPromptWindow: PromptBudget.appleIntelligenceCharacters), 400)
        XCTAssertEqual(VocabularyPrompt.characterLimit(forPromptWindow: 1_000_000), 1_500)
        XCTAssertEqual(VocabularyPrompt.characterLimit(forPromptWindow: -5), 0)
    }

    func testCombinedPersonaJoinsNonEmptyPieces() {
        XCTAssertNil(VocabularyPrompt.combined(persona: nil, guidance: "  "))
        XCTAssertEqual(VocabularyPrompt.combined(persona: "This is a sales call.", guidance: nil), "This is a sales call.")
        XCTAssertEqual(VocabularyPrompt.combined(persona: "Persona.", guidance: "Domain: X."), "Persona. Domain: X.")
    }

    func testAddingGuidanceAppendsToTheSystemPromptOnly() {
        let request = LLMRequest(system: "Base.", messages: [ChatMessage(role: "user", content: "hi")], purpose: .quickEvaluation)
        XCTAssertEqual(request.addingGuidance(nil), request)
        XCTAssertEqual(request.addingGuidance(""), request)
        let guided = request.addingGuidance("Domain: Medical.")
        XCTAssertEqual(guided.system, "Base.\nContext for this session: Domain: Medical.")
        XCTAssertEqual(guided.messages, request.messages)
        XCTAssertEqual(guided.purpose, .quickEvaluation)
    }

    /// The guidance rides in the persona line, so `PromptBuilder` measures it as scaffold and
    /// `PromptBudget` takes it out of the transcript's share: an Apple-sized prompt still fits.
    func testGuidanceIsChargedToThePromptScaffoldAndTheWholePromptFits() throws {
        let limit = PromptBudget.appleIntelligenceCharacters
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(
            for: ActiveVocabulary(domains: [medical], myTerms: ["Acme"]),
            characterLimit: VocabularyPrompt.characterLimit(forPromptWindow: limit), includeLayout: true))
        let persona = VocabularyPrompt.combined(persona: "This is a medical consultation.", guidance: guidance)
        let plain = PromptContext(messages: [], notes: nil, personaGuidance: "This is a medical consultation.")
        let guided = PromptContext(messages: [], notes: nil, personaGuidance: persona)
        let plainCost = PromptBuilder.scaffoldCharacterCost(kind: .deep, context: plain, action: .recap)
        let guidedCost = PromptBuilder.scaffoldCharacterCost(kind: .deep, context: guided, action: .recap)
        XCTAssertEqual(guidedCost - plainCost, guidance.count + 1)
        let allocation = PromptBudget.allocate(limit: limit, scaffold: guidedCost, transcript: 50_000, references: 0)
        let line = String(repeating: "word ", count: 20)
        var lines: [TranscriptSegment] = []
        var spent = 0
        while true {
            let segment = TranscriptSegment(source: .others, text: line, isFinal: true, start: 0, end: 1)
            let cost = TranscriptSegment.promptCharacterCost(segment)
            guard spent + cost <= allocation.transcript else { break }
            spent += cost
            lines.append(segment)
        }
        let request = PromptBuilder.buildDeep(context: PromptContext(messages: lines, notes: nil, personaGuidance: persona),
                                              action: .recap)
        let total = request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
        XCTAssertTrue(request.system.contains("History, Findings, Plan"))
        XCTAssertLessThanOrEqual(total, limit - PromptBudget.answerReserve)
    }

    // MARK: - Transcript correction glossary

    func testCorrectionGlossaryOffersMyTermsAndNearMisses() {
        let active = ActiveVocabulary(domains: [cloud], myTerms: ["Acme Cloud", "Okafor"])
        let glossary = VocabularyPrompt.correctionGlossary(
            for: active, text: "ask okafer: we deploy acme clowd on kubernetis with terra form")
        XCTAssertEqual(Array(glossary.prefix(2)).sorted(), ["Acme Cloud", "Okafor"], "My terms that resemble the phrase lead")
        XCTAssertTrue(glossary.contains("Kubernetes"), "\(glossary)")
        XCTAssertTrue(glossary.contains("Terraform"), "\(glossary)")
        XCTAssertLessThanOrEqual(glossary.count, VocabularyPrompt.correctionGlossaryLimit)
        XCTAssertFalse(glossary.contains("DynamoDB"), "only terms resembling the phrase are listed")
        XCTAssertEqual(VocabularyPrompt.correctionGlossary(for: ActiveVocabulary(domains: [], myTerms: []), text: "x"), [])
        XCTAssertEqual(VocabularyPrompt.correctionGlossary(for: active, text: "x", limit: 0), [])
    }

    /// A long My terms list: the terms resembling the phrase reach correction wherever they sit in the
    /// list, not only the first twenty (#222 review).
    func testMyTermsAreRankedByResemblanceNotListPosition() {
        let mine = (0..<50).map { "Name\($0)" } + ["Zhang Wei", "Kubeflow"]
        let glossary = VocabularyPrompt.correctionGlossary(for: ActiveVocabulary(domains: [cloud], myTerms: mine),
                                                           text: "kubernetes and cube flow with jang way", limit: 10)
        XCTAssertLessThanOrEqual(glossary.count, 10)
        XCTAssertEqual(glossary.first, "Kubeflow")
        XCTAssertFalse(glossary.contains("Name0"), "unrelated My terms are not listed")
        XCTAssertTrue(glossary.contains("Kubernetes"), "\(glossary)")
        let capped = VocabularyPrompt.correctionGlossary(
            for: ActiveVocabulary(domains: [], myTerms: (0..<30).map { "Kube\($0)" }), text: "kube", limit: 10)
        XCTAssertEqual(capped.count, 5, "My terms take at most half")
    }

    func testTheCorrectionIndexIsPreparedOnceAndMatchesTheOneShotGlossary() {
        let active = ActiveVocabulary(domains: VocabularyCatalog.bundled.domains, myTerms: ["Acme Cloud", "S3"])
        let index = VocabularyPrompt.CorrectionIndex(active)
        XCTAssertEqual(index, VocabularyPrompt.CorrectionIndex(active))
        let phrase = "we moved the cooper netties cluster to terra form and paged pager duty"
        XCTAssertEqual(index.glossary(for: phrase), VocabularyPrompt.correctionGlossary(for: active, text: phrase))
        XCTAssertTrue(index.glossary(for: phrase).contains("Terraform"))
        XCTAssertEqual(index.glossary(for: ""), [])
        XCTAssertEqual(VocabularyPrompt.CorrectionIndex.pairs(["a"]), ["a"])
    }
}
