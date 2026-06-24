import XCTest
@testable import ListenToMeCore

final class PromptBuilderTests: XCTestCase {
    private func ctx(notes: String? = nil, summary: String? = nil,
                     responseLanguage: String? = nil) -> PromptContext {
        PromptContext(messages: [
            TranscriptSegment(source: .others, text: "What is our deploy plan?",
                              isFinal: true, start: 0, end: 1),
            TranscriptSegment(source: .you, text: "Good question.",
                              isFinal: true, start: 1, end: 2)
        ], notes: notes, summary: summary, responseLanguage: responseLanguage)
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

    func testResponseLanguageOmittedWhenNilOrBlank() {
        XCTAssertFalse(PromptBuilder.build(context: ctx(responseLanguage: nil),
                                           action: .answerQuestion).system.contains("respond in"))
        XCTAssertFalse(PromptBuilder.build(context: ctx(responseLanguage: "   "),
                                           action: .answerQuestion).system.contains("respond in"))
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
