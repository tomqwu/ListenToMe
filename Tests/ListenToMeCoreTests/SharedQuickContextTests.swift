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

    func testResponseLanguageDirectiveReachesTheQuickEvaluator() throws {
        let pieces = [QuickSummaryContext.Piece(id: "a", text: "You: Sarah confirms Monday.")]
        let plain = try XCTUnwrap(QuickSummaryContext().batch(pieces, summary: ""))
        XCTAssertEqual(plain.request.system, QuickSummaryContext.instructions)
        let localized = try XCTUnwrap(QuickSummaryContext().batch(pieces, summary: "",
                                                                 responseLanguage: "Simplified Chinese"))
        XCTAssertTrue(localized.request.system.contains("Simplified Chinese"), localized.request.system)
        XCTAssertTrue(localized.request.system.hasPrefix(QuickSummaryContext.instructions))
        let manual = try QuickSummaryContext.manualRequest(source: "You: Sarah confirms Monday.",
                                                           responseLanguage: "Simplified Chinese")
        XCTAssertTrue(manual.system.contains("Simplified Chinese"))
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
        XCTAssertEqual(recovered, "You: " + original)
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
}
