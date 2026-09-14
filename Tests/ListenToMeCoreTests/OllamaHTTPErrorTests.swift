import XCTest
@testable import ListenToMeCore

/// Issue #118: a non-2xx Ollama response must surface the server's own explanation, and cloud
/// auth/quota failures must not be reported as "is the server running and the model pulled?".
final class OllamaHTTPErrorTests: XCTestCase {

    private func message(_ status: Int, _ body: String) -> String {
        OllamaStreamError.fromHTTP(status: status, body: Data(body.utf8)).localizedDescription
    }

    func testServerErrorBodyIsSurfaced() {
        let text = message(400, #"{"error":"unknown option for this model"}"#)
        XCTAssertTrue(text.contains("HTTP 400"), text)
        XCTAssertTrue(text.contains("unknown option"), text)
    }

    func testNestedErrorObjectMessageIsSurfaced() {
        XCTAssertTrue(message(400, #"{"error":{"message":"bad request"}}"#).contains("bad request"))
    }

    func testUnauthorizedReadsAsRejectedKeyNotMissingModel() {
        for status in [401, 403] {
            let text = message(status, #"{"error":"invalid api key"}"#)
            XCTAssertTrue(text.contains("HTTP \(status)"), text)
            XCTAssertTrue(text.lowercased().contains("api key"), text)
            XCTAssertFalse(text.contains("model pulled"), text)
            XCTAssertTrue(text.contains("invalid api key"), text)
        }
    }

    func testRateLimitReadsAsQuotaNotMissingModel() {
        let text = message(429, "")
        XCTAssertTrue(text.contains("HTTP 429"), text)
        XCTAssertTrue(text.lowercased().contains("rate"), text)
        XCTAssertFalse(text.contains("model pulled"), text)
    }

    func testNotFoundKeepsTheModelHint() {
        XCTAssertTrue(message(404, "").lowercased().contains("model"))
    }

    func testPlainTextBodyIsUsedWhenNotJSON() {
        XCTAssertTrue(message(502, "upstream gateway exploded").contains("upstream gateway exploded"))
    }

    func testEmptyBodyStillProducesAStatusMessage() {
        let text = message(500, "")
        XCTAssertTrue(text.contains("HTTP 500"), text)
        XCTAssertFalse(text.isEmpty)
    }

    func testBodyIsBoundedSoAHugeErrorPageCannotFloodThePane() {
        let text = message(500, String(repeating: "x", count: 200_000))
        XCTAssertLessThanOrEqual(text.count, OllamaStreamError.maximumErrorBodyBytes + 200)
    }

    func testConnectionFailureKeepsTheServerRunningHint() {
        let text = OllamaStreamError.unreachable("Could not connect to the server.").localizedDescription
        XCTAssertTrue(text.contains("Could not connect to the server."), text)
        XCTAssertTrue(text.contains("running"), text)
    }
}
