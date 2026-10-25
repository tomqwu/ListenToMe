import EventKit
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Naming conversations that still say "New conversation" after a save (#221), with a fake
/// on-device provider. No real model is called.
@MainActor
final class MobileAutoTitleTests: XCTestCase {
    /// Answers with `reply`; when `gate` is set, waits for it to open first.
    final class TitleProvider: LLMProvider, @unchecked Sendable {
        let id = "auto-title-test"
        var reply: String
        var requests = 0
        var gate: CheckedContinuation<Void, Never>?
        var gated = false
        init(_ reply: String) { self.reply = reply }
        func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
            requests += 1
            let reply = reply, gated = gated
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    if gated { await withCheckedContinuation { self.gate = $0 } }
                    continuation.yield(reply)
                    continuation.finish()
                }
            }
        }
    }

    private var root: URL!
    private var savedSetting: Any?
    private var savedProvider: String?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("autotitle-\(UUID().uuidString)")
        savedSetting = UserDefaults.standard.object(forKey: MobileSession.autoTitleKey)
        UserDefaults.standard.removeObject(forKey: MobileSession.autoTitleKey)
        savedProvider = UserDefaults.standard.string(forKey: "mobileAIProvider")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedSetting, forKey: MobileSession.autoTitleKey)
        UserDefaults.standard.set(savedProvider, forKey: "mobileAIProvider")
        try? FileManager.default.removeItem(at: root)
    }

    static let meeting = [
        "Let's go over the marketing budget for the spring campaign.",
        "The marketing budget is tight this quarter, so we need to decide which channels to cut.",
        "I think the spring campaign should focus on social video, because print ads did not pay off.",
        "Agreed. Let's move print money into social video and review the marketing budget next month.",
    ]

    private func makeSession(_ provider: TitleProvider? = nil, lines: [String] = meeting) -> MobileSession {
        let session = MobileSession(storageDirectory: root, sharedInbox: root.appendingPathComponent("inbox"))
        session.ai.provider = .apple
        session.onDeviceProviderOverride = provider
        session.segments = lines.enumerated().map { index, text in
            TranscriptSegment(source: .you, text: text, isFinal: true, start: Double(index * 5),
                              end: Double(index * 5 + 4), speakerName: "Microphone")
        }
        return session
    }

    private func name(_ session: MobileSession, _ id: String? = nil) async {
        await session.nameConversationIfNeeded(id)?.value
    }

    func testASavedDefaultConversationIsNamedByTheChosenProviderAndKeepsIt() async throws {
        let provider = TitleProvider("\"Spring marketing budget.\" 🚀")
        let session = makeSession(provider)
        XCTAssertTrue(session.save())
        await name(session)
        XCTAssertEqual(session.title, "Spring marketing budget")
        XCTAssertEqual(session.titleState.source, .automatic)
        XCTAssertEqual(provider.requests, 1)
        XCTAssertEqual(session.history.first?.title, "Spring marketing budget")
        let relaunched = MobileSession(storageDirectory: root, sharedInbox: root.appendingPathComponent("inbox"))
        XCTAssertEqual(relaunched.title, "Spring marketing budget")
        XCTAssertEqual(relaunched.titleState.source, .automatic)

        // Named once: saving again with a little more speech does not ask again.
        await name(session)
        XCTAssertEqual(provider.requests, 1)
    }

    func testATypedTitleIsNeverReplacedAndCancelsANamingUnderWay() async throws {
        let provider = TitleProvider("Spring marketing budget")
        provider.gated = true
        let session = makeSession(provider)
        XCTAssertTrue(session.save())
        let task = try XCTUnwrap(session.nameConversationIfNeeded())
        for _ in 0..<200 where provider.gate == nil { await Task.yield() }
        session.renameByUser("Budget sync")
        provider.gate?.resume()
        await task.value
        XCTAssertEqual(session.title, "Budget sync")
        XCTAssertEqual(session.titleState, .user)
        XCTAssertTrue(session.save())   // the title field schedules this save
        XCTAssertEqual(session.history.first?.title, "Budget sync")
        XCTAssertEqual(session.history.first?.titleState, .user)

        provider.gated = false
        await name(session)
        XCTAssertEqual(session.title, "Budget sync")
        XCTAssertEqual(provider.requests, 1, "a typed title is not even sent for naming")
    }

    func testAnExistingSummaryNamesItWithoutAModelCall() async {
        let provider = TitleProvider("Should not be used")
        let session = makeSession(provider)
        session.summary = "## Decisions\n- Spring campaign moves to social video."
        XCTAssertTrue(session.save())
        await name(session)
        XCTAssertEqual(session.title, "Spring campaign moves to social video")
        XCTAssertEqual(provider.requests, 0)
    }

    func testWithoutAnAvailableProviderKeywordsFoundOnDeviceNameIt() async {
        let session = makeSession(nil)
        XCTAssertNil(session.autoTitleProvider, "unit tests never reach a real model")
        XCTAssertTrue(session.save())
        await name(session)
        XCTAssertTrue(session.title.lowercased().contains("budget"), session.title)
        XCTAssertEqual(session.titleState.source, .automatic)
    }

    func testTheSettingShortConversationsAndCalendarTitlesLeaveTheNameAlone() async throws {
        UserDefaults.standard.set(false, forKey: MobileSession.autoTitleKey)
        let provider = TitleProvider("Spring marketing budget")
        let off = makeSession(provider)
        XCTAssertTrue(off.save())
        await name(off)
        XCTAssertEqual(off.title, "New conversation")
        UserDefaults.standard.removeObject(forKey: MobileSession.autoTitleKey)
        XCTAssertTrue(MobileSession.namesConversationsAutomatically, "on by default")

        off.newConversation()
        off.segments = [TranscriptSegment(source: .you, text: "Hello, can you hear me?", isFinal: true, start: 0, end: 1)]
        XCTAssertTrue(off.save())
        await name(off)
        XCTAssertEqual(off.title, "New conversation", "too few words to name")

        let calendar = makeSession(provider)
        calendar.newConversation()
        calendar.segments = makeSession().segments
        let source = EKEvent(eventStore: EKEventStore())
        source.title = "Release review"
        source.startDate = Date()
        source.endDate = source.startDate.addingTimeInterval(1_800)
        let event = MobileCalendar.event(source)
        XCTAssertTrue(calendar.importCalendarEvent(event))
        XCTAssertEqual(calendar.titleState, .calendar)
        await name(calendar)
        XCTAssertEqual(calendar.title, "Release review")
        XCTAssertEqual(provider.requests, 0)
    }

    func testASavedConversationNotOpenAnyMoreIsRenamedInHistory() async throws {
        let provider = TitleProvider("Spring marketing budget")
        provider.gated = true
        let session = makeSession(provider)
        XCTAssertTrue(session.save())
        let first = session.id
        let task = try XCTUnwrap(session.nameConversationIfNeeded())
        for _ in 0..<200 where provider.gate == nil { await Task.yield() }
        session.newConversation()
        provider.gate?.resume()
        await task.value
        XCTAssertEqual(session.title, "New conversation", "the new conversation keeps its name")
        let renamed = try XCTUnwrap(session.history.first { $0.id == first })
        XCTAssertEqual(renamed.title, "Spring marketing budget")
        XCTAssertEqual(renamed.titleState?.source, .automatic)
        XCTAssertEqual(renamed.segments?.count, Self.meeting.count)
    }

    /// #221 review: a return to the app mid-recording (Control Center) must not name half a
    /// transcript or send anything.
    func testNothingIsNamedWhileRecording() async {
        let provider = TitleProvider("Spring marketing budget")
        let session = makeSession(provider)
        XCTAssertTrue(session.save())
        for state in [MobileSession.State.preparing, .recording, .stopping] {
            session.state = state
            session.nameConversationIfNeeded()
            XCTAssertFalse(session.titleCoordinator.isNaming(session.id), "\(state)")
        }
        session.state = .idle
        await name(session)
        XCTAssertEqual(session.title, "Spring marketing budget")
        XCTAssertEqual(provider.requests, 1)
    }

    /// #221 review: with Ollama Cloud, a Cloud AI service or an OpenAI-compatible server, Stop sends
    /// nothing for a title; keywords name it. Apple Intelligence and the user's own Ollama may be asked.
    func testOnlyOnDeviceOrOwnOllamaModelsAreAskedForATitle() {
        let session = makeSession(TitleProvider("Unused"))
        XCTAssertEqual(session.autoTitleMode, .apple)
        XCTAssertNotNil(session.autoTitleProvider)
        for provider in [MobileAISettings.Provider.openAI, .cloud] {
            session.ai.provider = provider
            XCTAssertFalse(ConversationAutoTitle.mayAskModel(session.autoTitleMode), provider.rawValue)
            XCTAssertNil(session.autoTitleProvider, provider.rawValue)
        }
        session.ai.provider = .ollama
        XCTAssertEqual(session.autoTitleMode, session.ai.usesCustomEndpoint ? .local : .cloud)
        if !session.ai.usesCustomEndpoint { XCTAssertNil(session.autoTitleProvider, "Ollama Cloud") }
    }

    /// #221 review: a naming that found nothing is remembered, not retried on every Save.
    func testANamingThatFoundNothingIsNotRetriedUntilTheTranscriptGrows() async {
        let provider = TitleProvider("I'm sorry, I can't help with that.")
        let filler = Array(repeating: "Yeah okay um uh yeah okay um uh yeah okay.", count: 4)
        let session = makeSession(provider, lines: filler)
        XCTAssertTrue(session.save())
        await name(session)
        XCTAssertEqual(session.title, "New conversation")
        XCTAssertEqual(session.titleState.attemptedWords, ConversationAutoTitle.wordCount(filler.joined(separator: "\n")))
        XCTAssertEqual(MobileSession(storageDirectory: root, sharedInbox: root.appendingPathComponent("inbox"))
            .titleState.attemptedWords, session.titleState.attemptedWords, "remembered across launches")
        await name(session)
        XCTAssertEqual(provider.requests, 1, "not asked again for the same transcript")
    }

    /// #221 review: Import from Calendar replaces an automatic name with the meeting's.
    func testCalendarReplacesAnAutomaticName() async throws {
        let session = makeSession(TitleProvider("Spring marketing budget"))
        XCTAssertTrue(session.save())
        await name(session)
        XCTAssertEqual(session.titleState.source, .automatic)
        let source = EKEvent(eventStore: EKEventStore())
        source.title = "Release review"
        source.startDate = Date()
        source.endDate = source.startDate.addingTimeInterval(1_800)
        XCTAssertTrue(session.importCalendarEvent(MobileCalendar.event(source)))
        XCTAssertEqual(session.title, "Release review")
        XCTAssertEqual(session.titleState, .calendar)
        session.renameByUser("Our review")
        XCTAssertTrue(session.importCalendarEvent(MobileCalendar.event(source)))
        XCTAssertEqual(session.title, "Our review", "a typed title is never replaced")
    }

    func testAnOlderConversationRecordDecodesAsDefault() throws {
        let session = makeSession()
        XCTAssertTrue(session.save())
        XCTAssertEqual(session.history.first?.resolvedTitleState, .placeholder)
        session.renameByUser("Standup")
        XCTAssertTrue(session.save())
        XCTAssertEqual(session.history.first?.titleState, .user)
    }
}
