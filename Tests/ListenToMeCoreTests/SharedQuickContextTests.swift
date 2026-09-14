import XCTest
@testable import ListenToMeCore

final class QuickSummaryContextTests: XCTestCase {
    func testPiecesCarrySpeakerAttributionAndMarkTypedNotes() throws {
        let alice = TranscriptSegment(source: .others, text: "Can you own the rollout?", isFinal: true,
                                      start: 0, end: 1, speakerName: "Alice")
        let you = TranscriptSegment(source: .you, text: "Yes, by Friday.", isFinal: true, start: 1, end: 2)
        let live = TranscriptSegment(source: .others, text: "One more thing about the budget line.",
                                     isFinal: false, start: 2, end: 3)
        let pieces = QuickSummaryContext.pieces(notes: "Ask about budget", segments: [alice, you], liveSegments: [live])
        XCTAssertEqual(pieces.map(\.text), ["Notes: Ask about budget", "Alice: Can you own the rollout?",
                                            "You: Yes, by Friday.", "Others: One more thing about the budget line."])
        XCTAssertEqual(pieces.map(\.id), ["notes:0", alice.id.uuidString + ":0", you.id.uuidString + ":0", "live:others:0"])
        XCTAssertTrue(QuickSummaryContext.pieces(notes: "   ", segments: []).isEmpty,
                      "Blank notes must not become a labelled piece")
    }

    func testLabelledLiveSpeechStillAppendsWithoutInvalidatingTheReadPrefix() throws {
        let context = QuickSummaryContext()
        func pieces(_ text: String) -> [QuickSummaryContext.Piece] {
            QuickSummaryContext.pieces(notes: "", segments: [], liveSegments: [
                .init(source: .others, text: text, isFinal: false, start: 0, end: 2)])
        }
        let text = "Peter will deliver the prototype on Wednesday."
        let batch = try XCTUnwrap(context.batch(pieces(text), summary: ""))
        XCTAssertEqual(batch.changes[0].text, "Others: " + text)
        XCTAssertTrue(context.isCurrent(batch, pieces: pieces(text + " Sarah will review it.")))
    }

    /// #111: a keystroke in Notes used to discard a completed Quick read, because notes are the
    /// first piece and any edit moved every later piece in the joined comparison.
    func testTypedNotesDoNotDiscardAReadOfSpeech() throws {
        var context = QuickSummaryContext()
        let speech = TranscriptSegment(source: .others, text: "Sarah confirms Monday.", isFinal: true, start: 0, end: 1)
        let batch = try XCTUnwrap(context.batch(
            QuickSummaryContext.pieces(notes: "Ask about budget", segments: [speech]), summary: ""))
        let edited = QuickSummaryContext.pieces(notes: "Ask about budget and headcount", segments: [speech])
        XCTAssertTrue(context.isCurrent(batch, pieces: edited),
                      "Typing a note is new context for the next read, not a reason to throw this one away")
        context.accept(batch, memory: "Monday")
        XCTAssertTrue(context.hasChanges(edited), "The newer note is still read next time")
    }

    func testSnapshotContinuationComparesEachPieceInsteadOfTheJoinedTranscript() {
        func piece(_ id: String, _ text: String) -> QuickSummaryContext.Piece { .init(id: id, text: text) }
        let snapshot = [piece("notes:0", "Notes: budget"), piece("live:you:0", "You: why is Azure"),
                        piece("final:0", "Others: the region is far")]
        XCTAssertTrue(QuickSummaryContext.isContinuation(of: snapshot, in: snapshot))
        XCTAssertTrue(QuickSummaryContext.isContinuation(of: snapshot, in: [
            piece("notes:0", "Notes: budget and headcount"), piece("live:you:0", "You: why is Azure slow"),
            piece("final:0", "Others: the region is far")]), "Notes edits and appended speech are continuations")
        XCTAssertTrue(QuickSummaryContext.isContinuation(of: snapshot, in: [
            piece("final:0", "Others: the region is far"), piece("final:1", "You: why is Azure slow")]),
            "A finalized hypothesis removes its live piece and republishes as a final one")
        XCTAssertFalse(QuickSummaryContext.isContinuation(of: snapshot, in: [
            piece("notes:0", "Notes: budget"), piece("live:you:0", "You: why is AWS"),
            piece("final:0", "Others: the region is far")]), "A rewritten hypothesis invalidates")
        XCTAssertFalse(QuickSummaryContext.isContinuation(of: snapshot, in: [
            piece("notes:0", "Notes: budget"), piece("live:you:0", "You: why is Azure"),
            piece("final:0", "Others: the region is nearby")]), "A corrected final invalidates")
        XCTAssertFalse(QuickSummaryContext.isContinuation(of: snapshot, in: [piece("notes:0", "Notes: budget")]),
                       "A dropped final invalidates")
    }

    func testResponseLanguageReplacesTheFollowTheTranscriptRuleInsteadOfContradictingIt() throws {
        let pieces = [QuickSummaryContext.Piece(id: "a", text: "You: Sarah confirms Monday.")]
        let plain = try XCTUnwrap(QuickSummaryContext().batch(pieces, summary: ""))
        XCTAssertEqual(plain.request.system, QuickSummaryContext.instructions)
        XCTAssertTrue(plain.request.system.contains("keep visibleSummary's language"),
                      "Without a setting the evaluator still follows the transcript")
        let localized = try XCTUnwrap(QuickSummaryContext().batch(pieces, summary: "",
                                                                 responseLanguage: " Simplified Chinese "))
        XCTAssertTrue(localized.request.system.contains(
            "Language: always write context and bullets in Simplified Chinese"), localized.request.system)
        XCTAssertFalse(localized.request.system.contains("keep visibleSummary's language"),
                       "The prompt must state one language rule, not two contradictory ones")
        XCTAssertEqual(localized.request.system.count,
                       QuickSummaryContext.instructions.count
                       - QuickSummaryContext.followTheTranscriptLanguage.count
                       + "Language: always write context and bullets in Simplified Chinese, regardless of the language spoken in the transcript.".count)
    }

    func testTypedNotesAreExplainedToEveryReviewer() {
        XCTAssertTrue(QuickSummaryContext.instructions.contains("\"Notes: \" is the user's typed"))
        for mode in AutomaticReviewMode.allCases {
            XCTAssertTrue(mode.instructions.contains("\"Notes: \" is the user's typed"), mode.rawValue)
        }
    }

    func testEveryChunkOfALongUtteranceKeepsItsSpeakerLabel() throws {
        let long = String(repeating: "We keep discussing the rollout schedule. ", count: 60)
        let segment = TranscriptSegment(source: .others, text: long, isFinal: true,
                                        start: 0, end: 90, speakerName: "Alice")
        let pieces = QuickSummaryContext.pieces(notes: "", segments: [segment])
        XCTAssertGreaterThan(pieces.count, 1, "This utterance must span several chunks")
        XCTAssertTrue(pieces.allSatisfy { $0.text.hasPrefix("Alice: ") },
                      "A later chunk must not reach the model unattributed")
        let recovered = pieces.map { $0.text.dropFirst("Alice: ".count) }.joined()
        XCTAssertEqual(recovered, long.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testKeepAdvancesMemoryAndOnlyUnreadSpeechIsSentNext() throws {
        var context = QuickSummaryContext()
        let first = TranscriptSegment(source: .you, text: "Friday is a proposal.", isFinal: true, start: 0, end: 2)
        var pieces = QuickSummaryContext.pieces(notes: "", segments: [first])
        let batch = try XCTUnwrap(context.batch(pieces, summary: ""))
        context.accept(batch, memory: "Friday proposed, not agreed.")
        XCTAssertNil(try context.batch(pieces, summary: ""), "Silence must not produce another model request")
        let second = TranscriptSegment(source: .you, text: "QA needs longer.", isFinal: true, start: 2, end: 4)
        pieces = QuickSummaryContext.pieces(notes: "", segments: [first, second])
        let next = try XCTUnwrap(context.batch(pieces, summary: ""))
        let input = try JSONDecoder().decode(QuickSummaryContext.Input.self, from: Data(next.request.messages[0].content.utf8))
        XCTAssertEqual(input.runningContext, "Friday proposed, not agreed.")
        XCTAssertEqual(input.changes.map(\.text), ["You: QA needs longer."])
        XCTAssertEqual(input.recentSpeech.map(\.text), ["You: " + first.text])
    }

    func testPartialIsExcludedAndCorrectionAndRemovalAreExplicit() throws {
        var context = QuickSummaryContext()
        let segment = TranscriptSegment(source: .you, text: "Sarah confirms.", isFinal: true, start: 0, end: 2)
        let partial = TranscriptSegment(source: .you, text: "Actually Peter", isFinal: false, start: 2, end: 3)
        let pieces = QuickSummaryContext.pieces(notes: "", segments: [segment, partial])
        XCTAssertEqual(pieces.count, 1)
        let batch = try XCTUnwrap(context.batch(pieces, summary: ""))
        let corrected = TranscriptSegment(id: segment.id, source: segment.source, text: "Peter confirms.",
            isFinal: true, start: segment.start, end: segment.end, originalText: segment.text, correctionModel: "test-flash")
        let changed = QuickSummaryContext.pieces(notes: "", segments: [corrected])
        XCTAssertFalse(context.isCurrent(batch, pieces: changed), "An old response must not acknowledge a corrected phrase")
        context.accept(batch, memory: "Sarah confirms")
        let revision = try XCTUnwrap(context.batch(changed, summary: "Sarah confirms"))
        XCTAssertEqual(revision.changes[0].previousText, "You: Sarah confirms.")
        XCTAssertEqual(revision.changes[0].text, "You: Peter confirms.")
        context.accept(revision, memory: "Peter confirms")
        let removal = try XCTUnwrap(context.batch([], summary: "Peter confirms"))
        XCTAssertEqual(removal.changes[0].text, "")
        XCTAssertEqual(removal.changes[0].previousText, "You: Peter confirms.")
        context.accept(removal, memory: "")
        XCTAssertFalse(context.hasChanges([]))
    }

    func testLiveSpeechAppendRevisionAndFinalReplacement() throws {
        var context = QuickSummaryContext()
        func pieces(_ text: String) -> [QuickSummaryContext.Piece] {
            QuickSummaryContext.pieces(notes: "", segments: [], liveSegments: [
                .init(source: .you, text: text, isFinal: false, start: 0, end: 2)])
        }
        XCTAssertTrue(pieces("Maybe we should").isEmpty)
        let text = "Peter will deliver the prototype on Wednesday."
        let initial = pieces(text)
        let batch = try XCTUnwrap(context.batch(initial, summary: ""))
        XCTAssertTrue(context.isCurrent(batch, pieces: pieces(text + " Sarah will review it.")))
        XCTAssertFalse(context.isCurrent(batch, pieces: pieces(text.replacingOccurrences(of: "Wednesday", with: "Thursday"))))
        context.accept(batch, memory: text)
        XCTAssertFalse(context.hasChanges(pieces(text)), "Changing ASR UUIDs must not re-read identical wording")
        let final = QuickSummaryContext.pieces(notes: "", segments: [
            .init(source: .you, text: "Peter will deliver on Thursday.", isFinal: true, start: 0, end: 3)])
        XCTAssertFalse(context.isCurrent(batch, pieces: final))
        let replacement = try XCTUnwrap(context.batch(final, summary: text))
        XCTAssertEqual(replacement.changes.first?.previousText, "You: " + text)
        XCTAssertEqual(replacement.changes.first?.text, "")
        XCTAssertEqual(replacement.changes.last?.text, "You: Peter will deliver on Thursday.")
        context.accept(replacement, memory: "Thursday")
        XCTAssertFalse(context.hasChanges(final))
    }

    func testLongChineseInputIsBatchedWithoutDroppingTextOrExceedingBudget() throws {
        let original = String(repeating: "讨论交付安排与尚未确认的负责人。", count: 600)
        let segment = TranscriptSegment(source: .you, text: original, isFinal: true, start: 0, end: 300)
        let pieces = QuickSummaryContext.pieces(notes: "", segments: [segment])
        var context = QuickSummaryContext()
        var recovered = ""
        var batches = 0
        while let batch = try context.batch(pieces, summary: String(repeating: "摘", count: 1_500)) {
            batches += 1
            XCTAssertLessThan(batch.request.messages[0].content.count + batch.request.system.count, 8_000)
            recovered += batch.changes.map(\.text).joined()
            context.accept(batch, memory: String(repeating: "忆", count: 2_000))
        }
        XCTAssertGreaterThan(batches, 2)
        XCTAssertEqual(recovered.replacingOccurrences(of: "You: ", with: ""), original)
    }

    func testEvaluationContainsTypedReviewRecommendationsAndRejectsInvalidConfidence() throws {
        let response = #"{"action":"keep","context":"Two alternatives remain","bullets":[],"reviews":"#
            + #"[{"mode":"deep","confidence":"high","reason":"Unresolved tradeoff"}]}"#
        let result = try QuickSummaryDecision.parse(response)
        XCTAssertNil(result.summary)
        XCTAssertEqual(result.reviews.first?.mode, "deep")
        XCTAssertEqual(result.reviews.first?.confidence, "high")
        XCTAssertThrowsError(try QuickSummaryDecision.parse(response.replacingOccurrences(of: "high", with: "certain")))
        XCTAssertThrowsError(try QuickSummaryDecision.parse(response.replacingOccurrences(of: "deep", with: "publish")))
    }

    func testStrictDecisionContractKeepsReasoningAndMalformedOutputOffScreen() throws {
        let valid = #"{"reviews":[],"action":"publish","context":"A decision","bullets":["Monday delivery"]}"#
        for prefix in ["", "<think>internal reasoning</think>\n", "Internal preamble\n```json\n"] {
            XCTAssertEqual(try QuickSummaryDecision.parse(prefix + valid).summary, "- Monday delivery")
        }
        XCTAssertNil(try QuickSummaryDecision.parse(#"{"reviews":[],"action":"keep","context":"Proposal only","bullets":[]}"#).summary)
        for invalid in [valid + " trailing", String(valid.dropLast()),
                        #"{"reviews":[],"action":"keep","context":"x","bullets":["Hidden update"]}"#,
                        #"{"reviews":[],"action":"publish","context":"x","bullets":[]}"#,
                        #"{"reviews":[],"action":"publish","context":"x","bullets":["a"],"extra":true}"#,
                        #"{"reviews":[],"action":"unknown","context":"x","bullets":[]}"#,
                        #"{"reviews":[],"action":"publish","context":"x","bullets":["a","b","c","d","e","f"]}"#] {
            XCTAssertThrowsError(try QuickSummaryDecision.parse(invalid))
        }
    }

    /// A small on-device model cannot be held to the evaluator's JSON schema, so the manual Quick
    /// prompt for that path asks for plain bullets and is read back without the JSON parser.
    func testProseQuickPromptAndReaderAcceptWhatASmallOnDeviceModelActuallyReturns() {
        XCTAssertFalse(QuickSummaryContext.manualProseInstructions.contains("JSON"),
                       "The prose prompt must not ask a small on-device model for a JSON envelope")
        XCTAssertTrue(QuickSummaryContext.manualProseInstructions.contains("Notes: "),
                      "Typed notes still must not be recapped as speech")
        XCTAssertEqual(QuickSummaryContext.proseSummary("- Sarah owns the rollout.\n- Budget is unresolved."),
                       "- Sarah owns the rollout.\n- Budget is unresolved.")
        XCTAssertEqual(QuickSummaryContext.proseSummary("Sarah owns the rollout."), "- Sarah owns the rollout.")
        XCTAssertEqual(QuickSummaryContext.proseSummary("1. First point\n2) Second point"),
                       "- First point\n- Second point")
        XCTAssertEqual(QuickSummaryContext.proseSummary("```\n* Budget is unresolved.\n```"),
                       "- Budget is unresolved.")
        XCTAssertEqual(QuickSummaryContext.proseSummary("Key takeaways:\n- one\n- two\n- three\n- four"),
                       "- one\n- two\n- three", "At most three bullets are shown")
        XCTAssertEqual(QuickSummaryContext.proseSummary("Here is the recap:\nSarah owns the rollout."),
                       "- Sarah owns the rollout.", "An unmarked preamble line is not a takeaway")
        XCTAssertEqual(QuickSummaryContext.proseSummary("Budget owner: Sarah"), "- Budget owner: Sarah",
                       "A single line ending in a colon is the answer, not a preamble")
        XCTAssertEqual(QuickSummaryContext.proseSummary("- " + String(repeating: "x", count: 400))?.count, 242)
        XCTAssertNil(QuickSummaryContext.proseSummary("   "))
        XCTAssertNil(QuickSummaryContext.proseSummary("No key takeaway yet."))
        XCTAssertNil(QuickSummaryContext.proseSummary("{\"action\":\"keep\"}"))
    }
}
