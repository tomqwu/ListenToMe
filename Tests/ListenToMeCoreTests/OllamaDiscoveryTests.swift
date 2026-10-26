import XCTest
@testable import ListenToMeCore

final class OllamaDiscoveryTests: XCTestCase {
    func testIncompleteProbesAreUnknownRatherThanNotChatCapable() {
        for text in ["not json", "{}", #"{"capabilities":["completion"]}"#] {
            XCTAssertEqual(OllamaModelCapability(metadata: Data(text.utf8), localOnly: true).status, .unverified)
        }
        XCTAssertEqual(OllamaModelCapability().status, .unverified, "Transport failures use the unknown default")
    }

    func testVerifiedLocalAndExplicitlyRemoteModelsRemainDistinct() {
        let local = #"{"capabilities":["completion"],"details":{"format":"gguf"},"model_info":{"a":1}}"#
        let localResult = OllamaModelCapability(metadata: Data(local.utf8), localOnly: true)
        XCTAssertTrue(localResult.chatCapable); XCTAssertTrue(localResult.verifiedLocal)
        let remote = #"{"capabilities":["completion"],"remote_host":"https://ollama.com"}"#
        XCTAssertEqual(OllamaModelCapability(metadata: Data(remote.utf8), localOnly: true).status, .notChat)
        XCTAssertEqual(OllamaModelCapability(metadata: Data(remote.utf8), localOnly: false).status, .chat)
        XCTAssertEqual(OllamaModelCapability(metadata: Data(#"{"capabilities":["embedding"]}"#.utf8),
                                            localOnly: true).status, .notChat)
    }

    func testPinnedChoiceDoesNotSwitchToFallbackOnAnUnknownProbe() {
        let unknown = PaneModelHealing.decide(current: "pinned", pinned: true, available: ["other"],
                                              fallback: "other", autoAssign: true, verificationUncertain: true)
        XCTAssertEqual(unknown, .init(model: "pinned", persist: false))
        let absent = PaneModelHealing.decide(current: "pinned", pinned: true, available: ["other"],
                                             fallback: "other", autoAssign: true)
        XCTAssertEqual(absent, .init(model: "other", persist: false))
        let compatible = PaneModelHealing.decide(current: "pinned", pinned: true, available: ["other"],
                                                 fallback: "other", autoAssign: false, verificationUncertain: true)
        XCTAssertEqual(compatible, .init(model: "", persist: false), "Custom catalogs still never auto-select a model")
    }
}
