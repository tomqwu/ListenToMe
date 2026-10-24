import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Cloud AI presets on iOS (issue #214): opt-in only, one key per vendor bound to that vendor,
/// per-vendor model choices that are never auto-assigned, and Auto gated on the Quick contract.
@MainActor
final class MobileCloudAISettingsTests: XCTestCase {
    private var keys: [String] {
        var keys = ["mobileAIProvider", "mobileCloudAIVendor", "mobileCloudAIQuickContractFailures"]
        for id in CloudAIPreset.ID.allCases {
            keys += ["catalog", "keyOrigin"].map { "mobileCloudAI.\(id.rawValue).\($0)" }
            keys += MobileSummaryMode.allCases.map { "mobileCloudAI.\(id.rawValue).\($0.rawValue)Model" }
        }
        return keys
    }
    private var saved: [String: Any] = [:]
    private var savedKeys: [CloudAIPreset.ID: String] = [:]

    override func setUp() async throws {
        saved = [:]
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        for preset in CloudAIPreset.all {
            savedKeys[preset.id] = try MobileKeychain.read(account: preset.keychainAccount)
            try MobileKeychain.save("", account: preset.keychainAccount)
        }
    }

    override func tearDown() async throws {
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
        for preset in CloudAIPreset.all { try MobileKeychain.save(savedKeys[preset.id] ?? "", account: preset.keychainAccount) }
        OpenAIModelsStub.reply = nil
    }

    func testNothingIsSelectedByDefaultAndChoosingAServiceSelectsOnlyThatService() {
        let settings = MobileAISettings()
        XCTAssertNotEqual(settings.provider, .cloud, "A fresh install never starts on a cloud service")
        XCTAssertNil(settings.cloud.vendor)
        XCTAssertEqual(settings.cloud.providerLabel, "Cloud AI")
        settings.selectSummaryRoute(.cloud(.anthropic))
        XCTAssertEqual(settings.provider, .cloud)
        XCTAssertEqual(settings.summaryRoute, .cloud(.anthropic))
        XCTAssertEqual(settings.cloud.providerLabel, "Cloud AI · Anthropic Claude")
        XCTAssertEqual(settings.summaryEndpointLabel, "Anthropic (api.anthropic.com)")
        for mode in MobileSummaryMode.allCases {
            XCTAssertEqual(settings.selectedModel(for: mode), "", "No model is ever chosen for the user")
        }
        XCTAssertEqual(settings.availability(for: .summary), "Add your Anthropic API key in Settings.")
        XCTAssertFalse(settings.canRefreshSummaryModelsAutomatically, "Nothing is fetched before a key exists")
        let relaunched = MobileAISettings()
        XCTAssertEqual(relaunched.summaryRoute, .cloud(.anthropic), "The choice survives relaunch")
        settings.selectSummaryRoute(.apple)
        XCTAssertEqual(MobileAISettings().provider, .apple)
    }

    func testEachVendorKeepsItsOwnKeyAndModels() throws {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.openAI))
        XCTAssertTrue(settings.saveCloudKey("sk-openai-synthetic"))
        settings.selectModel("gpt-model", for: .summary)
        settings.selectSummaryRoute(.cloud(.anthropic))
        XCTAssertFalse(settings.cloud.hasKey, "Another vendor's key is never reused")
        XCTAssertEqual(settings.selectedModel(for: .summary), "")
        XCTAssertTrue(settings.saveCloudKey("sk-ant-synthetic"))
        XCTAssertEqual(try settings.cloud.currentKey(for: .anthropic), "sk-ant-synthetic")
        XCTAssertEqual(try settings.cloud.currentKey(for: .openAI), "sk-openai-synthetic", "Switching keeps each key")
        settings.selectSummaryRoute(.cloud(.openAI))
        XCTAssertEqual(settings.selectedModel(for: .summary), "gpt-model", "Switching back restores the choice")
        XCTAssertTrue(settings.saveCloudKey(""))
        XCTAssertEqual(try settings.cloud.currentKey(for: .openAI), "")
        XCTAssertEqual(try settings.cloud.currentKey(for: .anthropic), "sk-ant-synthetic")
    }

    func testAKeyIsOnlyReturnedForTheOriginItWasSavedFor() throws {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.groq))
        XCTAssertTrue(settings.saveCloudKey("gsk-synthetic"))
        UserDefaults.standard.set("https://elsewhere.example:443", forKey: "mobileCloudAI.groq.keyOrigin")
        XCTAssertEqual(try settings.cloud.currentKey(for: .groq), "", "A mismatched origin sends no credential")
        XCTAssertFalse(MobileAISettings().cloud.hasKey)
    }

    func testRefreshListsModelsButNeverPicksOne() async throws {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.anthropic))
        XCTAssertTrue(settings.saveCloudKey("sk-ant-synthetic"))
        XCTAssertTrue(settings.canRefreshSummaryModelsAutomatically)
        OpenAIModelsStub.reply = #"{"data":[{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}]}"#
        let count = try await settings.cloud.refresh(session: OpenAIModelsStub.session())
        XCTAssertEqual(count, 1)
        XCTAssertEqual(settings.models(for: .quick).map(\.name), ["claude-opus-5-5"])
        for mode in MobileSummaryMode.allCases {
            XCTAssertEqual(settings.selectedModel(for: mode), "", "Even a single listed model is not assigned")
        }
        XCTAssertEqual(settings.cloud.preset?.suggestions(in: settings.cloud.models), ["claude-opus-5-5"])
        settings.selectModel("claude-opus-5-5", for: .summary)
        XCTAssertNil(settings.availability(for: .summary))
        XCTAssertTrue(try settings.client(for: .summary) is AnthropicProvider)
        settings.selectModel("claude-retired", for: .quick)
        XCTAssertEqual(settings.availability(for: .quick),
                       "Anthropic no longer lists the selected model. Choose another model in Settings.")
    }

    func testAutoPausesPerVendorAndModelAfterAFailedContract() {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.mistral))
        settings.selectModel("small", for: .quick)
        XCTAssertNil(settings.automaticQuickReason)
        settings.cloud.recordContract(model: "small", passed: false)
        XCTAssertEqual(settings.automaticQuickReason, "small did not follow the Quick Summary format. "
                       + "Choose another Quick model or test it again in Settings.")
        settings.selectSummaryRoute(.cloud(.groq))
        settings.selectModel("small", for: .quick)
        XCTAssertNil(settings.automaticQuickReason, "The same model ID at another vendor starts fresh")
        settings.selectSummaryRoute(.cloud(.mistral))
        XCTAssertNotNil(MobileAISettings().automaticQuickReason, "The result survives relaunch")
        settings.cloud.recordContract(model: "small", passed: true)
        XCTAssertNil(settings.automaticQuickReason)
    }

    /// #218 review: a key typed while OpenAI was selected is never stored as, or sent to, OpenRouter.
    func testAKeyTypedForOneServiceIsNeverSavedForAnother() throws {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.openAI))
        settings.selectSummaryRoute(.cloud(.openRouter))
        XCTAssertFalse(settings.saveCloudKey("sk-openai-synthetic", typedFor: .openAI))
        XCTAssertTrue(settings.status?.contains("typed for OpenAI") == true, settings.status ?? "")
        XCTAssertEqual(try settings.cloud.currentKey(for: .openRouter), "")
        XCTAssertEqual(try settings.cloud.currentKey(for: .openAI), "")
        XCTAssertTrue(settings.saveCloudKey("sk-or-synthetic", typedFor: .openRouter))
        XCTAssertEqual(try settings.cloud.currentKey(for: .openRouter), "sk-or-synthetic")
    }

    /// #218 review: a test that finishes after the user switched services is recorded for the
    /// service and model that were tested.
    func testAContractResultIsRecordedForTheTestedServiceAndModel() {
        let settings = MobileAISettings()
        settings.selectSummaryRoute(.cloud(.groq))
        settings.selectModel("small", for: .quick)
        settings.selectSummaryRoute(.cloud(.mistral))
        settings.selectModel("small", for: .quick)
        settings.cloud.recordContract(model: "small", passed: false, vendor: .groq)
        XCTAssertNil(settings.automaticQuickReason, "Mistral was not the service tested")
        settings.selectSummaryRoute(.cloud(.groq))
        XCTAssertNotNil(settings.automaticQuickReason)
    }

    func testAMissingServiceFallsBackToTheDeviceDefault() {
        UserDefaults.standard.set("cloud", forKey: "mobileAIProvider")
        let settings = MobileAISettings()
        XCTAssertNotEqual(settings.provider, .cloud, "Never a cloud route with no service chosen")
    }
}
