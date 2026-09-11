import XCTest
@testable import ListenToMeCore

final class OllamaCloudCatalogTests: XCTestCase {
    func testLiveAPICatalog() async throws {
        guard ProcessInfo.processInfo.environment["LTM_CLOUD_CATALOG"] == "1" else {
            throw XCTSkip("Opt-in live public catalog check")
        }
        let models = try await OllamaCloudCatalog().fetch(apiKey: "")
        XCTAssertFalse(models.isEmpty)
        let recent = OllamaCloudModel.recentVariants(in: models)
        XCTAssertEqual(Set(recent.map(\.family)), ["deepseek", "glm", "qwen", "kimi"])
        XCTAssertTrue(recent.allSatisfy { models.contains($0) })
        print("Live API model IDs: " + recent.map(\.name).joined(separator: ", "))
    }

    func testAPIModelIDsArePreservedAndDuplicatesRemoved() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://ollama.com/api/tags")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"models":[{"name":"deepseek-v99-pro:0911"},{"name":"qwen99-flash"},{"name":"qwen99-flash"},{"name":""}]}"#.utf8))
        }
        let result = try await OllamaCloudCatalog(session: session).fetch(apiKey: "synthetic-test-key")
        XCTAssertEqual(Set(result.map(\.name)), ["deepseek-v99-pro:0911", "qwen99-flash"])
    }

    func testCatalogHTTPAndMalformedDataFailInsteadOfPretendingNoModels() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        for (status, body) in [(401, "{}"), (500, "{}"), (200, "not json")] {
            StubURLProtocol.handler = { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            do {
                _ = try await OllamaCloudCatalog(session: session).fetch(apiKey: "")
                XCTFail("Expected failure for \(status): \(body)")
            } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testNewestPerFamilyAndVariantWithoutInventingMissingFlash() {
        let names = [
            OllamaCloudModel(name: "deepseek-v4-pro:0813", modifiedAt: "2026-08-13T08:00:00-07:00"),
            OllamaCloudModel(name: "deepseek-v4-flash:0731", modifiedAt: "2026-07-31T00:00:00Z"),
            OllamaCloudModel(name: "deepseek-v4.1-flash", modifiedAt: "2026-09-10T03:00:00Z"),
            OllamaCloudModel(name: "glm-5.2", modifiedAt: "2026-06-01T00:00:00Z"),
            OllamaCloudModel(name: "glm-5.3", modifiedAt: "2026-08-28T00:00:00Z"),
            OllamaCloudModel(name: "glm-5.3-flash", modifiedAt: "2026-08-26T00:00:00Z"),
            OllamaCloudModel(name: "qwen3.5:397b"),
            OllamaCloudModel(name: "kimi-k3"),
            OllamaCloudModel(name: "unrelated-pro")
        ]
        XCTAssertEqual(OllamaCloudModel.recentVariants(in: names).map(\.name),
                       ["deepseek-v4-pro:0813", "deepseek-v4.1-flash", "glm-5.3", "glm-5.3-flash", "qwen3.5:397b", "kimi-k3"])
    }

    func testOrderingUsesDateOffsetsFractionalSecondsAndNumericTieBreak() {
        let names = [
            OllamaCloudModel(name: "glm-9", modifiedAt: "invalid"),
            OllamaCloudModel(name: "glm-10"),
            OllamaCloudModel(name: "glm-a", modifiedAt: "2026-09-11T08:00:00-07:00"),
            OllamaCloudModel(name: "glm-b", modifiedAt: "2026-09-11T15:00:00.500Z"),
            OllamaCloudModel(name: "glm-c", modifiedAt: "2026-09-11T14:00:00Z")
        ]
        XCTAssertEqual(names.sorted(by: OllamaCloudModel.newer).map(\.name), ["glm-b", "glm-a", "glm-c", "glm-10", "glm-9"])
        XCTAssertEqual(OllamaCloudModel.recentVariants(in: []), [])
    }
}
