import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileAICapabilityTests: XCTestCase {
    private var previous: [String: Any] = [:]
    private func relevant(_ key: String) -> Bool { key.hasPrefix("mobile") || key == "autoQuickSummary" }
    override func setUp() async throws {
        previous = UserDefaults.standard.dictionaryRepresentation().filter { relevant($0.key) }
        UserDefaults.standard.set("ollama", forKey: "mobileAIProvider")
        UserDefaults.standard.removeObject(forKey: "mobileCloudAIVendor")
        UserDefaults.standard.set(false, forKey: "mobileIdentifySpeakers")
        UserDefaults.standard.set(false, forKey: "autoQuickSummary")
    }
    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where relevant(key) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in previous { UserDefaults.standard.set(value, forKey: key) }
    }

    func testIdleAutoExplainsUnavailableProviderWithoutChangingSavedChoice() throws {
        UserDefaults.standard.set("apple", forKey: "mobileAIProvider")
        let ai = MobileAISettings(appleAvailability: { nil })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, ai: ai)
        let reason = try XCTUnwrap(session.automaticQuickAvailability)
        XCTAssertTrue(reason.contains("cloud AI"), "Name all supported provider categories, not only Ollama")
        for enabled in [false, true] {
            session.autoQuick = enabled
            XCTAssertTrue(session.autoQuickStatus.contains(reason), session.autoQuickStatus)
            XCTAssertTrue(session.automaticReviewStatus(.summary).contains(reason))
            XCTAssertFalse(session.autoQuickStatus.contains("Checks new speech"))
            XCTAssertEqual(ai.provider, .apple)
            XCTAssertEqual(session.autoQuick, enabled, "Keep the preference; do not silently change providers or Auto")
            XCTAssertNil(session.generatingMode)
            XCTAssertEqual(session.state, .idle)
        }
    }

    func testUnavailableAppleSelectionKeepsExplicitProviderAndServerChoices() {
        let reason = "Apple Intelligence is unavailable on this device."
        let ai = MobileAISettings(appleAvailability: { reason })
        XCTAssertTrue(ai.saveBaseURL("http://test-mac.local:11434"))
        ai.model = "existing-model"
        ai.selectSummaryRoute(.apple)
        XCTAssertEqual(ai.provider, .ollama)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mobileAIProvider"), "ollama")
        XCTAssertEqual(ai.status, reason)
        XCTAssertEqual(ai.ollamaBaseURL, "http://test-mac.local:11434")
        XCTAssertEqual(ai.model, "existing-model")
        XCTAssertNil(ai.cloud.vendor, "Unavailable Apple must not silently select a cloud service")
    }

    func testSavedUnavailableAppleChoiceStaysSavedAndClientFailsWithRecoveryReason() throws {
        UserDefaults.standard.set("apple", forKey: "mobileAIProvider")
        let reason = "Apple Intelligence is still preparing its model."
        let ai = MobileAISettings(appleAvailability: { reason })
        XCTAssertEqual(ai.provider, .apple, "Do not silently migrate an existing choice to a remote provider")
        XCTAssertEqual(ai.availability(for: .summary), reason)
        XCTAssertThrowsError(try ai.client(for: .summary)) { error in
            XCTAssertEqual(error.localizedDescription, reason)
        }
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mobileAIProvider"), "apple")
        XCTAssertNil(ai.cloud.vendor)
    }

    func testRefreshedAvailabilityEnablesAppleAndBlocksItAgainWithoutChangingChoice() throws {
        var reason: String? = "The on-device model is preparing."
        let ai = MobileAISettings(appleAvailability: { reason })
        XCTAssertNotNil(ai.appleUnavailableReason)
        reason = nil
        ai.refreshAppleAvailability()
        XCTAssertNil(ai.appleUnavailableReason)
        ai.selectSummaryRoute(.apple)
        XCTAssertEqual(ai.provider, .apple)
        XCTAssertEqual(try ai.client().id, "apple-intelligence")
        reason = "Apple Intelligence was turned off."
        ai.refreshAppleAvailability()
        XCTAssertEqual(ai.appleUnavailableReason, reason)
        XCTAssertEqual(ai.provider, .apple)
        XCTAssertEqual(ai.availability, reason)
    }

    func testCheckAgainRefreshesAppleReadinessWithoutChangingTheSavedProvider() {
        var reason: String? = nil
        let ai = MobileAISettings(appleAvailability: { reason })
        ai.selectSummaryRoute(.apple)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = [MobileSession.languageKey, MobileLanguageDetection.automaticKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        let session = MobileSession(storageDirectory: root, ai: ai)
        session.languageChoice = "en-US"
        session.notes = "Summarize these notes."
        reason = "Apple Intelligence is preparing its model."
        ai.refreshAppleAvailability()
        XCTAssertEqual(session.summaryAvailability, reason)
        reason = nil
        session.recheckSummary(for: .summary)
        XCTAssertNil(ai.appleUnavailableReason)
        XCTAssertNil(session.summaryAvailability)
        XCTAssertEqual(session.message, "Ready to generate Summary.")
        XCTAssertEqual(ai.provider, .apple)
        XCTAssertNil(ai.cloud.vendor)
        XCTAssertNil(session.generatingMode, "Check again must not generate or send conversation text")
    }

    func testForegroundRefreshesCapabilityWithoutSelectingAProvider() async throws {
        var reason: String? = "Apple Intelligence is preparing."
        let ai = MobileAISettings(appleAvailability: { reason })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, sharedInbox: root.appendingPathComponent("Inbox"),
                                    watchInbox: WatchInbox(root: root.appendingPathComponent("WatchInbox")), ai: ai)
        reason = nil
        await session.handleScenePhase(.active)
        XCTAssertNil(ai.appleUnavailableReason)
        XCTAssertEqual(ai.provider, .ollama)
        XCTAssertNil(ai.cloud.vendor)
        XCTAssertEqual(session.state, .idle)
        await session.background()
    }
}
