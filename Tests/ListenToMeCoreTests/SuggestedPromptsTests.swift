import XCTest
@testable import ListenToMeCore

/// Context-aware "Suggested" prompt chips (#61): validation, cadence, clearing, the evaluator and
/// prose contracts that carry them, and the macOS session's tap path. No real model is called.
final class SuggestedPromptsTests: XCTestCase {

    // MARK: - Validation

    func testSanitizeCleansMarkersAndQuotesAndKeepsAtMostThree() {
        XCTAssertEqual(SuggestedPrompts.sanitize([
            "- Counter the net-30 ask", "  \"Summarize pricing options\"  ", "1. Who owns the rollout?",
            "> Draft a reply to Sam", "Ask about the budget",
        ]), ["Counter the net-30 ask", "Summarize pricing options", "Who owns the rollout?"])
        XCTAssertEqual(SuggestedPrompts.clean("**Ask   about   Q3**"), "Ask about Q3", "Emphasis is decoration")
        XCTAssertEqual(SuggestedPrompts.clean("Explain __init__ in Python"), "Explain __init__ in Python",
                       "Markup inside a chip is kept")
        XCTAssertEqual(SuggestedPrompts.clean("What's Sam's deadline?"), "What's Sam's deadline?",
                       "Apostrophes are part of the words")
        XCTAssertEqual(SuggestedPrompts.clean("“Clarify   the   SLA”"), "Clarify the SLA")
    }

    func testSanitizeDedupesIgnoringCasePunctuationAndSpacing() {
        XCTAssertEqual(SuggestedPrompts.sanitize([
            "Ask about pricing?", "ask about  pricing", "ASK ABOUT PRICING!", "Ask about pricíng", "Next steps?",
        ]), ["Ask about pricing?", "Next steps?"])
    }

    func testLengthLimitRejectsRatherThanTruncates() {
        let sixty = String(repeating: "a", count: 59) + "?"
        XCTAssertEqual(SuggestedPrompts.clean(sixty), sixty)
        XCTAssertNil(SuggestedPrompts.clean(sixty + "b"), "A cut-off literal prompt is not a prompt")
    }

    func testJunkIsRejected() {
        let junk = [
            "", "   ", "-", "??", "Ok", "none", "N/A", "No suggestions yet", "request", "Suggested:",
            "{\"action\":\"keep\"}", "[\"a\"]", "<transcript>", "See https://example.com",
            "Visit www.example.com", "Line one\nLine two", "a | b | c", "```",
        ]
        for value in junk { XCTAssertNil(SuggestedPrompts.clean(value), value) }
        XCTAssertEqual(SuggestedPrompts.sanitize(junk), [])
        XCTAssertEqual(SuggestedPrompts.clean("问一下预算"), "问一下预算", "Non-Latin requests are kept")
    }

    // MARK: - Cadence and rate limiting

    func testFirstSetShowsAtOnceAndLaterSetsWaitOutTheRefreshWindow() {
        var chips = SuggestedPrompts()
        XCTAssertTrue(chips.offer(["Ask about pricing"], at: 100))
        XCTAssertFalse(chips.offer(["Who owns onboarding?"], at: 105), "Chips must not change under the pointer")
        XCTAssertEqual(chips.prompts, ["Ask about pricing"])
        // The held set appears on the first pass after the window, even one that brings nothing.
        XCTAssertFalse(chips.offer([], at: 110))
        XCTAssertTrue(chips.offer([], at: 100 + SuggestedPrompts.minimumRefreshInterval))
        XCTAssertEqual(chips.prompts, ["Who owns onboarding?"])
        XCTAssertFalse(chips.offer([], at: 500), "Nothing pending: an empty pass keeps what is showing")
        XCTAssertEqual(chips.prompts, ["Who owns onboarding?"])
    }

    func testNewestHeldSetWinsAndIdenticalSetsAreNoOps() {
        var chips = SuggestedPrompts()
        chips.offer(["One idea"], at: 0)
        chips.offer(["Second idea"], at: 5)
        chips.offer(["Third idea"], at: 10)
        XCTAssertTrue(chips.offer([], at: 25))
        XCTAssertEqual(chips.prompts, ["Third idea"])
        XCTAssertFalse(chips.offer(["Third idea"], at: 100), "An unchanged set does not restart the window")
    }

    func testAPassTheUserAskedForReplacesChipsAtOnce() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing"], at: 100)
        XCTAssertTrue(chips.offer(["Draft a reply to Sam"], at: 101, force: true))
        XCTAssertEqual(chips.prompts, ["Draft a reply to Sam"])
    }

    // MARK: - Using and clearing

    func testATappedChipLeavesTheRowAndIsNotSuggestedAgain() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing", "Next steps?"], at: 0)
        chips.use("Ask about pricing")
        XCTAssertEqual(chips.prompts, ["Next steps?"])
        chips.offer(["ask about pricing!", "Who decides?"], at: 100)
        XCTAssertEqual(chips.prompts, ["Who decides?"])
    }

    func testClearDropsChipsAndHeldSetsButRemembersUsedOnes() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing"], at: 0)
        chips.use("Ask about pricing")
        chips.offer(["Next steps?"], at: 1)
        chips.offer(["Held for later"], at: 2)
        chips.clear()
        XCTAssertTrue(chips.isEmpty)
        XCTAssertFalse(chips.offer([], at: 1_000), "A held set must not resurface after clearing")
        chips.offer(["Ask about pricing", "Fresh idea"], at: 1_001)
        XCTAssertEqual(chips.prompts, ["Fresh idea"])
        XCTAssertTrue(SuggestedPrompts().isEmpty, "A new conversation starts with no chips and no memory")
    }

    // MARK: - Evaluator contract

    func testDecisionCarriesSanitizedSuggestionsAndOldEnvelopesStayValid() throws {
        let with = #"{"action":"publish","context":"Pricing","bullets":["Pricing is open."],"reviews":[],"#
            + #""suggestions":["Summarize pricing options","summarize pricing options","{junk}","none"]}"#
        let decision = try QuickSummaryDecision.parse(with)
        XCTAssertEqual(decision.summary, "- Pricing is open.")
        XCTAssertEqual(decision.suggestions, ["Summarize pricing options"])
        let without = try QuickSummaryDecision.parse(
            #"{"action":"keep","context":"x","bullets":[],"reviews":[]}"#)
        XCTAssertEqual(without.suggestions, [])
    }

    func testMalformedSuggestionsCostTheChipsNeverTheRecap() throws {
        for value in [#""Ask about pricing""#, "42", "null", #"[1, 2]"#] {
            let response = #"{"action":"publish","context":"x","bullets":["Recap"],"reviews":[],"suggestions":"#
                + value + "}"
            let decision = try QuickSummaryDecision.parse(response)
            XCTAssertEqual(decision.summary, "- Recap", value)
            XCTAssertEqual(decision.suggestions, [], value)
        }
        XCTAssertThrowsError(try QuickSummaryDecision.parse(
            #"{"action":"publish","context":"x","bullets":["a"],"reviews":[],"suggestions":[],"extra":1}"#),
            "Only the documented optional key is accepted")
    }

    func testEvaluatorPromptAsksForBoundedSuggestionsOnlyWithPublish() {
        let prompt = QuickSummaryContext.instructions
        XCTAssertTrue(prompt.contains(#""suggestions":["request"]"#))
        XCTAssertTrue(prompt.contains("<=60 characters"))
        XCTAssertTrue(prompt.contains("suggestions=[] with keep"))
        XCTAssertTrue(QuickSummaryContext.instructions(responseLanguage: "French").contains("suggestions"),
                      "The response-language variant keeps the suggestion contract")
        let schema = QuickSummaryDecision.jsonSchema
        XCTAssertTrue((schema["required"] as? [String] ?? []).contains("suggestions"))
    }

    // MARK: - On-device prose

    func testAFinalSuggestedBlockBecomesChipsAndNeverTakeaways() {
        let response = """
        - Pricing is still open.
        - Sam owns the proposal.
        **Suggested:**
        > Summarize pricing options
        > Draft a reply to Sam
        > {"oops": true}

        """
        let split = SuggestedPrompts.splitProse(response)
        XCTAssertEqual(split.suggestions, ["Summarize pricing options", "Draft a reply to Sam"])
        XCTAssertEqual(QuickSummaryContext.proseSummary(response), "- Pricing is still open.\n- Sam owns the proposal.")
        for heading in ["Suggested questions:", "### Suggestions:", "suggested prompts:"] {
            let response = "- Pricing is open.\n\(heading)\n> Ask about pricing"
            XCTAssertEqual(SuggestedPrompts.splitProse(response).suggestions, ["Ask about pricing"], heading)
        }
        let fenced = "```\n- Pricing is open.\nSuggested:\n> Ask about pricing\n```"
        XCTAssertEqual(SuggestedPrompts.splitProse(fenced).suggestions, ["Ask about pricing"])
        XCTAssertEqual(QuickSummaryContext.proseSummary(fenced), "- Pricing is open.")
    }

    /// Review finding: a heading written first or mid-answer, a blank line, or bullet-style lines
    /// inside the block used to turn real takeaways ("2025 budget approved") into chips.
    func testASuggestedHeadingAnywhereButTheEndKeepsEveryBulletAndGivesNoChips() {
        let cases: [(String, String)] = [
            ("Suggested:\n> Ask about pricing\n- Pricing is open.\n- Sam owns it.",
             "- Pricing is open.\n- Sam owns it."),
            ("- Pricing is open.\nSuggested:\n> Ask about pricing\n- Sam owns it.",
             "- Pricing is open.\n- Sam owns it."),
            ("- Pricing is open.\nSuggested:\n- 2025 budget approved", "- Pricing is open.\n- 2025 budget approved"),
            ("- Pricing is open.\nSuggested:\n1. Who owns the budget?", "- Pricing is open.\n- Who owns the budget?"),
            ("- Pricing is open.\nSuggested:\n> Ask about pricing\n\n> Ask about Sam", "- Pricing is open."),
            ("- Pricing is open.\nSuggested:\n> Ask one\nSuggested:\n> Ask two", "- Pricing is open."),
            ("- Pricing is open.\nSuggested:\n> Ask about pricing\nThanks!", "- Pricing is open."),
        ]
        for (response, recap) in cases {
            let split = SuggestedPrompts.splitProse(response)
            XCTAssertEqual(split.suggestions, [], response)
            XCTAssertEqual(split.body, response, "The whole answer stays the recap: \(response)")
            XCTAssertEqual(QuickSummaryContext.proseSummary(response), recap, response)
        }
        XCTAssertEqual(SuggestedPrompts.splitProse("Suggested:\n> Ask about pricing").suggestions, [],
                       "No recap above the block, no chips")
        XCTAssertTrue(SuggestedPrompts.proseInstructions.contains("always this English"),
                      "Other languages keep the English heading the parser reads")
    }

    func testProseWithoutTheHeadingHasNoChipsAndAnUnchangedRecap() {
        let response = "- Pricing is still open.\n> Summarize pricing options"
        XCTAssertEqual(SuggestedPrompts.splitProse(response).suggestions, [])
        XCTAssertEqual(SuggestedPrompts.splitProse(response).body, response)
        XCTAssertEqual(QuickSummaryContext.proseSummary(response), "- Pricing is still open.")
        XCTAssertEqual(SuggestedPrompts.splitProse("No key takeaway yet.").suggestions, [])
        XCTAssertNil(QuickSummaryContext.proseSummary("No key takeaway yet.\nSuggested:\n> Ask something"))
        XCTAssertTrue(QuickSummaryContext.manualProseInstructions.contains(SuggestedPrompts.proseInstructions))
        XCTAssertFalse(QuickSummaryContext.manualProseInstructions.contains("JSON"))
    }

    // MARK: - Tapped prompt

    func testATappedChipIsSentLiterallyOnOneLineThroughQuickAndDeep() {
        let context = PromptContext(messages: [TranscriptSegment(source: .others, text: "Net 30?", isFinal: true,
                                                                 start: 0, end: 1)], notes: nil)
        let quick = PromptBuilder.build(context: context, action: .ask("Counter the net-30 ask"))
        let user = quick.messages.last?.content ?? ""
        XCTAssertTrue(user.hasSuffix(#"The user asks: "Counter the net-30 ask". Respond to that request, "#
            + "grounded in the transcript and notes. Answer briefly."))
        XCTAssertTrue(user.contains("<transcript>"), "The tapped request is answered from the fenced transcript")
        let deep = PromptBuilder.buildDeep(context: context, action: .ask("Line one\nLine two"))
        XCTAssertTrue(deep.messages.last?.content.contains(#""Line one Line two""#) ?? false)
        XCTAssertNotEqual(quick.system, deep.system)
    }
}
