import XCTest
@testable import ListenToMeCore

final class OpenAIModelParsingTests: XCTestCase {
    func testParsesIdsFromDataArray() {
        let json = #"{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"llama-3.1-8b"}]}"#
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data(json.utf8)), ["gpt-4o", "llama-3.1-8b"])
    }

    func testEmptyOnMissingDataKey() {
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data(#"{"object":"list"}"#.utf8)), [])
    }

    func testEmptyOnGarbage() {
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data("not json".utf8)), [])
    }
}
