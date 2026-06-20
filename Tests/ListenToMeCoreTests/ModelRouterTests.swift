import XCTest
@testable import ListenToMeCore

final class ModelRouterTests: XCTestCase {
    private func collect(_ router: ModelRouter) async throws -> String {
        var out = ""
        let req = LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])
        for try await delta in router.stream(req) { out += delta }
        return out
    }

    func testDefaultProviderIsActive() {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["a"]))
        XCTAssertEqual(router.activeID, "ollama")
    }

    func testStreamsFromActiveProvider() async throws {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["he", "llo"]))
        let out = try await collect(router)
        XCTAssertEqual(out, "hello")
    }

    func testSwitchingActiveProvider() async throws {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["x"]))
        router.register(MockLLMProvider(id: "claude", deltas: ["cl", "aude"]))
        router.setActive("claude")
        XCTAssertEqual(router.activeID, "claude")
        let out = try await collect(router)
        XCTAssertEqual(out, "claude")
    }

    func testSwitchingToUnknownProviderIsIgnored() {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["x"]))
        router.setActive("does-not-exist")
        XCTAssertEqual(router.activeID, "ollama")
    }
}
