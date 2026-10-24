import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileModelRoleTests: XCTestCase {
    private let keys = ["mobileOllamaModel", "mobileOllamaQuickModel", "mobileOllamaDeepModel", "mobileOllamaCatalog"]
    private func withCleanPreferences(_ body: () throws -> Void) rethrows {
        var saved: [String: Any] = [:]
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try body()
    }
    private func cache(_ names: [String]) throws {
        let data = try JSONEncoder().encode(names.map { OllamaCloudModel(name: $0) })
        UserDefaults.standard.set(data.base64EncodedString(), forKey: "mobileOllamaCatalog")
    }
    func testLegacyFlashInheritanceKeepsQuickOnFlash() throws {
        try withCleanPreferences {
            try cache(["glm-5.3-flash", "glm-5.3", "deepseek-v4-pro:0813"])
            UserDefaults.standard.set("glm-5.3-flash", forKey: "mobileOllamaModel")
            let settings = MobileAISettings()
            XCTAssertEqual(settings.quickModel, "glm-5.3-flash")
            XCTAssertEqual(settings.model, "glm-5.3-flash")
        }
    }
    func testNewSetupAssignsFlashQuickAndFullSummary() throws {
        try withCleanPreferences {
            try cache(["glm-5.3-flash", "glm-5.3", "deepseek-v4-pro:0813"])
            let settings = MobileAISettings()
            XCTAssertEqual(settings.quickModel, "glm-5.3-flash")
            XCTAssertEqual(settings.model, "glm-5.3")
        }
    }
    /// Issue #235: iOS has Summary and Quick only. A Deep model an older build saved for Ollama, an
    /// OpenAI-compatible server or a cloud service is never read, never sent and never crashes.
    func testOldDeepModelDefaultsAreHarmless() throws {
        let legacy = ["mobileOpenAIDeepModel", "mobileCloudAI.anthropic.deepModel"]
        let saved = legacy.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(legacy, saved) { UserDefaults.standard.set(value, forKey: key) } }
        try withCleanPreferences {
            try cache(["glm-5.3-flash", "glm-5.3"])
            UserDefaults.standard.set("glm-5.3-flash", forKey: "mobileOllamaDeepModel")
            for key in legacy { UserDefaults.standard.set("legacy-deep", forKey: key) }
            XCTAssertEqual(MobileSummaryMode.allCases, [.summary, .quick])
            let settings = MobileAISettings()
            settings.hasKey = true
            XCTAssertEqual(settings.models(for: .summary).map(\.name), ["glm-5.3-flash", "glm-5.3"])
            for mode in MobileSummaryMode.allCases {
                XCTAssertNotEqual(settings.selectedModel(for: mode), "legacy-deep")
                XCTAssertNil(settings.availability(for: mode))
            }
            XCTAssertEqual(UserDefaults.standard.string(forKey: "mobileOllamaDeepModel"), "glm-5.3-flash",
                           "The old value is left alone, not rewritten")
        }
    }
}
