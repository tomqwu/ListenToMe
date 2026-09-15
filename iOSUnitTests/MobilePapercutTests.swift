import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Covers issue #138: language persistence, long-lived transports, unauthenticated catalog
/// refreshes, on-disk protection and backup exclusion, and History search.
@MainActor
final class MobilePapercutTests: XCTestCase {
    private static let aiKeys = ["mobileAIProvider", "mobileOllamaBaseURL", "mobileOllamaModel",
                                 "mobileOllamaQuickModel", "mobileOllamaDeepModel", "mobileCorrectionModel",
                                 "mobileOllamaCatalog"]
    private var savedAI: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedAI = Self.aiKeys.reduce(into: [:]) { $0[$1] = UserDefaults.standard.object(forKey: $1) }
    }

    override func tearDown() {
        for key in Self.aiKeys { UserDefaults.standard.set(savedAI[key], forKey: key) }
        super.tearDown()
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: Transcription language

    func testChosenTranscriptionLanguageSurvivesRelaunch() {
        let previous = UserDefaults.standard.object(forKey: MobileSession.languageKey)
        defer { UserDefaults.standard.set(previous, forKey: MobileSession.languageKey) }
        UserDefaults.standard.removeObject(forKey: MobileSession.languageKey)
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        XCTAssertEqual(session.language, Locale.current.identifier, "Untouched means the device language")
        session.language = "zh-CN"
        XCTAssertEqual(MobileSession(storageDirectory: temporaryRoot()).language, "zh-CN",
                       "A chosen transcription language must not reset at every launch")
    }

    func testLanguagePickerDoesNotOfferTheSystemLanguageTwice() {
        XCTAssertFalse(MobileSession.selectableLanguages(system: Locale(identifier: "en_US")).contains("en-US"),
                       "en_US and en-US are the same language written two ways")
        XCTAssertTrue(MobileSession.selectableLanguages(system: Locale(identifier: "en_US")).contains("en-GB"))
        XCTAssertFalse(MobileSession.selectableLanguages(system: Locale(identifier: "zh_CN")).contains("zh-CN"))
        XCTAssertTrue(MobileSession.selectableLanguages(system: Locale(identifier: "zh_CN")).contains("zh-TW"))
        // A device language the app does not list leaves every offered entry available.
        XCTAssertEqual(MobileSession.selectableLanguages(system: Locale(identifier: "pt_BR")).count,
                       MobileSession.offeredLanguages.count)
    }

    // MARK: Request transports

    func testOneTransportIsReusedPerRoleAndRebuiltOnlyWhenTheDestinationChanges() {
        let transports = MobileTransports()
        let cloud = transports.session(for: MobileTransports.summary, identity: "https://ollama.com\u{1}key")
        XCTAssertTrue(transports.session(for: MobileTransports.summary, identity: "https://ollama.com\u{1}key") === cloud,
                      "Every summary and automatic Quick must reuse one session")
        XCTAssertEqual(transports.builtSessions, 1)
        let rekeyed = transports.session(for: MobileTransports.summary, identity: "https://ollama.com\u{1}other")
        XCTAssertFalse(rekeyed === cloud, "A new credential may not reuse the old connection")
        let correction = transports.session(for: MobileTransports.correction, identity: "https://ollama.com\u{1}other")
        XCTAssertFalse(correction === rekeyed, "Corrections keep their own short resource timeout")
        XCTAssertEqual(correction.configuration.timeoutIntervalForResource, 12)
        XCTAssertEqual(rekeyed.configuration.timeoutIntervalForResource, 480)
        XCTAssertEqual(transports.builtSessions, 3)
        transports.invalidateAll()
    }

    func testEveryRequestForOneEndpointSharesTheSameURLSession() throws {
        let settings = MobileAISettings()
        settings.models = [OllamaCloudModel(name: "glm-4.6-flash"), OllamaCloudModel(name: "glm-4.6")]
        settings.saveBaseURL("http://papercut-test.local:11434")
        settings.model = "glm-4.6"; settings.quickModel = "glm-4.6-flash"; settings.correctionModel = "glm-4.6-flash"
        defer { settings.saveBaseURL("") }
        _ = try settings.client(for: .summary)
        _ = try settings.client(for: .quick)
        _ = try settings.correctionClient()
        XCTAssertEqual(settings.transports.builtSessions, 2,
                       "Summaries share one session and corrections one, however many requests are made")
    }

    // MARK: Automatic catalog refresh

    func testAutomaticCatalogRefreshNeedsOllamaAndEitherAKeyOrAServer() {
        let settings = MobileAISettings()
        defer { settings.saveBaseURL("") }
        settings.provider = .apple
        settings.saveBaseURL("http://papercut-test.local:11434")
        XCTAssertFalse(settings.canRefreshAutomatically, "Apple Intelligence never reaches for a model catalog")
        settings.provider = .ollama
        XCTAssertTrue(settings.canRefreshAutomatically, "A server the user entered is a destination they chose")
        settings.saveBaseURL("")
        XCTAssertEqual(settings.canRefreshAutomatically, settings.hasKey,
                       "Ollama Cloud may only be contacted automatically once a key is saved")
    }

    // MARK: On-disk protection and backup

    func testConversationFilesAreWrittenWithFileProtection() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.notes = "Board pay review"
        XCTAssertTrue(session.save(announce: false))
        session.addAttachment(data: Data("Whiteboard".utf8), name: "photo.txt")
        let attachment = try XCTUnwrap(session.attachments.first)
        XCTAssertTrue(PrivateStorage.writingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication),
                      "Transcripts stay encrypted until the device is unlocked once after a restart")
        for url in [root.appendingPathComponent("ActiveConversation.json"),
                    try session.attachmentStore().url(for: attachment)] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testBackupExclusionIsOffByDefaultAndAppliesToEveryConversationDirectory() throws {
        let previous = UserDefaults.standard.object(forKey: MobileSession.excludeBackupKey)
        defer { UserDefaults.standard.set(previous, forKey: MobileSession.excludeBackupKey) }
        UserDefaults.standard.removeObject(forKey: MobileSession.excludeBackupKey)
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let directories = [root.appendingPathComponent("Conversations"), root.appendingPathComponent("Attachments")]
        XCTAssertFalse(session.excludeFromBackup, "A restored phone should still have the user's conversations")
        for directory in directories { XCTAssertFalse(PrivateStorage.isExcludedFromBackup(directory)) }
        session.excludeFromBackup = true
        for directory in directories { XCTAssertTrue(PrivateStorage.isExcludedFromBackup(directory)) }
        session.notes = "Kept out of iCloud"
        XCTAssertTrue(session.save(announce: false))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(root.appendingPathComponent("ActiveConversation.json")))
        // The choice is remembered and re-applied at launch.
        XCTAssertTrue(MobileSession(storageDirectory: root).excludeFromBackup)
        session.excludeFromBackup = false
        for directory in directories { XCTAssertFalse(PrivateStorage.isExcludedFromBackup(directory)) }
    }

    // MARK: History search

    func testHistorySearchFindsAConversationByAnyOfItsWords() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "Standup"; session.summary = "Chased invoice 4471 with finance"
        XCTAssertTrue(session.save(announce: false))
        session.newConversation()
        session.title = "Design review"; session.summary = "Typography pass on the summary card"
        XCTAssertTrue(session.save(announce: false))
        XCTAssertEqual(session.historyMatching("").count, 2, "No query is the whole history")
        XCTAssertEqual(session.historyMatching("   ").count, 2)
        XCTAssertEqual(session.historyMatching("4471").map(\.title), ["Standup"])
        XCTAssertEqual(session.historyMatching("design").map(\.title), ["Design review"])
        XCTAssertTrue(session.historyMatching("invoice typography").isEmpty,
                      "Every term must appear in the same conversation")
    }
}
