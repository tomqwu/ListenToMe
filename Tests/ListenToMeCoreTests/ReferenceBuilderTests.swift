import XCTest
@testable import ListenToMeCore

final class ReferenceBuilderTests: XCTestCase {
    private func doc(_ name: String, _ content: String) -> ReferenceBuilder.Document {
        ReferenceBuilder.Document(name: name, content: content)
    }

    func testNilForNoDocumentsOrEmptyContent() {
        XCTAssertNil(ReferenceBuilder.build(documents: []))
        XCTAssertNil(ReferenceBuilder.build(documents: [doc("a.txt", "   \n  ")]))
    }

    func testJoinsDocumentsWithHeaders() {
        let out = ReferenceBuilder.build(documents: [doc("a.md", "alpha"), doc("b.md", "beta")])
        XCTAssertEqual(out, "### a.md\nalpha\n\n### b.md\nbeta")
    }

    func testSkipsEmptyDocumentsButKeepsOthers() {
        let out = ReferenceBuilder.build(documents: [doc("a.md", "  "), doc("b.md", "beta")])
        XCTAssertEqual(out, "### b.md\nbeta")
    }

    func testTruncatesWhenOverBudgetAndAppendsNotice() {
        let big = String(repeating: "x", count: 1000)
        let out = ReferenceBuilder.build(documents: [doc("big.txt", big)], maxChars: 400)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("### big.txt"))
        XCTAssertTrue(out!.contains("[reference material truncated"))
        XCTAssertLessThan(out!.count, 500)
    }

    func testStopsAddingDocumentsOnceBudgetExceeded() {
        // First doc fills the budget; the second is dropped (too small a remainder to partial-add).
        let out = ReferenceBuilder.build(
            documents: [doc("first.txt", String(repeating: "a", count: 300)),
                        doc("second.txt", "should not appear")],
            maxChars: 330)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("### first.txt"))
        XCTAssertFalse(out!.contains("second.txt"))
        XCTAssertTrue(out!.contains("[reference material truncated"))
    }
}
