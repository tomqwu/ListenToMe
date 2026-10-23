import XCTest
@testable import ListenToMeCore

/// Address validation and honest classification for OpenAI-compatible servers (issue #52).
final class OpenAICompatibleEndpointTests: XCTestCase {
    private func normalized(_ raw: String) throws -> String {
        try OpenAICompatibleEndpoint.normalize(raw).absoluteString
    }

    func testCommonServersNormalizeToTheirAPIBase() throws {
        XCTAssertEqual(try normalized("http://localhost:1234"), "http://localhost:1234/v1")
        XCTAssertEqual(try normalized("  http://Studio.LOCAL:1234/v1/ "), "http://studio.local:1234/v1")
        XCTAssertEqual(try normalized("https://openrouter.ai/api/v1"), "https://openrouter.ai/api/v1")
        XCTAssertEqual(try normalized("http://127.0.0.1:8000/v1/chat/completions"), "http://127.0.0.1:8000/v1")
        XCTAssertEqual(try normalized("https://example.com/openai/v1/models"), "https://example.com/openai/v1")
        XCTAssertEqual(try normalized("http://[::1]:11434"), "http://[::1]:11434/v1")
        XCTAssertEqual(try normalized("https://192.168.1.20:8443/v1"), "https://192.168.1.20:8443/v1")
    }

    func testInvalidAddressesAreRejectedWithAReason() {
        let cases: [(String, OpenAICompatibleEndpoint.ValidationError)] = [
            ("", .empty), ("   ", .empty),
            ("localhost:1234/v1", .invalid), ("ftp://host/v1", .invalid), ("https://", .invalid), ("not a url", .invalid),
            ("https://user:pass@openrouter.ai/api/v1", .credentialsInURL),
            ("https://openrouter.ai/api/v1?key=sk-1", .queryInURL), ("https://host/v1#frag", .queryInURL),
            ("http://192.168.1.20:1234/v1", .plainHTTP(host: "192.168.1.20")),
            ("http://10.0.0.5:8000", .plainHTTP(host: "10.0.0.5")),
            ("http://100.101.102.103:1234", .plainHTTP(host: "100.101.102.103")),
            ("http://openrouter.ai/api/v1", .plainHTTP(host: "openrouter.ai")),
            ("http://studio:1234", .plainHTTP(host: "studio")),
            ("http://[fd00::1]:1234", .plainHTTP(host: "[fd00::1]"))
        ]
        for (raw, expected) in cases {
            XCTAssertThrowsError(try OpenAICompatibleEndpoint.normalize(raw), raw) { error in
                guard let validation = error as? OpenAICompatibleEndpoint.ValidationError else {
                    return XCTFail("Unexpected \(error) for \(raw)")
                }
                if case .plainHTTP = expected, case .plainHTTP = validation {} else {
                    XCTAssertEqual(validation, expected, raw)
                }
                XCTAssertFalse((validation.errorDescription ?? "").isEmpty, raw)
            }
        }
    }

    func testPlainHTTPIsLimitedToTheATSLocalNetworkingExemption() {
        for host in ["localhost", "LOCALHOST", "studio.local", "127.0.0.1", "127.8.9.10", "169.254.3.4", "::1", "[::1]", "fe80::1"] {
            XCTAssertTrue(OpenAICompatibleEndpoint.allowsPlainHTTP(host: host), host)
        }
        for host in ["192.168.1.2", "10.1.1.1", "172.16.0.1", "8.8.8.8", "fd00::1", "2001:db8::1", "studio", "example.com", "1.2.3"] {
            XCTAssertFalse(OpenAICompatibleEndpoint.allowsPlainHTTP(host: host), host)
        }
    }

    func testReachIsAboutTheAddressAndNeverClaimsLocalInference() throws {
        let expectations: [(String, OpenAICompatibleEndpoint.Reach)] = [
            ("http://localhost:1234/v1", .loopback), ("http://127.0.0.1:1234/v1", .loopback), ("http://[::1]:1/v1", .loopback),
            ("http://studio.local:1234/v1", .privateNetwork), ("https://192.168.1.2/v1", .privateNetwork),
            ("https://10.0.0.2/v1", .privateNetwork), ("https://172.20.0.2/v1", .privateNetwork),
            ("https://172.32.0.2/v1", .internet), ("https://169.254.1.1/v1", .privateNetwork),
            ("https://[fd12::1]/v1", .privateNetwork), ("https://[fe80::1]/v1", .privateNetwork),
            ("https://[2001:db8::1]/v1", .internet), ("https://100.64.0.1/v1", .internet),
            ("https://openrouter.ai/api/v1", .internet), ("https://studio/v1", .internet)
        ]
        for (raw, reach) in expectations {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(OpenAICompatibleEndpoint.reach(of: url), reach, raw)
            let label = OpenAICompatibleEndpoint.destinationLabel(url)
            let note = OpenAICompatibleEndpoint.privacyNote(url)
            XCTAssertFalse(label.lowercased().contains("on-device") || note.lowercased().contains("on-device"), raw)
            if reach.isUsersOwnServer {
                XCTAssertTrue(label.hasPrefix("your server at "), label)
                XCTAssertTrue(note.contains("cannot verify"), note)
            } else {
                XCTAssertTrue(label.hasSuffix("(may leave this device)"), label)
                XCTAssertTrue(note.contains("may leave this device"), note)
            }
        }
    }

    func testOriginsBindKeysToSchemeHostAndPort() throws {
        func origin(_ raw: String) throws -> String { OpenAICompatibleEndpoint.origin(of: try XCTUnwrap(URL(string: raw))) }
        XCTAssertEqual(try origin("https://OpenRouter.ai/api/v1"), "https://openrouter.ai:443")
        XCTAssertEqual(try origin("http://studio.local/v1"), "http://studio.local:80")
        XCTAssertEqual(try origin("https://openrouter.ai/api/v1"), try origin("https://openrouter.ai:443/other"))
        XCTAssertNotEqual(try origin("https://openrouter.ai/api/v1"), try origin("https://openrouter.ai.evil.example/api/v1"))
        XCTAssertNotEqual(try origin("http://studio.local:1234/v1"), try origin("http://studio.local:1235/v1"))
        XCTAssertEqual(OpenAICompatibleEndpoint.hostLabel(try XCTUnwrap(URL(string: "http://[::1]:8080/v1"))), "[::1]:8080")
        XCTAssertEqual(OpenAICompatibleEndpoint.hostLabel(try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1"))), "openrouter.ai")
    }

    func testRequestPathsHangOffTheBase() throws {
        let base = try OpenAICompatibleEndpoint.normalize("https://openrouter.ai/api/v1")
        XCTAssertEqual(OpenAICompatibleEndpoint.chatURL(base).absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(OpenAICompatibleEndpoint.modelsURL(base).absoluteString, "https://openrouter.ai/api/v1/models")
    }
}

/// `/v1/models` discovery against a stubbed URLProtocol.
final class OpenAICompatibleCatalogTests: XCTestCase {
    private let base = URL(string: "https://openrouter.ai/api/v1")!

    override func tearDown() {
        OpenAIStubProtocol.reset()
        super.tearDown()
    }

    func testParsesUniqueIDsInStableOrderAndSkipsJunk() throws {
        let body = #"{"object":"list","data":[{"id":"qwen3-14b"},{"id":"qwen3-8b"},{"id":"qwen3-8b"},{"id":""},"#
            + #"{"id":"bad\u0007id"},{"name":"no id"},{"id":"Llama-3.1-8B"}]}"#
        XCTAssertEqual(try OpenAICompatibleCatalog.parse(Data(body.utf8)), ["Llama-3.1-8B", "qwen3-8b", "qwen3-14b"])
        XCTAssertEqual(try OpenAICompatibleCatalog.parse(Data(#"{"data":[]}"#.utf8)), [])
    }

    func testNonListsAndErrorBodiesThrow() {
        XCTAssertThrowsError(try OpenAICompatibleCatalog.parse(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? OpenAICompatibleError, .invalidModelList)
        }
        XCTAssertThrowsError(try OpenAICompatibleCatalog.parse(Data(#"{"models":[]}"#.utf8))) {
            XCTAssertEqual($0 as? OpenAICompatibleError, .invalidModelList)
        }
        XCTAssertThrowsError(try OpenAICompatibleCatalog.parse(Data(#"{"error":{"message":"No auth"}}"#.utf8))) {
            XCTAssertEqual($0 as? OpenAICompatibleError, .server("No auth"))
        }
    }

    func testTheModelListIsCapped() throws {
        let entries = (0..<(OpenAICompatibleCatalog.maximumModels + 50)).map { #"{"id":"m\#($0)"}"# }
        let body = #"{"data":["# + entries.joined(separator: ",") + "]}"
        XCTAssertEqual(try OpenAICompatibleCatalog.parse(Data(body.utf8)).count, OpenAICompatibleCatalog.maximumModels)
        XCTAssertFalse(OpenAICompatibleCatalog.isPlausibleID(String(repeating: "a", count: 257)))
    }

    func testFetchSendsTheKeyOnlyToTheBaseAndRefusesRedirects() async throws {
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"data":[{"id":"m1"}]}"#.utf8))
        }
        let catalog = OpenAICompatibleCatalog(session: OpenAIStubProtocol.session())
        let models = try await catalog.fetch(baseURL: base, apiKey: "sk-or-key-1")
        XCTAssertEqual(models, ["m1"])
        let sent = try XCTUnwrap(OpenAIStubProtocol.received.first?.request)
        XCTAssertEqual(sent.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-key-1")
        XCTAssertEqual(sent.httpMethod, "GET")

        OpenAIStubProtocol.received = []
        OpenAIStubProtocol.reply = { _ in .redirect(status: 302, location: "https://elsewhere.example/v1/models") }
        do {
            _ = try await catalog.fetch(baseURL: base, apiKey: "sk-or-key-1")
            XCTFail("A redirect must not be followed")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .redirected(status: 302, location: "elsewhere.example"))
        }
        XCTAssertEqual(OpenAIStubProtocol.received.count, 1)
    }

    func testFetchFailuresAreTypedAndBounded() async throws {
        let catalog = OpenAICompatibleCatalog(session: OpenAIStubProtocol.session())
        OpenAIStubProtocol.reply = { _ in .response(status: 401, headers: [:], body: Data(#"{"error":"bad key sk-zzzz"}"#.utf8)) }
        do {
            _ = try await catalog.fetch(baseURL: base, apiKey: "sk-zzzz")
            XCTFail("401 must throw")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .http(status: 401, detail: "bad key [API key]"))
        }
        OpenAIStubProtocol.reply = { _ in .failure(.cannotFindHost) }
        do {
            _ = try await catalog.fetch(baseURL: base, apiKey: nil)
            XCTFail("DNS failure must throw")
        } catch {
            guard case .unreachable(host: "openrouter.ai", _) = error as? OpenAICompatibleError else { return XCTFail("\(error)") }
        }
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: [:], body: Data(repeating: 0x20, count: OpenAICompatibleCatalog.maximumBytes + 1))
        }
        do {
            _ = try await catalog.fetch(baseURL: base, apiKey: nil)
            XCTFail("An oversized list must throw")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .tooLarge)
        }
    }
}
