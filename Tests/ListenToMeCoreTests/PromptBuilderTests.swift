import XCTest
@testable import ListenToMeCore

final class PromptBuilderTests: XCTestCase {
    private func ctx(notes: String? = nil) -> PromptContext {
        PromptContext(messages: [
            TranscriptSegment(source: .others, text: "What is our deploy plan?",
                              isFinal: true, start: 0, end: 1),
            TranscriptSegment(source: .you, text: "Good question.",
                              isFinal: true, start: 1, end: 2)
        ], notes: notes)
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

    func testSystemMessageIsFirst() {
        let req = PromptBuilder.build(context: ctx(), action: .proactive)
        XCTAssertEqual(req.system, PromptBuilder.systemPrompt)
    }
}
