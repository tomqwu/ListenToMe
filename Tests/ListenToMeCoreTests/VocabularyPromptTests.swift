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
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 1_500))
        XCTAssertTrue(guidance.hasPrefix("Domain: Medical — A clinical or health-care conversation"))
        XCTAssertTrue(guidance.contains("organize it under these headings: History, Findings, Plan."))
        XCTAssertTrue(guidance.contains("never add a term nobody said"))
        XCTAssertTrue(guidance.contains("Glossary (") && guidance.contains("Dr. Okafor, metoprolol"))
        XCTAssertLessThanOrEqual(guidance.count, 1_500)
        let compact = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 400))
        XCTAssertLessThanOrEqual(compact.count, 400)
        let noLayout = try XCTUnwrap(VocabularyPrompt.guidance(for: active, includeLayout: false))
        XCTAssertFalse(noLayout.contains("headings"))
        let tiny = try XCTUnwrap(VocabularyPrompt.guidance(for: active, characterLimit: 30))
        XCTAssertEqual(tiny.count, 30, "a pathological limit truncates instead of overrunning")
    }

    func testMyTermsAloneStillProduceAGlossary() throws {
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: ActiveVocabulary(domains: [], myTerms: ["Acme"])))
        XCTAssertTrue(guidance.hasPrefix("Glossary ("))
        XCTAssertTrue(guidance.hasSuffix("Acme."))
    }

    func testTermsHeardInTheTranscriptAreListedBeforeTheRest() throws {
        let active = ActiveVocabulary(domains: [cloud], myTerms: [])
        let guidance = try XCTUnwrap(VocabularyPrompt.guidance(for: active, transcript: "we moved the queue to Kafka",
                                                                characterLimit: 400, includeLayout: false))
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
            characterLimit: VocabularyPrompt.characterLimit(forPromptWindow: limit)))
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
        let active = ActiveVocabulary(domains: [cloud], myTerms: ["Acme Cloud"])
        let glossary = VocabularyPrompt.correctionGlossary(for: active, text: "we deploy it on kubernetis with terra form")
        XCTAssertEqual(glossary.first, "Acme Cloud")
        XCTAssertTrue(glossary.contains("Kubernetes"), "\(glossary)")
        XCTAssertTrue(glossary.contains("Terraform"), "\(glossary)")
        XCTAssertLessThanOrEqual(glossary.count, VocabularyPrompt.correctionGlossaryLimit)
        XCTAssertFalse(glossary.contains("DynamoDB"), "only terms resembling the phrase are listed")
        XCTAssertEqual(VocabularyPrompt.correctionGlossary(for: ActiveVocabulary(domains: [], myTerms: []), text: "x"), [])
        XCTAssertEqual(VocabularyPrompt.correctionGlossary(for: active, text: "x", limit: 0), [])
    }

    func testCorrectionGlossaryIsCapped() {
        let mine = (0..<50).map { "Name\($0)" }
        let glossary = VocabularyPrompt.correctionGlossary(for: ActiveVocabulary(domains: [cloud], myTerms: mine),
                                                           text: "kubernetes", limit: 10)
        XCTAssertLessThanOrEqual(glossary.count, 10)
        XCTAssertEqual(Array(glossary.prefix(5)), Array(mine.prefix(5)), "My terms take at most half")
        XCTAssertEqual(glossary[5], "Kubernetes", "the closest preset term comes first")
    }

    func testResemblanceAndTermRemoval() {
        XCTAssertEqual(VocabularyPrompt.resemblance(of: "Kubernetes", in: ["kubernetes"]), 1)
        XCTAssertGreaterThan(VocabularyPrompt.resemblance(of: "Terraform", in: ["terra", "form"]), 0.9)
        XCTAssertEqual(VocabularyPrompt.resemblance(of: "S3", in: ["s3"]), 0, "too short to compare safely")
        XCTAssertEqual(VocabularyPrompt.resemblance(of: "Kubernetes", in: []), 0)
        XCTAssertEqual(VocabularyPrompt.removingTerms(["EC2", "ISO 9001"], from: "move ec2 to iso 9001 now"), "move   to   now")
    }
}
