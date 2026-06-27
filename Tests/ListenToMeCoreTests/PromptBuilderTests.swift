import XCTest
@testable import ListenToMeCore

final class PromptBuilderTests: XCTestCase {
    private func ctx(notes: String? = nil, summary: String? = nil,
                     responseLanguage: String? = nil, references: String? = nil,
                     personaGuidance: String? = nil) -> PromptContext {
        PromptContext(messages: [
            TranscriptSegment(source: .others, text: "What is our deploy plan?",
                              isFinal: true, start: 0, end: 1),
            TranscriptSegment(source: .you, text: "Good question.",
                              isFinal: true, start: 1, end: 2)
        ], notes: notes, summary: summary, responseLanguage: responseLanguage,
           references: references, personaGuidance: personaGuidance)
    }

    func testSystemPromptHasNoPreambleConstraint() {
        XCTAssertTrue(PromptBuilder.systemPrompt.lowercased().contains("concise"))
        XCTAssertTrue(PromptBuilder.systemPrompt.lowercased().contains("no preamble"))
    }

    func testTranscriptFormattedWithSpeakerLabels() {
        let req = PromptBuilder.build(context: ctx(), action: .answerQuestion)
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Others: What is our deploy plan?"))
        XCTAssertTrue(user.contains("You: Good question."))
    }

    func testActionInstructionVaries() {
        let answer = PromptBuilder.build(context: ctx(), action: .answerQuestion).messages.last!.content
        let recap = PromptBuilder.build(context: ctx(), action: .recap).messages.last!.content
        let follow = PromptBuilder.build(context: ctx(), action: .followUp).messages.last!.content
        XCTAssertTrue(answer.contains("answer"))
        XCTAssertTrue(recap.lowercased().contains("recap") || recap.lowercased().contains("summar"))
        XCTAssertTrue(follow.lowercased().contains("follow-up") || follow.lowercased().contains("question"))
    }

    func testNewQuickActionsProduceDistinctNonEmptyInstructions() {
        func quick(_ action: ResponseAction) -> String {
            PromptBuilder.build(context: ctx(), action: action).messages.last!.content
        }
        let actionItems = quick(.actionItems)
        let clarify = quick(.clarify)
        let counterpoint = quick(.counterpoint)
        let keyTerms = quick(.keyTerms)
        let draftReply = quick(.draftReply)

        for content in [actionItems, clarify, counterpoint, keyTerms, draftReply] {
            XCTAssertFalse(content.isEmpty)
        }
        XCTAssertTrue(actionItems.lowercased().contains("action item"))
        XCTAssertTrue(clarify.lowercased().contains("simpl") || clarify.lowercased().contains("plain"))
        XCTAssertTrue(counterpoint.lowercased().contains("challenge") || counterpoint.lowercased().contains("counter")
                      || counterpoint.lowercased().contains("devil"))
        XCTAssertTrue(keyTerms.lowercased().contains("define") || keyTerms.lowercased().contains("term"))
        XCTAssertTrue(draftReply.lowercased().contains("draft") || draftReply.lowercased().contains("reply"))

        // Each new action's instruction must be distinct from the others.
        let all = [actionItems, clarify, counterpoint, keyTerms, draftReply]
        XCTAssertEqual(Set(all).count, all.count, "New quick actions should yield distinct instructions")
    }

    func testNewActionsHandledByDeep() {
        func deep(_ action: ResponseAction) -> String {
            PromptBuilder.buildDeep(context: ctx(), action: action).messages.last!.content
        }
        let all = [deep(.actionItems), deep(.clarify), deep(.counterpoint), deep(.keyTerms), deep(.draftReply)]
        for content in all { XCTAssertFalse(content.isEmpty) }
        // Deep should differ from the Quick instruction for at least one new action.
        let quickActionItems = PromptBuilder.build(context: ctx(), action: .actionItems).messages.last!.content
        XCTAssertNotEqual(deep(.actionItems), quickActionItems,
                          "Deep instruction should differ from Quick for action items")
    }

    func testNotesInjectedWhenPresent() {
        let req = PromptBuilder.build(context: ctx(notes: "I am the backend lead."), action: .answerQuestion)
        XCTAssertTrue(req.messages.last!.content.contains("I am the backend lead."))
    }

    func testNotesOmittedWhenNil() {
        let req = PromptBuilder.build(context: ctx(notes: nil), action: .answerQuestion)
        XCTAssertFalse(req.messages.last!.content.contains("Context notes"))
    }

    func testListenerSummaryInjectedIntoQuickWhenPresent() {
        let req = PromptBuilder.build(
            context: ctx(summary: "Discussed the Friday deploy; owner is unclear."),
            action: .answerQuestion)
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Meeting summary so far"))
        XCTAssertTrue(user.contains("owner is unclear"))
    }

    func testListenerSummaryInjectedIntoDeepWhenPresent() {
        let req = PromptBuilder.buildDeep(
            context: ctx(summary: "Discussed the Friday deploy; owner is unclear."),
            action: .answerQuestion)
        XCTAssertTrue(req.messages.last!.content.contains("Meeting summary so far"))
    }

    func testListenerSummaryOmittedWhenNil() {
        let req = PromptBuilder.build(context: ctx(summary: nil), action: .answerQuestion)
        XCTAssertFalse(req.messages.last!.content.contains("Meeting summary so far"))
    }

    func testListenerBuilderDoesNotIncludeSummaryBlock() {
        // The listener generates the summary; it must not be fed its own summary back.
        let req = PromptBuilder.buildListener(context: ctx(summary: "prior summary text"))
        XCTAssertFalse(req.messages.last!.content.contains("Meeting summary so far"))
    }

    func testResponseLanguageDirectiveAppendedToQuickAndDeep() {
        let quick = PromptBuilder.build(context: ctx(responseLanguage: "Simplified Chinese"),
                                        action: .answerQuestion)
        let deep = PromptBuilder.buildDeep(context: ctx(responseLanguage: "Simplified Chinese"),
                                           action: .answerQuestion)
        XCTAssertTrue(quick.system.contains("Simplified Chinese"))
        XCTAssertTrue(deep.system.contains("Simplified Chinese"))
    }

    func testResponseLanguageDirectiveAppendedToListener() {
        let req = PromptBuilder.buildListener(context: ctx(responseLanguage: "Japanese"))
        XCTAssertTrue(req.system.contains("Japanese"))
    }

    func testReferencesInjectedIntoQuickAndDeep() {
        let quick = PromptBuilder.build(context: ctx(references: "### plan.md\nShip Friday"),
                                        action: .answerQuestion)
        let deep = PromptBuilder.buildDeep(context: ctx(references: "### plan.md\nShip Friday"),
                                           action: .answerQuestion)
        XCTAssertTrue(quick.messages.last!.content.contains("Reference material the user attached"))
        XCTAssertTrue(quick.messages.last!.content.contains("Ship Friday"))
        XCTAssertTrue(deep.messages.last!.content.contains("Reference material the user attached"))
    }

    func testReferencesNotIncludedInListener() {
        // The listener summarizes the live conversation; attached files shouldn't bloat it.
        let req = PromptBuilder.buildListener(context: ctx(references: "### plan.md\nShip Friday"))
        XCTAssertFalse(req.messages.last!.content.contains("Reference material"))
    }

    func testReferencesOmittedWhenNil() {
        let req = PromptBuilder.build(context: ctx(references: nil), action: .answerQuestion)
        XCTAssertFalse(req.messages.last!.content.contains("Reference material"))
    }

    func testResponseLanguageOmittedWhenNilOrBlank() {
        XCTAssertFalse(PromptBuilder.build(context: ctx(responseLanguage: nil),
                                           action: .answerQuestion).system.contains("respond in"))
        XCTAssertFalse(PromptBuilder.build(context: ctx(responseLanguage: "   "),
                                           action: .answerQuestion).system.contains("respond in"))
    }

    func testPersonaGuidanceAppendedToAllPanes() {
        let guidance = "The user is the candidate in a job interview."
        XCTAssertTrue(PromptBuilder.build(context: ctx(personaGuidance: guidance),
                                          action: .answerQuestion).system.contains(guidance))
        XCTAssertTrue(PromptBuilder.buildDeep(context: ctx(personaGuidance: guidance),
                                              action: .answerQuestion).system.contains(guidance))
        XCTAssertTrue(PromptBuilder.buildListener(context: ctx(personaGuidance: guidance))
                        .system.contains(guidance))
    }

    func testPersonaGuidanceOmittedWhenNilOrBlank() {
        XCTAssertFalse(PromptBuilder.build(context: ctx(personaGuidance: nil),
                                           action: .answerQuestion).system.contains("Context for this session"))
        XCTAssertFalse(PromptBuilder.build(context: ctx(personaGuidance: "  "),
                                           action: .answerQuestion).system.contains("Context for this session"))
    }

    func testSystemMessageIsFirst() {
        let req = PromptBuilder.build(context: ctx(), action: .proactive)
        XCTAssertEqual(req.system, PromptBuilder.systemPrompt)
    }

    // MARK: - buildListener tests

    func testListenerSystemPromptMentionsSummary() {
        let req = PromptBuilder.buildListener(context: ctx())
        XCTAssertTrue(req.system.lowercased().contains("summar"),
                      "Listener system prompt should mention summary")
    }

    func testListenerSystemPromptMentionsQuestionsOrActionItems() {
        let req = PromptBuilder.buildListener(context: ctx())
        let lower = req.system.lowercased()
        XCTAssertTrue(lower.contains("question") || lower.contains("action item"),
                      "Listener system prompt should mention questions or action items")
    }

    func testListenerIncludesTranscript() {
        let req = PromptBuilder.buildListener(context: ctx())
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Others: What is our deploy plan?"),
                      "Listener request should include transcript text")
    }

    func testListenerIncludesNotes() {
        let req = PromptBuilder.buildListener(context: ctx(notes: "Topic: release planning"))
        XCTAssertTrue(req.messages.last!.content.contains("release planning"),
                      "Listener request should include notes when present")
    }

    func testListenerHasSystemMessage() {
        let req = PromptBuilder.buildListener(context: ctx())
        XCTAssertFalse(req.system.isEmpty, "Listener request must have a non-empty system message")
    }

    // MARK: - buildDeep tests

    func testDeepSystemPromptContainsDetailedOrThoroughOrReasoned() {
        let req = PromptBuilder.buildDeep(context: ctx(), action: .answerQuestion)
        let lower = req.system.lowercased()
        XCTAssertTrue(lower.contains("detail") || lower.contains("thorough") || lower.contains("reason"),
                      "Deep system prompt should mention detail/thorough/reason")
    }

    func testDeepSystemPromptDiffersFromQuick() {
        let quick = PromptBuilder.build(context: ctx(), action: .answerQuestion)
        let deep = PromptBuilder.buildDeep(context: ctx(), action: .answerQuestion)
        XCTAssertNotEqual(quick.system, deep.system,
                          "Deep system prompt must differ from Quick system prompt")
    }

    func testDeepIncludesTranscript() {
        let req = PromptBuilder.buildDeep(context: ctx(), action: .answerQuestion)
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Others: What is our deploy plan?"),
                      "Deep request should include transcript text")
    }

    func testDeepIncludesNotes() {
        let req = PromptBuilder.buildDeep(context: ctx(notes: "Architecture notes"), action: .recap)
        XCTAssertTrue(req.messages.last!.content.contains("Architecture notes"),
                      "Deep request should include notes when present")
    }

    func testDeepHasSystemMessage() {
        let req = PromptBuilder.buildDeep(context: ctx(), action: .answerQuestion)
        XCTAssertFalse(req.system.isEmpty, "Deep request must have a non-empty system message")
    }

    func testDeepActionInstructionVaries() {
        let answer = PromptBuilder.buildDeep(context: ctx(), action: .answerQuestion).messages.last!.content
        let recap = PromptBuilder.buildDeep(context: ctx(), action: .recap).messages.last!.content
        XCTAssertNotEqual(answer, recap, "Deep should vary instruction by action")
    }
}
