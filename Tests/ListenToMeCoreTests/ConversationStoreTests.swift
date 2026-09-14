import XCTest
@testable import ListenToMeCore

final class ConversationStoreTests: XCTestCase {
    private func seg(_ text: String, final: Bool, source: SpeakerSource = .others) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: final, start: 0, end: 1)
    }

    func testPartialDoesNotAppend() {
        let store = ConversationStore()
        store.apply(seg("typing", final: false))
        XCTAssertTrue(store.utterances.isEmpty)
        XCTAssertEqual(store.partial?.text, "typing")
    }

    func testFinalAppendsAndClearsPartial() {
        let store = ConversationStore()
        store.apply(seg("typing", final: false))
        store.apply(seg("done", final: true))
        XCTAssertEqual(store.utterances.map(\.text), ["done"])
        XCTAssertNil(store.partial)
    }

    func testRecentContextRespectsCharBudget() {
        let store = ConversationStore()
        store.apply(seg("aaaa", final: true))
        store.apply(seg("bbbb", final: true))
        store.apply(seg("cccc", final: true))
        // Each segment costs what it costs in the prompt: "Others: cccc" plus the joining newline.
        let perSegment = "Others: cccc\n".count
        XCTAssertEqual(TranscriptSegment.promptCharacterCost(store.utterances[0]), perSegment)
        let recent = store.recentContext(maxChars: perSegment * 2 + 1)
        XCTAssertEqual(recent.map(\.text), ["bbbb", "cccc"])
    }

    /// The speaker label is charged, so a budget that would fit the raw text alone does not fit the
    /// rendered line (issue #119 — hundreds of short labeled lines used to overrun a small window).
    func testRecentContextChargesTheSpeakerLabel() {
        let store = ConversationStore()
        store.apply(seg("aaaa", final: true))
        store.apply(seg("bbbb", final: true))
        XCTAssertEqual(store.recentContext(maxChars: 9).map(\.text), ["bbbb"])
    }

    func testRecentContextKeepsAtLeastOne() {
        let store = ConversationStore()
        store.apply(seg("a very long final utterance", final: true))
        XCTAssertEqual(store.recentContext(maxChars: 1).count, 1)
    }
}
