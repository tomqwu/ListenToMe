import XCTest
@testable import ListenToMeCore

/// Naming conversations that still have a default name (#221). No real model is called.
final class ConversationAutoTitleTests: XCTestCase {
    /// Answers every request with `reply`, or fails; records what it was asked.
    private final class TitleProvider: LLMProvider, @unchecked Sendable {
        let id = "title-test"
        let reply: String?
        private(set) var requests: [LLMRequest] = []
        init(_ reply: String?) { self.reply = reply }
        func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
            requests.append(request)
            let reply = reply
            return AsyncThrowingStream { continuation in
                if let reply {
                    for piece in reply.split(separator: " ", omittingEmptySubsequences: false) {
                        continuation.yield(String(piece) + " ")
                    }
                    continuation.finish()
                } else {
                    continuation.finish(throwing: URLError(.notConnectedToInternet))
                }
            }
        }
    }

    private let budgetMeeting = """
        Microphone: Let's go over the marketing budget for the spring campaign. The marketing budget is \
        tight this quarter, so we need to decide which channels to cut. Speaker 2: I think the spring \
        campaign should focus on social video, because the marketing budget for print ads did not pay \
        off last year. Microphone: Agreed. Let's move print money into social video and review the \
        marketing budget again next month.
        """

    // MARK: The replace rule

    func testOnlyADefaultNameWithEnoughWordsIsReplaced() {
        let enough = ConversationAutoTitle.minimumWords
        XCTAssertTrue(ConversationAutoTitle.shouldName(state: .placeholder, title: "New conversation", words: enough))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: .placeholder, title: "New conversation", words: enough - 1))
        XCTAssertTrue(ConversationAutoTitle.shouldName(state: .placeholder, title: "Conversation — Oct 23, 2026",
                                                       words: enough))
        XCTAssertTrue(ConversationAutoTitle.shouldName(state: .placeholder, title: "Apple Watch · Oct 23", words: enough))
        // A state says placeholder but the title was set some other way (a fixture, an older build).
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: .placeholder, title: "Standup", words: 500))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: .user, title: "New conversation", words: 500))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: .calendar, title: "Release review", words: 500))
    }

    func testAnAutomaticTitleIsRefinedOnceAfterMuchMoreSpeech() {
        let named = ConversationAutoTitle.namedState(after: .placeholder, words: 40)
        XCTAssertEqual(named, .automatic(words: 40))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: named, title: "Budget review", words: 100))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: named, title: "Budget review", words: 120),
                       "three times as long, but only 80 more words")
        XCTAssertTrue(ConversationAutoTitle.shouldName(state: named, title: "Budget review", words: 200))
        let refined = ConversationAutoTitle.namedState(after: named, words: 200)
        XCTAssertEqual(refined, .automatic(words: 200, refined: true))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: refined, title: "Spring budget", words: 5_000))
        XCTAssertFalse(ConversationAutoTitle.shouldName(state: ConversationTitleState(source: .automatic),
                                                       title: "Spring budget", words: 5_000))
    }

    func testOldRecordsDecodeAndResolveFromTheirTitle() throws {
        let legacy = #"{"id":"A","title":"New conversation","date":0,"transcript":"","summary":""}"#
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(record.titleState)
        XCTAssertEqual(record.resolvedTitleState, .placeholder)
        let typed = SessionRecord(id: "B", title: "Standup", date: Date(), transcript: "", summary: "")
        XCTAssertEqual(typed.resolvedTitleState, .user)
        XCTAssertEqual(SessionRecord(id: "C", title: "", date: Date(), transcript: "", summary: "").resolvedTitleState,
                       .user, "a title the user cleared is theirs")

        let named = typed.retitled("Budget review", state: .automatic(words: 40))
        let round = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(round, named)
        XCTAssertEqual(round.titleState, .automatic(words: 40))
        XCTAssertEqual(round.id, "B")

        let future = #"{"id":"D","title":"X","date":0,"transcript":"","summary":"","titleState":{"source":"assistant"}}"#
        let newer = try JSONDecoder().decode(SessionRecord.self, from: Data(future.utf8))
        XCTAssertEqual(newer.titleState?.source, .user, "an unknown source is never overwritten")
    }

    func testWordsAreCountedInAnyScript() {
        XCTAssertEqual(ConversationAutoTitle.wordCount("Review the budget, then ship."), 5)
        XCTAssertGreaterThan(ConversationAutoTitle.wordCount("我们明天讨论预算"), 2)
        XCTAssertEqual(ConversationAutoTitle.wordCount(""), 0)
    }

    // MARK: The prompt

    func testThePromptIsTinyBoundedFencedAndInTheConversationsLanguage() {
        let long = String(repeating: "word ", count: 2_000)
        let request = ConversationAutoTitle.request(transcript: long, language: "fr_FR")
        XCTAssertTrue(request.system.contains("in French"))
        XCTAssertTrue(request.system.contains("at most 6 words"))
        XCTAssertTrue(request.system.contains(PromptData.notice))
        XCTAssertEqual(request.messages.count, 1)
        let content = request.messages[0].content
        XCTAssertTrue(content.hasPrefix("<transcript>\n"))
        XCTAssertLessThanOrEqual(content.count, ConversationAutoTitle.headCharacters + 40)
        XCTAssertTrue(ConversationAutoTitle.request(transcript: "Hi", language: nil).system
            .contains("the same language as the transcript"))
        XCTAssertTrue(ConversationAutoTitle.request(transcript: "Hi", language: "zh-Hans").system.contains("Chinese"))
    }

    // MARK: Sanitizing

    func testSanitizingStripsQuotesLabelsEmojiMarkdownAndTrailingPunctuation() {
        let cases: [(String, String)] = [
            ("\"Spring marketing budget\"", "Spring marketing budget"),
            ("“Spring marketing budget.”", "Spring marketing budget"),
            ("Title: Spring marketing budget", "Spring marketing budget"),
            ("Here is a title: Spring budget review!", "Spring budget review"),
            ("**Spring budget** 🚀", "Spring budget"),
            ("## Q3 roadmap planning…", "Q3 roadmap planning"),
            ("spring budget review", "Spring budget review"),
            ("Hiring plan (engineering)", "Hiring plan (engineering)"),
            ("Budget review\nThis title reflects the main topic.", "Budget review"),
            ("Team's Q3 offsite", "Team's Q3 offsite"),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ConversationAutoTitle.sanitize(raw, language: "en"), expected, raw)
        }
    }

    func testSanitizingLimitsLength() throws {
        let long = try XCTUnwrap(ConversationAutoTitle.sanitize(
            "Planning the spring marketing budget and the social video campaign for next quarter", language: "en"))
        XCTAssertEqual(long.split(separator: " ").count, ConversationAutoTitle.maximumWords)
        XCTAssertEqual(long, "Planning the spring marketing budget and")
        let unspaced = try XCTUnwrap(ConversationAutoTitle.sanitize(
            "我们讨论了下个季度的市场预算以及社交视频广告活动的安排和时间表", language: "zh-Hans"))
        XCTAssertLessThanOrEqual(unspaced.count, ConversationAutoTitle.maximumUnspacedCharacters)
        let wide = String(repeating: "Supercalifragilistic ", count: 5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(ConversationAutoTitle.sanitize(wide, language: nil)).count,
                                 ConversationAutoTitle.maximumCharacters)
    }

    func testSanitizingRejectsJunkRefusalsDefaultsAndAnotherLanguage() {
        for junk in ["", "   ", "\"\"", "🚀🚀", "Untitled", "Title:", "New conversation", "N/A", ".",
                     "I'm sorry, but I can't help with that.", "As an AI, I cannot name this."] {
            XCTAssertNil(ConversationAutoTitle.sanitize(junk, language: "en"), junk)
        }
        // A French conversation named in English is rejected; short titles cannot be judged and pass.
        XCTAssertNil(ConversationAutoTitle.sanitize("Quarterly marketing budget planning review", language: "fr_FR"))
        XCTAssertEqual(ConversationAutoTitle.sanitize("Budget marketing du printemps", language: "fr_FR"),
                       "Budget marketing du printemps")
        XCTAssertEqual(ConversationAutoTitle.sanitize("Budget", language: "fr_FR"), "Budget")
        XCTAssertEqual(ConversationAutoTitle.sanitize("Quarterly marketing budget planning review", language: nil),
                       "Quarterly marketing budget planning review")
    }

    // MARK: From the summary

    func testTheSummarysFirstShortSentenceBecomesTheTitle() {
        let summary = "## Decisions\n- **Spring campaign moves to social video.**\n- Print is cut."
        XCTAssertEqual(ConversationAutoTitle.fromSummary(summary, language: "en"), "Spring campaign moves to social video")
        XCTAssertNil(ConversationAutoTitle.fromSummary("", language: "en"))
        XCTAssertNil(ConversationAutoTitle.fromSummary("## Decisions\n## Next steps", language: "en"))
    }

    func testALongSummarySentenceIsNamedByItsKeyPhrases() throws {
        let summary = """
            ## Summary
            The team reviewed the marketing budget for the spring campaign and agreed that the marketing \
            budget should move from print ads to social video.
            """
        let title = try XCTUnwrap(ConversationAutoTitle.fromSummary(summary, language: "en"))
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, ConversationAutoTitle.maximumWords)
        XCTAssertTrue(title.lowercased().contains("budget"), title)
    }

    // MARK: Keywords

    func testKeywordsNameTheTopicTheConversationReturnsTo() throws {
        let title = try XCTUnwrap(ConversationAutoTitle.keywords(budgetMeeting, language: "en"))
        XCTAssertTrue(title.lowercased().contains("marketing budget"), title)
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, ConversationAutoTitle.maximumWords)
        XCTAssertEqual(title.first?.isUppercase, true)
        XCTAssertFalse(title.contains("Speaker"))
        XCTAssertFalse(title.contains("Microphone"))
    }

    /// Each comma-separated part of a keyword title is the conversation's own words, found inside one
    /// of its sentences (so in its language, and never a phrase run across a full stop), and the
    /// whole title is at most six words.
    private func assertTakenFromOneSentenceEach(_ title: String, of text: String,
                                                file: StaticString = #filePath, line: UInt = #line) {
        let sentences = text.lowercased().components(separatedBy: ". ")
        for part in title.lowercased().components(separatedBy: ", ") {
            XCTAssertTrue(sentences.contains { $0.contains(part) }, "“\(part)” in \(title)", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, ConversationAutoTitle.maximumWords,
                                 file: file, line: line)
    }

    func testKeywordsStayInTheConversationsLanguageAndWithinASentence() throws {
        let french = "Nous devons parler du budget marketing pour la campagne. Le budget marketing est serré. "
            + "La campagne doit se concentrer sur la vidéo. Revoyons le budget le mois prochain."
        // Whether French has a part-of-speech model differs between SDKs: with one this is
        // "Budget marketing, campagne", without one the frequent-word fallback gives
        // "Budget, marketing, campagne". Both are fine; what matters holds either way.
        let titre = try XCTUnwrap(ConversationAutoTitle.keywords(french, language: "fr_FR"))
        XCTAssertTrue(titre.lowercased().hasPrefix("budget"), titre)
        assertTakenFromOneSentenceEach(titre, of: french)
        // The fallback itself only tokenizes, so it is the same on every SDK.
        XCTAssertEqual(Array(ConversationAutoTitle.frequentWords(french).prefix(3)), ["budget", "marketing", "campagne"])
        let german = "Wir müssen über das Marketingbudget sprechen. Das Marketingbudget ist knapp. "
            + "Die Kampagne sollte sich auf Videos konzentrieren. Die Kampagne prüfen wir nächsten Monat."
        let titel = try XCTUnwrap(ConversationAutoTitle.keywords(german, language: "de_DE"))
        XCTAssertTrue(titel.contains("Marketingbudget"), titel)
        XCTAssertFalse(titel.contains("Wir") || titel.contains("das"), titel)
        assertTakenFromOneSentenceEach(titel, of: german)
        let english = "The onboarding flow has too many steps. Alex will redesign the onboarding flow."
        XCTAssertEqual(ConversationAutoTitle.keywords(english, language: "en"), "Onboarding flow")
    }

    func testKeywordsWorkWithoutAPartOfSpeechModel() throws {
        let chinese = "我们讨论预算。预算需要削减。下个月再讨论预算和广告。广告效果不好。"
        let title = try XCTUnwrap(ConversationAutoTitle.keywords(chinese, language: "zh-Hans"))
        XCTAssertTrue(title.contains("预算"), title)
        XCTAssertNil(ConversationAutoTitle.keywords("", language: "en"))
    }

    // MARK: Choosing the source

    func testASummaryIsUsedWithoutAskingTheModel() async throws {
        let provider = TitleProvider("Should not be asked")
        let result = await ConversationAutoTitle.title(transcript: budgetMeeting,
                                                       summary: "- Spring campaign moves to social video.",
                                                       language: "en", provider: provider)
        XCTAssertEqual(result?.origin, .summary)
        XCTAssertEqual(result?.title, "Spring campaign moves to social video")
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testTheChosenProviderNamesItWhenThereIsNoSummary() async throws {
        let provider = TitleProvider("\"Spring marketing budget.\"")
        let result = await ConversationAutoTitle.title(transcript: budgetMeeting, summary: "", language: "en",
                                                       provider: provider)
        XCTAssertEqual(result?.title, "Spring marketing budget")
        XCTAssertEqual(result?.origin, .model)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(provider.requests[0].messages[0].content.contains("spring campaign"))
    }

    func testKeywordsAreUsedWhenTheProviderFailsAnswersBadlyOrIsOff() async throws {
        for provider in [TitleProvider(nil), TitleProvider("I'm sorry, I can't do that."), nil] {
            let result = await ConversationAutoTitle.title(transcript: budgetMeeting, summary: "", language: "en",
                                                           provider: provider)
            XCTAssertEqual(result?.origin, .keywords)
            XCTAssertTrue(result?.title.lowercased().contains("budget") == true, result?.title ?? "nil")
        }
    }

    func testAShortConversationIsNotNamed() async {
        let provider = TitleProvider("Budget")
        let result = await ConversationAutoTitle.title(transcript: "Hello, can you hear me?", summary: "- A summary.",
                                                       language: "en", provider: provider)
        XCTAssertNil(result)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testPlaceholdersOnBothPlatforms() {
        for title in ["New conversation", "Conversation — Oct 23, 2026 at 2:30 PM", "Apple Watch · Oct 23, 2026",
                      "Imported notes"] {
            XCTAssertTrue(ConversationTitle.isPlaceholder(title), title)
        }
        for title in ["", "Standup", "New conversation about budgets"] {
            XCTAssertFalse(ConversationTitle.isPlaceholder(title), title)
        }
    }
}

/// macOS names conversations with the Summary pane's provider only when the user can use it (#221).
@MainActor
final class MeetingSessionTitleProviderTests: XCTestCase {
    private func makeSession(listener: String, unavailable: Set<String> = []) -> MeetingSession {
        MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                       makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                       makeProvider: { model in MockLLMProvider(id: model, deltas: ["ok"]) },
                       models: [.listener: listener, .quick: "Q", .deep: "D"],
                       providerAvailability: { unavailable.contains($0) ? "Model not installed" : nil })
    }

    func testTheSummaryPanesProviderNamesConversationsWhenAvailable() {
        let session = makeSession(listener: "summary-model")
        XCTAssertEqual(session.conversationTitleProvider?.id, "summary-model")
        session.aiEnabled = false
        XCTAssertNil(session.conversationTitleProvider, "AI off means on-device keywords")
        XCTAssertNil(makeSession(listener: "missing", unavailable: ["missing"]).conversationTitleProvider)
        XCTAssertNil(makeSession(listener: "").conversationTitleProvider, "no model chosen")
    }
}
