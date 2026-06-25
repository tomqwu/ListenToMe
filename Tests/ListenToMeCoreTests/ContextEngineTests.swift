import XCTest
@testable import ListenToMeCore

final class ContextEngineTests: XCTestCase {
    private func finalSeg(_ text: String, _ source: SpeakerSource) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: 0, end: 1)
    }

    func testBuildContextPullsRecentAndNotes() {
        let store = ConversationStore()
        store.apply(finalSeg("hello there", .others))
        let engine = ContextEngine(debounce: 5)
        let ctx = engine.buildContext(from: store, notes: "my notes", maxChars: 4000)
        XCTAssertEqual(ctx.messages.map(\.text), ["hello there"])
        XCTAssertEqual(ctx.notes, "my notes")
    }

    func testBuildContextIncludesTrimmedSummary() {
        let store = ConversationStore()
        store.apply(finalSeg("hello there", .others))
        let engine = ContextEngine(debounce: 5)
        let ctx = engine.buildContext(from: store, notes: nil, summary: "  rolling summary  ")
        XCTAssertEqual(ctx.summary, "rolling summary")
    }

    func testBuildContextSummaryNilWhenEmpty() {
        let store = ConversationStore()
        let engine = ContextEngine(debounce: 5)
        XCTAssertNil(engine.buildContext(from: store, notes: nil, summary: "   ").summary)
        XCTAssertNil(engine.buildContext(from: store, notes: nil).summary)
    }

    func testBuildContextIncludesTrimmedPersonaGuidance() {
        let store = ConversationStore()
        let engine = ContextEngine(debounce: 5)
        let ctx = engine.buildContext(from: store, notes: nil, personaGuidance: "  interview  ")
        XCTAssertEqual(ctx.personaGuidance, "interview")
    }

    func testBuildContextPersonaNilWhenEmpty() {
        let store = ConversationStore()
        let engine = ContextEngine(debounce: 5)
        XCTAssertNil(engine.buildContext(from: store, notes: nil, personaGuidance: "  ").personaGuidance)
        XCTAssertNil(engine.buildContext(from: store, notes: nil).personaGuidance)
    }

    func testProactiveFiresForOthersQuestion() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("what is the ETA?", .others), now: 0))
    }

    func testProactiveIgnoresYou() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("what is the ETA?", .you), now: 0))
    }

    func testProactiveIgnoresNonQuestion() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("we are done.", .others), now: 0))
    }

    func testProactiveIgnoresPartial() {
        var engine = ContextEngine(debounce: 5)
        let partial = TranscriptSegment(source: .others, text: "what now?", isFinal: false, start: 0, end: 1)
        XCTAssertFalse(engine.shouldFireProactive(for: partial, now: 0))
    }

    func testProactiveDebounced() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("q1?", .others), now: 0))
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("q2?", .others), now: 3))   // within debounce
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("q3?", .others), now: 6))    // past debounce
    }
}
