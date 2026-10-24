import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #206: each conversation keeps the language it was actually transcribed in, including an
/// Automatic switch and its Undo, so Save to folder and exports never fall back to today's setting.
@MainActor
final class MobileConversationLanguageTests: MobileLanguageTestCase {
    private var device: String { ConversationLanguages.normalized(Locale.current.identifier) ?? "" }

    /// The record as History holds it after a relaunch.
    private func saved(_ session: MobileSession) -> SessionRecord? {
        makeSession().history.first { $0.id == session.id }
    }

    private func switchWholeConversationToChinese() async throws -> MobileSession {
        await model.answer("zh", 0.97)
        let session = makeSession()
        try await record(session)
        await speakChinese(session)
        recorder.send("我们今天", 1, 4)
        recorder.send("开会", 13, 15)
        await session.stop()
        return session
    }

    func testAWholeConversationSwitchIsSavedAndOutlivesTheSetting() async throws {
        let session = try await switchWholeConversationToChinese()
        let record = try XCTUnwrap(saved(session))
        XCTAssertEqual(record.language, "zh-CN")
        XCTAssertEqual(record.languages, ["zh-CN"], "nothing is left in the language it started in")

        session.languageChoice = "fr_FR"
        session.title = "Renamed later"
        XCTAssertTrue(session.save(announce: false))
        let edited = try XCTUnwrap(saved(session))
        XCTAssertEqual(edited.language, "zh-CN", "a later edit keeps the conversation's own language")
        XCTAssertTrue(MarkdownVault.markdown(for: edited).contains("language: \"zh-CN\""))
        XCTAssertTrue(session.markdown.contains("Language: zh-CN"), session.markdown)
        XCTAssertTrue(SessionExporter.json(for: edited).contains("\"language\" : \"zh-CN\""))
    }

    func testUndoPutsTheOriginalLanguageBack() async throws {
        let session = try await switchWholeConversationToChinese()
        session.undoLanguageSwitch()
        let record = try XCTUnwrap(saved(session))
        XCTAssertEqual(record.language, device)
        XCTAssertEqual(record.languages, [device])
    }

    func testAMidRecordingSwitchKeepsBothLanguages() async throws {
        let session = try await switchToMandarinAtOneMinute()
        await session.stop()
        let record = try XCTUnwrap(saved(session))
        XCTAssertEqual(record.language, "zh-CN")
        XCTAssertEqual(record.languages, [device, "zh-CN"])
        XCTAssertTrue(MarkdownVault.markdown(for: record).contains("languages:\n  - \"\(device)\"\n  - \"zh-CN\""))
    }

    func testAFixedLanguageIsSavedWithTheConversation() async throws {
        let session = makeSession(withModel: false)
        session.languageChoice = "de_DE"
        try await record(session)
        recorder.send("Guten Morgen", 1, 3)
        await session.stop()
        XCTAssertEqual(saved(session)?.language, "de-DE")
        XCTAssertEqual(saved(session)?.languages, ["de-DE"])
    }

    func testANeverTranscribedConversationHasNoLanguage() {
        let session = makeSession()
        session.notes = "Typed only"
        XCTAssertTrue(session.save(announce: false))
        XCTAssertNil(saved(session)?.language)
        XCTAssertFalse(MarkdownVault.markdown(for: session.currentRecord).contains("language:"))
    }
}

/// Issue #130: Export as writes a file named after the conversation, in the chosen format.
@MainActor
final class MobileExportFileTests: XCTestCase {
    func testExportFileIsNamedAfterTheConversationAndHoldsTheFormat() throws {
        let date = Date(timeIntervalSince1970: 1_792_766_100)
        let record = SessionRecord(id: "e", title: "Standup: Q4", date: date, transcript: "", summary: "",
                                   segments: [TranscriptSegment(source: .you, text: "Ship it.", isFinal: true,
                                                                start: 2, end: 4, speakerName: "Microphone")],
                                   language: "en-US", languages: ["en-US"])
        let file = ConversationExportFile(record: record, format: .srt)
        XCTAssertTrue(file.fileName.hasPrefix("Standup Q4 2026-10-2"), file.fileName)
        XCTAssertTrue(file.fileName.hasSuffix(".srt"))
        let url = try file.write()
        defer { try? FileManager.default.removeItem(at: ConversationExportFile.folder) }
        XCTAssertEqual(url.lastPathComponent, file.fileName)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "1\n00:00:02,000 --> 00:00:04,000\nShip it.\n")
        let second = try ConversationExportFile(record: record, format: .json).write()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the previous export is not kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(SessionExporter.formats(for: record), SessionExportFormat.allCases)
    }
}
