import XCTest
@testable import ListenToMeCore

final class LocalOllamaReadinessTests: XCTestCase {
    func testFailedCatalogIsNotAnEmptyInstallation() {
        let unavailable = LocalOllamaReadiness(installed: nil)
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertFalse(unavailable.needsModel)
        XCTAssertEqual(unavailable.label(for: "pinned"), "pinned (not verified)")
        let empty = LocalOllamaReadiness(installed: [])
        XCTAssertEqual(empty.status, .noModels)
        XCTAssertTrue(empty.needsModel)
        XCTAssertEqual(empty.label(for: "pinned"), "pinned (not installed)")
    }
    func testCapabilityFailureDoesNotRecommendReplacingAnInstalledModel() {
        let unknown = LocalOllamaReadiness(installed: ["pinned"], unverified: ["pinned"])
        XCTAssertEqual(unknown.status, .unverified)
        XCTAssertFalse(unknown.needsModel)
        XCTAssertEqual(unknown.label(for: "pinned"), "pinned (not verified)")
        let embeddingsOnly = LocalOllamaReadiness(installed: ["embedding"])
        XCTAssertEqual(embeddingsOnly.status, .noChatModels)
        XCTAssertTrue(embeddingsOnly.needsModel)
        XCTAssertEqual(embeddingsOnly.label(for: "embedding"), "embedding (not a local chat model)")
    }
    func testUsableChatModelRemainsReadyWhileOtherProbesFail() {
        let mixed = LocalOllamaReadiness(installed: ["chat", "uncertain"], available: ["chat"], unverified: ["uncertain"])
        XCTAssertEqual(mixed.status, .ready)
        XCTAssertTrue(mixed.message.contains("1 other model(s) could not be verified"))
        XCTAssertEqual(mixed.label(for: "chat"), "chat")
        XCTAssertEqual(mixed.label(for: "uncertain"), "uncertain (not verified)")
        XCTAssertEqual(mixed.label(for: "missing"), "missing (not installed)")
        XCTAssertFalse(mixed.needsModel)
    }
}
