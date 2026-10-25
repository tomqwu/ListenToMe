import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileOllamaEndpointTests: XCTestCase {
    func testHTTPAddressPolicyPreservesPreviousServerOnRejection() {
        let previous = UserDefaults.standard.object(forKey: "mobileOllamaBaseURL")
        defer { UserDefaults.standard.set(previous, forKey: "mobileOllamaBaseURL") }
        let settings = MobileAISettings()
        XCTAssertTrue(settings.saveBaseURL("http://studio.local:11434"))
        for host in ["192.168.1.10", "10.0.0.2", "172.16.0.3", "100.64.0.1", "100.127.255.254",
                     "8.8.8.8", "[fd00::1]", "[2001:db8::1]", "[::ffff:192.168.1.1]", "example.com"] {
            XCTAssertFalse(settings.saveBaseURL("http://\(host):11434"), host)
            XCTAssertEqual(settings.endpointDescription, "http://studio.local:11434", host)
            XCTAssertTrue(settings.status?.contains("Use https://") == true, host)
        }
        for host in ["localhost", "studio.local", "127.0.0.1", "127.255.1.2", "169.254.1.2",
                     "[::1]", "[fe80::1]", "[::ffff:127.0.0.1]"] {
            XCTAssertTrue(settings.saveBaseURL("http://\(host):11434"), host)
        }
        for host in ["192.168.1.10", "100.64.0.1", "8.8.8.8", "[fd00::1]", "[2001:db8::1]"] {
            XCTAssertTrue(settings.saveBaseURL("https://\(host):11434"), host)
        }
    }

    func testOmittedURLPartsAreExplainedWithoutEchoingSensitiveValues() {
        let previous = UserDefaults.standard.object(forKey: "mobileOllamaBaseURL")
        defer { UserDefaults.standard.set(previous, forKey: "mobileOllamaBaseURL") }
        let settings = MobileAISettings()
        for origin in ["https://studio.local:11434", "https://ollama.com"] {
            for suffix in ["/ollama", "?token=private-marker", "#private-marker"] {
                XCTAssertTrue(settings.saveBaseURL(origin + suffix))
                XCTAssertEqual(settings.endpointDescription, origin)
                XCTAssertTrue(settings.status?.contains("Only the scheme, host and port") == true)
                XCTAssertFalse(settings.status?.contains("private-marker") == true)
            }
            XCTAssertTrue(settings.saveBaseURL(origin + "/"))
            XCTAssertFalse(settings.status?.contains("not saved") == true)
        }
        XCTAssertTrue(settings.saveBaseURL("https://private-marker:private-marker@studio.local:11434/api"))
        XCTAssertEqual(settings.endpointDescription, "https://studio.local:11434")
        XCTAssertFalse(settings.status?.contains("private-marker") == true)
        XCTAssertTrue(settings.status?.contains("credentials are not saved") == true)
    }
}
