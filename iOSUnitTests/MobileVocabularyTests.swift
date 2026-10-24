import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Domain vocabularies on iOS (issue #222): what the recognizer, the correction prompt and the summary
/// prompts receive, and the suggestion banner's flow. A fake recorder records every context it is given;
/// no real recognition runs.
@MainActor
final class MobileVocabularyTests: XCTestCase {
    static let medicalSpeech = [
        "okay so this is a sixty eight year old woman with a history of atrial fibrillation and heart failure",
        "she came in with worsening dyspnea over the last week and can't lie flat anymore",
        "she's on apixaban five milligrams BID, metoprolol twenty five twice a day, and furosemide forty daily",
        "on exam she has pitting edema up to the knees and crackles at both bases",
        "troponin was flat times two and BNP is elevated at around eleven hundred",
        "her creatinine bumped from one point one to one point six so i'm a little worried about her kidneys",
        "can we get an echocardiogram today, her last ejection fraction was thirty five percent a year ago",
        "let's switch the furosemide to forty IV twice a day and keep her on a fluid restriction",
        "strict ins and outs, daily weights, and recheck labs in the morning, no allergies listed in the chart",
        "okay, i'll talk to her daughter this afternoon and update the family on everything we discussed today"
    ]

    private let keys = [VocabularySettingsStore.key, "autoQuickSummary", MobileSession.languageKey,
                        MobileLanguageDetection.automaticKey]
    private var saved: [Any?] = []
    private var root: URL!

    override func setUp() async throws {
        saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: VocabularySettingsStore.key)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession(_ recorder: VocabularyTestRecorder, provider: (any LLMProvider)? = nil) -> MobileSession {
        let session = MobileSession(storageDirectory: root, summaryProvider: provider, makeRecorder: { recorder })
        session.autoQuick = false
        return session
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate())
    }

    func testMyTermsAndDefaultPresetsReachTheRecognizerBeforeItStarts() async throws {
        let recorder = VocabularyTestRecorder()
        let session = makeSession(recorder)
        session.vocabulary.settings = VocabularySettings(defaultDomainIDs: ["legal"], myTerms: ["Acme Cloud", "张伟"])
        session.start()
        try await wait { session.state == .recording }
        let first = try XCTUnwrap(recorder.contexts.first)
        XCTAssertEqual(recorder.contextsBeforeStart, 1)
        XCTAssertEqual(Array(first.prefix(2)), ["张伟", "Acme Cloud"], "My terms first, newest first")
        XCTAssertTrue(first.contains("res judicata"))
        XCTAssertEqual(first.count, ActiveVocabulary.recognitionLimit)
        await session.stop()
    }

    func testFixedChineseLanguageUsesChineseTermsBeforeCaptureAndInManualPrompts() async throws {
        let recorder = VocabularyTestRecorder()
        let provider = PromptRecordingProvider()
        let session = makeSession(recorder, provider: provider)
        session.languageChoice = "zh-CN"
        session.vocabulary.settings = VocabularySettings(defaultDomainIDs: ["medical"], myTerms: ["张伟"])
        session.start()
        try await wait { session.state == .recording }
        XCTAssertTrue(recorder.contexts.first?.contains("心房颤动") == true)
        XCTAssertEqual(recorder.contexts.first?.first, "张伟")
        XCTAssertFalse(recorder.contexts.first?.contains("metoprolol") == true)
        recorder.send("患者存在心房颤动和呼吸困难，检查肌钙蛋白和肌酐。")
        await session.stop()
        await session.summarize(mode: .summary)
        XCTAssertTrue(provider.requests.last?.system.contains("心房颤动") == true)
        let record = try XCTUnwrap(session.history.first)
        session.newConversation()
        session.languageChoice = "en-US"
        session.open(record)
        XCTAssertEqual(session.vocabularyLanguage, "zh-CN", "History uses the conversation's own language")
        XCTAssertTrue(session.activeVocabulary.recognitionTerms().contains("心房颤动"))
    }

    func testChineseSuggestionsAndEnglishFallbackKeepTheirOwnTerms() async {
        let vocabulary = SessionVocabulary(defaults: UserDefaults(suiteName: "zh-vocab-\(UUID())")!)
        let speech = String(repeating: "患者存在心房颤动和心力衰竭，服用美托洛尔和阿哌沙班。检查肌钙蛋白、肌酐和超声心动图。", count: 12)
        vocabulary.heard(speech, conversationID: "zh", localeIdentifier: "zh-CN", recent: speech)
        await vocabulary.check?.value
        XCTAssertEqual(vocabulary.banner(for: "zh")?.domain.id, "medical")
        vocabulary.addSuggested()
        XCTAssertTrue(vocabulary.recognitionTerms(for: "zh", localeIdentifier: "zh-CN").contains("心房颤动"))
        XCTAssertTrue(vocabulary.recognitionTerms(for: "zh", localeIdentifier: "fr-FR").contains("metoprolol"))
    }

    func testTheBannerOffersMedicalAndAddTakesEffectWithoutRestartingTheMicrophone() async throws {
        let recorder = VocabularyTestRecorder()
        let session = makeSession(recorder)
        session.start()
        try await wait { session.state == .recording }
        XCTAssertEqual(recorder.contexts, [[]])
        for line in Self.medicalSpeech { recorder.send(line) }
        try await wait { session.vocabulary.banner(for: session.id) != nil }
        let banner = try XCTUnwrap(session.vocabulary.banner(for: session.id))
        XCTAssertEqual(banner.domain.id, "medical")
        XCTAssertEqual(banner.stage, .offered)
        XCTAssertTrue(recorder.contexts.count == 1, "suggesting never turns a vocabulary on")

        session.addSuggestedVocabulary()
        try await wait { recorder.contexts.count == 2 }
        XCTAssertTrue(recorder.contexts.last?.contains("metoprolol") == true)
        XCTAssertEqual(recorder.startCount, 1, "the microphone kept running")
        XCTAssertEqual(session.vocabulary.banner(for: session.id)?.stage, .added)
        XCTAssertTrue(session.activeVocabulary.domains.map(\.id) == ["medical"])
        XCTAssertFalse(session.vocabulary.settings.isDefault("medical"), "Add is for this conversation only")

        session.useSuggestedVocabularyByDefault()
        XCTAssertTrue(session.vocabulary.settings.isDefault("medical"))
        XCTAssertNil(session.vocabulary.banner(for: session.id))
        await session.stop()
    }

    func testNotNowAndDontSuggestAgain() async throws {
        let recorder = VocabularyTestRecorder()
        let session = makeSession(recorder)
        session.start()
        try await wait { session.state == .recording }
        for line in Self.medicalSpeech { recorder.send(line) }
        try await wait { session.vocabulary.banner(for: session.id) != nil }
        session.vocabulary.dismissSuggestion()
        XCTAssertNil(session.vocabulary.banner(for: session.id))
        for line in Self.medicalSpeech { recorder.send(line) }
        await session.vocabulary.check?.value
        XCTAssertNil(session.vocabulary.banner(for: session.id), "offered at most once per conversation")
        XCTAssertEqual(recorder.contexts.count, 1)
        await session.stop()

        session.newConversation()
        session.start()
        try await wait { session.state == .recording }
        for line in Self.medicalSpeech { recorder.send(line) }
        try await wait { session.vocabulary.banner(for: session.id) != nil }
        session.vocabulary.muteSuggested()
        XCTAssertTrue(session.vocabulary.settings.isMuted("medical"))
        await session.stop()
    }

    func testSuggestionsCanBeTurnedOff() async throws {
        let recorder = VocabularyTestRecorder()
        let session = makeSession(recorder)
        session.vocabulary.settings.suggestionsEnabled = false
        session.start()
        try await wait { session.state == .recording }
        for line in Self.medicalSpeech { recorder.send(line) }
        await session.vocabulary.check?.value
        XCTAssertNil(session.vocabulary.check)
        XCTAssertNil(session.vocabulary.banner(for: session.id))
        await session.stop()
    }

    func testAddToMyTermsFromATranscriptLineReachesTheRunningRecognizer() async throws {
        let recorder = VocabularyTestRecorder()
        let session = makeSession(recorder)
        session.start()
        try await wait { session.state == .recording }
        XCTAssertNil(session.addToMyTerms("Kubeflow"))
        try await wait { recorder.contexts.last == ["Kubeflow"] }
        XCTAssertEqual(session.addToMyTerms("kubeflow"), "“kubeflow” is already in My terms.")
        XCTAssertEqual(VocabularySettingsStore().load().myTerms, ["Kubeflow"], "saved with the app's settings")
        await session.stop()
    }

    func testSummaryPromptCarriesTheDomainGlossaryAndLayout() async throws {
        let provider = PromptRecordingProvider()
        let session = makeSession(VocabularyTestRecorder(), provider: provider)
        session.vocabulary.settings = VocabularySettings(defaultDomainIDs: ["medical"], myTerms: ["Dr. Okafor"])
        session.notes = "Patient seen with apixaban questions."
        await session.summarize(mode: .summary)
        let summary = try XCTUnwrap(provider.requests.last)
        XCTAssertTrue(summary.system.contains("Context for this session: Domain: Medical"))
        XCTAssertTrue(summary.system.contains("History, Findings, Plan"))
        XCTAssertTrue(summary.system.contains("Dr. Okafor, apixaban"), "terms heard come before the rest")
        await session.summarize(mode: .quick)
        let quick = try XCTUnwrap(provider.requests.last)
        XCTAssertTrue(quick.system.contains("Domain: Medical"))
        XCTAssertFalse(quick.system.contains("headings"), "the layout is for summaries only")
        session.vocabulary.settings = VocabularySettings()
        await session.summarize(mode: .summary)
        XCTAssertFalse(provider.requests.last?.system.contains("Context for this session") == true)
    }

    func testCorrectionRequestCarriesTheGlossaryAndAcceptsKnownTermsWithNumbers() throws {
        let request = try MobileTranscriptCorrection.request(text: "move it to ec two", context: "",
                                                             glossary: ["EC2", "Kubernetes"])
        XCTAssertTrue(request.system.contains(VocabularyPrompt.correctionInstruction))
        let payload = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(request.messages.first?.content).utf8))
        XCTAssertEqual((payload as? [String: Any])?["glossary"] as? [String], ["EC2", "Kubernetes"])
        let reply = #"{"text":"deploy the EC2 instance"}"#
        XCTAssertEqual(try MobileTranscriptCorrection.validatedText(reply, original: "deploy the e c2 instance",
                                                                    glossary: ["EC2"]), "deploy the EC2 instance")
        XCTAssertThrowsError(try MobileTranscriptCorrection.validatedText(#"{"text":"deploy the EC2 instance"}"#,
                                                                          original: "deploy the easy instance"),
                             "without the glossary a new number is still refused")
        XCTAssertThrowsError(try MobileTranscriptCorrection.validatedText(#"{"text":"move 4 nodes to EC2"}"#,
                                                                          original: "move 3 nodes to ec two",
                                                                          glossary: ["EC2"]))
        let plain = try MobileTranscriptCorrection.request(text: "hello", context: "")
        XCTAssertEqual(plain.system, MobileTranscriptCorrection.instructions)
    }

    func testTheCorrectionGlossaryFavorsNearMisses() {
        let session = makeSession(VocabularyTestRecorder())
        session.vocabulary.settings = VocabularySettings(defaultDomainIDs: ["software-cloud"], myTerms: ["Acme", "Okafor"])
        let glossary = session.correctionGlossary(for: "we run akme on kubernetis")
        XCTAssertEqual(glossary.first, "Acme")
        XCTAssertFalse(glossary.contains("Okafor"), "My terms are ranked by resemblance, like presets")
        XCTAssertTrue(glossary.contains("Kubernetes"))
        XCTAssertLessThanOrEqual(glossary.count, VocabularyPrompt.correctionGlossaryLimit)
    }

    /// #222 review, finding 1: a glossary term never lets a correction add or remove a negation or number.
    func testAGlossaryTermCannotChangeANegationOrANumber() {
        func reply(_ text: String) -> String { #"{"text":"\#(text)"}"# }
        let cases: [(String, String, [String])] = [
            ("our show rate dropped", "our no-show rate dropped", ["no-show rate"]),
            ("the case was dismissed with prejudice", "the case was dismissed without prejudice",
             ["without prejudice", "dismissal with prejudice"]),
            ("SOC 2 audit for 2 vendors", "SOC 2 audit for vendors", ["SOC 2"])
        ]
        for (original, corrected, glossary) in cases {
            XCTAssertThrowsError(try MobileTranscriptCorrection.validatedText(reply(corrected), original: original,
                                                                              glossary: glossary), corrected)
        }
    }

    /// #222 review, finding 7: a restored or imported transcript is never classified; only lines that
    /// arrive while recording count, and a replaced transcript only moves the baseline.
    func testOnlyLiveSpeechCountsTowardASuggestion() async {
        let vocabulary = SessionVocabulary(defaults: UserDefaults(suiteName: "vocab-\(UUID())")!)
        let restored = Self.medicalSpeech + Self.medicalSpeech
        vocabulary.heard(transcript: restored, conversationID: "a", live: false)
        XCTAssertNil(vocabulary.check)
        XCTAssertEqual(vocabulary.tracker.heardWords, 0)
        vocabulary.heard(transcript: restored, conversationID: "a", live: true)
        XCTAssertEqual(vocabulary.tracker.heardWords, 0, "lines already on screen are the baseline")
        vocabulary.heard(transcript: Array(restored.prefix(3)), conversationID: "a", live: true)
        XCTAssertEqual(vocabulary.tracker.heardWords, 0, "a shorter, replaced transcript is not recounted")
        vocabulary.heard(transcript: Array(restored.prefix(3)) + Self.medicalSpeech, conversationID: "a", live: true)
        XCTAssertGreaterThan(vocabulary.tracker.heardWords, 150)
        await vocabulary.check?.value
        XCTAssertEqual(vocabulary.banner(for: "a")?.domain.id, "medical")
        vocabulary.heard(transcript: restored, conversationID: "b", live: true)
        XCTAssertNil(vocabulary.banner(for: "b"))
        XCTAssertEqual(vocabulary.tracker.heardWords, 0, "another conversation starts from its baseline")
    }
}

@MainActor
final class VocabularyTestRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    private(set) var contexts: [[String]] = []
    private(set) var contextsBeforeStart = 0
    private(set) var startCount = 0
    private var time = 0.0

    func setContextualStrings(_ strings: [String]) async {
        contexts.append(strings)
        if startCount == 0 { contextsBeforeStart += 1 }
    }
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        startCount += 1
        receive = onSegment
    }
    func send(_ text: String) {
        receive?(.init(source: .you, text: text, isFinal: true, start: time, end: time + 4))
        time += 4
    }
    func stop() async throws { receive = nil }
    func reconfigure() async throws {}
}

private final class PromptRecordingProvider: LLMProvider, @unchecked Sendable {
    let id = "vocabulary-prompt-test"
    private let lock = NSLock()
    private var recorded: [LLMRequest] = []
    var requests: [LLMRequest] { lock.withLock { recorded } }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { recorded.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.yield("Summary.")
            continuation.finish()
        }
    }
}
