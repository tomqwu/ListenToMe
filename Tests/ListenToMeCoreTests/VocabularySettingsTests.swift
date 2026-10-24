import XCTest
@testable import ListenToMeCore

/// My terms editing, plain-text import/export, persistence and the active-vocabulary caps (issue #222).
final class VocabularySettingsTests: XCTestCase {
    func testMyTermsAreTrimmedUniqueAndBounded() {
        var settings = VocabularySettings()
        XCTAssertTrue(settings.addTerm("  Kubernetes   cluster "))
        XCTAssertEqual(settings.myTerms, ["Kubernetes cluster"])
        XCTAssertFalse(settings.addTerm("kubernetes CLUSTER"))
        XCTAssertEqual(settings.rejection(of: "kubernetes cluster"), "“kubernetes cluster” is already in My terms.")
        XCTAssertFalse(settings.addTerm("   "))
        XCTAssertEqual(settings.rejection(of: ""), "Enter a word or short phrase.")
        XCTAssertFalse(settings.addTerm(String(repeating: "x", count: 61)))
        XCTAssertNotNil(settings.rejection(of: String(repeating: "x", count: 61)))
        XCTAssertTrue(settings.addTerm("张伟"), "My terms accept any language")
        settings.myTerms = (0..<VocabularySettings.myTermsLimit).map { "t\($0)" }
        XCTAssertFalse(settings.addTerm("one more"))
        XCTAssertEqual(settings.rejection(of: "one more"), "My terms holds up to 300 terms.")
    }

    func testReplaceAndRemove() {
        var settings = VocabularySettings(myTerms: ["Acme", "Jordan"])
        XCTAssertTrue(settings.replaceTerm(at: 0, with: "ACME Corp"))
        XCTAssertTrue(settings.replaceTerm(at: 1, with: "jordan"), "a case-only edit of the same term is allowed")
        XCTAssertFalse(settings.replaceTerm(at: 1, with: "acme corp"))
        XCTAssertFalse(settings.replaceTerm(at: 5, with: "Nope"))
        XCTAssertEqual(settings.myTerms, ["ACME Corp", "jordan"])
        settings.removeTerm("ACME CORP")
        XCTAssertEqual(settings.myTerms, ["jordan"])
    }

    func testPlainTextImportAndExportRoundTrip() {
        var settings = VocabularySettings(myTerms: ["Acme"])
        let added = settings.importTerms(from: "# my list\nKubernetes\n\n  acme \r\nLiu Yang\nKubernetes\n")
        XCTAssertEqual(added, 2)
        XCTAssertEqual(settings.myTerms, ["Acme", "Kubernetes", "Liu Yang"])
        XCTAssertEqual(settings.exportedText, "Acme\nKubernetes\nLiu Yang\n")
        var copy = VocabularySettings()
        copy.importTerms(from: settings.exportedText)
        XCTAssertEqual(copy.myTerms, settings.myTerms)
        XCTAssertEqual(VocabularySettings().exportedText, "")
    }

    func testDefaultsAndMutedSuggestions() {
        var settings = VocabularySettings()
        settings.setDefault("medical", true)
        settings.setDefault("medical", true)
        settings.setDefault("legal", true)
        settings.setDefault("legal", false)
        XCTAssertEqual(settings.defaultDomainIDs, ["medical"])
        XCTAssertTrue(settings.isDefault("medical"))
        settings.setMuted("sales", true)
        XCTAssertTrue(settings.isMuted("sales"))
        settings.setMuted("sales", false)
        XCTAssertFalse(settings.isMuted("sales"))
    }

    func testStoreRoundTripsAndToleratesOlderOrBrokenData() throws {
        let suite = "VocabularySettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VocabularySettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), VocabularySettings())
        let saved = VocabularySettings(defaultDomainIDs: ["legal"], myTerms: ["Acme"], myTermsEnabled: false,
                                       suggestionsEnabled: false, mutedSuggestionIDs: ["sales"], domainSummaryLayout: false)
        store.save(saved)
        XCTAssertEqual(store.load(), saved)
        // A record written before a field existed keeps the user's list and defaults the rest.
        defaults.set(Data(#"{"myTerms":["Acme"]}"#.utf8), forKey: VocabularySettingsStore.key)
        XCTAssertEqual(store.load(), VocabularySettings(myTerms: ["Acme"]))
        defaults.set(Data("not json".utf8), forKey: VocabularySettingsStore.key)
        XCTAssertEqual(store.load(), VocabularySettings())
    }

    // MARK: - Active vocabulary and recognition caps

    private func preset(_ id: String, _ terms: [String]) -> VocabularyDomain {
        VocabularyDomain(id: id, name: id.capitalized, description: "A \(id) conversation.", summaryLayout: ["A", "B"],
                         terms: terms)
    }

    func testActiveVocabularyMergesDefaultsWithThisConversationsChoices() {
        let catalog = VocabularyCatalog(domains: [preset("medical", ["a"]), preset("legal", ["b"]), preset("sales", ["c"])])
        var settings = VocabularySettings(defaultDomainIDs: ["sales"], myTerms: ["Acme"])
        let active = ActiveVocabulary(settings: settings, conversationDomainIDs: ["medical"], catalog: catalog)
        XCTAssertEqual(active.domains.map(\.id), ["medical", "sales"], "catalog order, not the order chosen")
        XCTAssertEqual(active.myTerms, ["Acme"])
        XCTAssertEqual(active.layoutDomain?.id, "medical")
        settings.myTermsEnabled = false
        settings.domainSummaryLayout = false
        let quiet = ActiveVocabulary(settings: settings, catalog: catalog)
        XCTAssertEqual(quiet.myTerms, [])
        XCTAssertNil(quiet.layoutDomain)
        XCTAssertFalse(quiet.isEmpty)
        XCTAssertTrue(ActiveVocabulary(settings: VocabularySettings(), catalog: catalog).isEmpty)
    }

    func testRecognitionTermsAreCappedAtAppleGuidance() {
        let big = preset("medical", (0..<300).map { "drug\($0)" })
        let active = ActiveVocabulary(domains: [big], myTerms: [])
        let terms = active.recognitionTerms()
        XCTAssertEqual(terms.count, ActiveVocabulary.recognitionLimit)
        XCTAssertEqual(ActiveVocabulary.recognitionLimit, 100)
        XCTAssertEqual(terms.first, "drug0", "a preset's leading (most mis-heard) terms go first")
    }

    func testMyTermsComeFirstButLeaveRoomForAnActivePreset() {
        let mine = (0..<90).map { "mine\($0)" }
        let withPreset = ActiveVocabulary(domains: [preset("legal", (0..<300).map { "law\($0)" })], myTerms: mine)
        let terms = withPreset.recognitionTerms()
        XCTAssertEqual(terms.count, 100)
        XCTAssertEqual(Array(terms.prefix(60)), Array(mine.prefix(60)))
        XCTAssertEqual(terms[60], "law0")
        XCTAssertEqual(ActiveVocabulary(domains: [], myTerms: mine).recognitionTerms(), mine)
        // A small preset leaves its unused slots to the rest of My terms.
        let small = ActiveVocabulary(domains: [preset("legal", ["tort"])], myTerms: mine).recognitionTerms()
        XCTAssertEqual(small.count, 91)
        XCTAssertEqual(small[60], "tort")
        XCTAssertEqual(small.last, "mine89")
    }

    func testRecognitionInterleavesPresetsAndSkipsLongOrRepeatedPhrases() {
        let active = ActiveVocabulary(domains: [preset("medical", ["CBC", "dyspnea", "one two three four"]),
                                               preset("legal", ["tort", "cbc", "voir dire"])],
                                      myTerms: ["Acme"])
        XCTAssertEqual(active.recognitionTerms(), ["Acme", "CBC", "tort", "dyspnea", "voir dire"])
        XCTAssertEqual(active.recognitionTerms(limit: 2), ["Acme", "CBC"])
    }
}
