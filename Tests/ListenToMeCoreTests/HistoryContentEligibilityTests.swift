import XCTest
@testable import ListenToMeCore

final class HistoryContentEligibilityTests: XCTestCase {
    func testUnhintedSingleWordQueriesRemainUnknownWithoutInstalledLexicalAssets() throws {
        for text in ["comida", "meal", "passport", "comida?"] {
            XCTAssertEqual(HistoryContentEligibility.evaluate(text, kind: .query), .unknown,
                           "A one-word language/POS guess cannot establish insufficient query content")
        }
    }
}
