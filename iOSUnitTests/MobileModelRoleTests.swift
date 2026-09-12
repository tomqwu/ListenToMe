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
    func testLegacyFlashInheritanceMigratesToFullModelAndPersists() throws {
        try withCleanPreferences {
            try cache(["glm-5.3-flash", "glm-5.3", "deepseek-v4-pro:0813"])
            UserDefaults.standard.set("glm-5.3-flash", forKey: "mobileOllamaModel")
            let settings = MobileAISettings()
            XCTAssertEqual(settings.quickModel, "glm-5.3-flash")
            XCTAssertEqual(settings.deepModel, "glm-5.3")
            XCTAssertEqual(MobileAISettings().deepModel, "glm-5.3")
            settings.selectModel("deepseek-v4-pro:0813", for: .deep)
            settings.resolveRoleModels()
            XCTAssertEqual(MobileAISettings().deepModel, "deepseek-v4-pro:0813")
        }
    }
    func testNewSetupAssignsFlashQuickFullSummaryAndProDeep() throws {
        try withCleanPreferences {
            try cache(["glm-5.3-flash", "glm-5.3", "deepseek-v4-pro:0813"])
            let settings = MobileAISettings()
            XCTAssertEqual(settings.quickModel, "glm-5.3-flash")
            XCTAssertEqual(settings.model, "glm-5.3")
            XCTAssertEqual(settings.deepModel, "deepseek-v4-pro:0813")
        }
    }
    func testFlashCannotBeSelectedOrSentForDeepAndNoFlashFallbackExists() throws {
        try withCleanPreferences {
            try cache(["glm-5.3-flash"])
            UserDefaults.standard.set("glm-5.3-flash", forKey: "mobileOllamaDeepModel")
            let settings = MobileAISettings()
            settings.hasKey = true
            XCTAssertEqual(settings.deepModel, "")
            XCTAssertTrue(settings.models(for: .deep).isEmpty)
            settings.selectModel("glm-5.3-flash", for: .deep)
            XCTAssertEqual(settings.deepModel, "")
            settings.deepModel = "GLM-5.3-FLASH"
            XCTAssertNotNil(settings.availability(for: .deep))
            XCTAssertThrowsError(try settings.client(for: .deep)) { error in
                XCTAssertTrue(error.localizedDescription.contains("Flash models cannot be used"))
            }
        }
    }
}
