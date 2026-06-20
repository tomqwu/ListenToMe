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
        store.apply(seg("aaaa", final: true))   // 4 chars
        store.apply(seg("bbbb", final: true))   // 4 chars
        store.apply(seg("cccc", final: true))   // 4 chars
        // Budget 9: keep newest segments that fit (cccc=4, +bbbb=8 <= 9; +aaaa=12 > 9 stops).
        let recent = store.recentContext(maxChars: 9)
        XCTAssertEqual(recent.map(\.text), ["bbbb", "cccc"])
    }

    func testRecentContextKeepsAtLeastOne() {
        let store = ConversationStore()
        store.apply(seg("a very long final utterance", final: true))
        XCTAssertEqual(store.recentContext(maxChars: 1).count, 1)
    }
}
