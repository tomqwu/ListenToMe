import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #180: opt-in speaker labels for one shared microphone. The diarizer is a fake, because the
/// simulator cannot run the speaker models meaningfully; the mapping, persistence and scheduling
/// around it are what these tests pin down.
@MainActor
final class MobileSpeakerTests: MobileSpeakerTestCase {
    // MARK: The setting

    func testAudioIsCopiedForIdentificationOnlyWhenTheSettingIsOn() async throws {
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        let session = makeSession()
        XCTAssertFalse(session.speakers.enabled)
        try await record(session)
        XCTAssertNil(recorder.speakerAudio, "Off: no audio is kept for identification")
        await session.stop()

        session.speakers.enabled = true
        try await record(session)
        XCTAssertNotNil(recorder.speakerAudio)
        await session.stop()
        await session.speakerFinalPass?.value   // turning it on loaded the models, so Stop runs a final pass
        XCTAssertFalse(session.speakers.isRunning)
    }

    // MARK: Mapping

    func testAPassLabelsLinesByTimeAndLeavesUnheardLinesAsMicrophone() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.map(\.speakerName), ["Speaker 1", "Speaker 2", "Microphone"])
        XCTAssertNil(session.segments[2].speakerID)
        XCTAssertEqual(session.speakerList.map(\.name), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(session.speakerList.map(\.lines), [1, 1])
        let samples = await diarizer.lastSampleCount()
        XCTAssertEqual(samples, 160_000, "The pass sees exactly the audio the recorder copied")
        await session.stop()
    }

    func testALineTheSpeakerBarelyCoversKeepsMicrophone() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await record(session)
        recorder.feedAudio(seconds: 10)
        recorder.send("A long line the model mostly missed.", 0, 8)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 7, duration: 2)])
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.first?.speakerName, "Microphone")
        await session.stop()
    }

    func testARenamedSpeakerSilentForMinutesIsRecognizedByVoice() async throws {
        // Issue #171: Alice says nothing through the windows' shared audio, then speaks again.
        let session = makeSession()
        session.speakers.enabled = true
        try await record(session)
        let alice: [Float] = [1, 0, 0], bob: [Float] = [0, 1, 0]
        recorder.feedAudio(seconds: 30)
        recorder.send("I'm Alice.", 0, 10)
        recorder.send("And I'm Bob.", 10, 20)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 10),
                                DiarizedSegment(speakerId: "y", start: 10, duration: 10)],
                               embeddings: ["x": alice, "y": bob])
        await session.runSpeakerPass()
        session.renameSpeaker(id: try XCTUnwrap(session.speakerList.first?.id), to: "Alice")
        // Bob alone for over three minutes; the next window starts after anything Alice said.
        recorder.feedAudio(seconds: 200)
        recorder.send("A long update.", 30, 230)
        await diarizer.respond([DiarizedSegment(speakerId: "p", start: 30, duration: 200)],
                               embeddings: ["p": bob])
        await session.runSpeakerPass()
        recorder.feedAudio(seconds: 100)
        recorder.send("I'm back.", 300, 320)
        // This window starts at 170 s; the diarizer's times are relative to it.
        await diarizer.respond([DiarizedSegment(speakerId: "s", start: 0, duration: 60),
                                DiarizedSegment(speakerId: "t", start: 130, duration: 20)],
                               embeddings: ["s": bob, "t": [0.95, 0.1, 0]])
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.map(\.speakerName), ["Alice", "Speaker 2", "Speaker 2", "Alice"])
        XCTAssertEqual(session.speakerList.count, 2, "No new speaker for a returning voice")
        await session.stop()
    }

    // MARK: Prompts, rename and persistence

    func testPromptsKeepMicrophoneAsYouAndNamedSpeakersUnchanged() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        await session.stop()
        session.renameSpeaker(id: try XCTUnwrap(session.speakerList.first?.id), to: "  Alice \n Ng ")
        XCTAssertEqual(MobileSession.promptSegment(session.segments[0]).speakerName, "Alice Ng")
        XCTAssertEqual(MobileSession.promptSegment(session.segments[1]).speakerName, "Speaker 2")
        XCTAssertNil(MobileSession.promptSegment(session.segments[2]).speakerName)
        XCTAssertTrue(session.summarySource.contains("Alice Ng: Shall we start?"))
        XCTAssertTrue(session.summarySource.contains("Speaker 2: Yes, the budget first."))
        XCTAssertTrue(session.summarySource.contains("You: Mm."))
    }

    func testRenamePersistsThroughSaveReopenExportAndSearch() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        await session.stop()
        let speaker = try XCTUnwrap(session.speakerList.last)
        session.renameSpeaker(id: speaker.id, to: "Bob")
        session.renameSpeaker(id: speaker.id, to: "   ")
        session.renameSpeaker(id: speaker.id, to: "Microphone")
        XCTAssertEqual(session.speakerList.map(\.name), ["Speaker 1", "Bob"], "Blank or device names are ignored")

        let reopened = makeSession()
        XCTAssertEqual(reopened.segments.map(\.speakerName), ["Speaker 1", "Bob", "Microphone"])
        XCTAssertEqual(reopened.speakerList.map(\.name), ["Speaker 1", "Bob"])
        XCTAssertTrue(reopened.markdown.contains("- **Bob:** Yes, the budget first."))
        XCTAssertTrue(reopened.markdown.contains("- **Microphone:** Mm."))
        let record = try XCTUnwrap(reopened.history.first)
        XCTAssertTrue(record.transcript.contains("Bob: Yes, the budget first."))
        XCTAssertTrue(record.transcript.contains("Speaker 1: Shall we start?"))
        XCTAssertTrue(MobileSession.markdown(for: record).contains("**Bob:**"))
        XCTAssertEqual(reopened.historyMatching("bob").map(\.id), [record.id])
    }

    func testRelabelingAndRenamingDoNotStartAIWork() async throws {
        let provider = CountingQuickProvider()
        let session = makeSession(provider: provider)
        let savedAuto = session.autoQuick
        defer { UserDefaults.standard.set(savedAuto, forKey: "autoQuickSummary") }
        session.speakers.enabled = true
        session.autoQuick = true
        try await recordTwoVoices(session)
        try await wait { session.quickReader.completedReads >= 1 && !session.quickReader.isReading }
        try await Task.sleep(for: .milliseconds(200))
        let before = await provider.count()

        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.first?.speakerName, "Speaker 1")
        session.renameSpeaker(id: try XCTUnwrap(session.speakerList.first?.id), to: "Alice")
        try await Task.sleep(for: .milliseconds(300))
        let after = await provider.count()
        XCTAssertEqual(after, before, "A label change is not new speech")
        XCTAssertTrue(session.quickDiagnostics.contains("Unread speech: no"))
        session.autoQuick = false
        await session.stop()
    }

    func testACorrectionThatLandsAfterLabelingKeepsTheLabel() async throws {
        let corrector = HeldCorrectionProvider()
        let recorder = recorder!, diarizer = diarizer!
        let session = MobileSession(storageDirectory: root, correctionProvider: corrector,
                                    makeRecorder: { recorder }, makeDiarizer: { diarizer })
        let savedCorrection = session.ai.correctTranscript, savedAuto = session.autoQuick
        defer { session.ai.correctTranscript = savedCorrection; session.autoQuick = savedAuto }
        session.autoQuick = false
        session.ai.correctTranscript = true
        session.speakers.enabled = true
        try await record(session)
        recorder.feedAudio(seconds: 5)
        recorder.send("Please send the meeting goats to Alex.", 0, 4)
        await diarizer.respond([DiarizedSegment(speakerId: "x", start: 0, duration: 4)])
        try await wait { corrector.isHolding }
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.first?.speakerName, "Speaker 1")
        corrector.release(#"{"text":"Please send the meeting notes to Alex."}"#)
        try await wait { session.segments.first?.originalText != nil }
        XCTAssertEqual(session.segments.first?.text, "Please send the meeting notes to Alex.")
        XCTAssertEqual(session.segments.first?.speakerName, "Speaker 1",
                       "The correction was submitted before labeling; it must not undo the label")
        XCTAssertNotNil(session.segments.first?.speakerID)
        await session.stop()
    }

    // MARK: Model failures

    func testALatchedModelFailureStopsPassesUntilRetry() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await diarizer.failModels("The Internet connection appears to be offline.")
        let outcome = await session.runSpeakerPass()
        XCTAssertEqual(outcome, .modelsUnavailable)
        XCTAssertTrue(session.speakers.isUnavailable)
        XCTAssertTrue(try XCTUnwrap(session.speakers.statusLine).contains("offline"))

        recorder.feedAudio(seconds: 5)
        _ = await session.periodicSpeakerPass()
        _ = await session.periodicSpeakerPass()
        var calls = await diarizer.calls()
        XCTAssertEqual(calls, 1, "No pass runs while the models are unavailable")
        XCTAssertEqual(Set(session.segments.compactMap(\.speakerName)), ["Microphone"])

        await diarizer.recover()
        session.retrySpeakerIdentification()
        try await wait { session.segments.first?.speakerName == "Speaker 1" }
        calls = await diarizer.calls()
        XCTAssertEqual(calls, 2)
        let retried = await diarizer.retries()
        XCTAssertEqual(retried, 1)
        XCTAssertFalse(session.speakers.isUnavailable)
        await session.stop()
    }

    func testAnotherDiarizerErrorIsReportedButDoesNotLatch() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await diarizer.failOnce()
        let outcome = await session.runSpeakerPass()
        XCTAssertEqual(outcome, .completed)
        XCTAssertFalse(session.speakers.isUnavailable)
        XCTAssertNotNil(session.speakers.statusLine)
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.first?.speakerName, "Speaker 1")
        XCTAssertEqual(session.speakers.statusLine, "Speaker labels appear about 20 s in and at Stop",
                       "A successful pass clears the skipped-pass note")
        await session.stop()
    }

    func testANewRecordingClearsALatchedFailure() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await diarizer.failModels("offline")
        await session.runSpeakerPass()
        await session.stop()
        XCTAssertTrue(session.speakers.isUnavailable)
        await diarizer.recover()
        try await record(session)
        XCTAssertFalse(session.speakers.isUnavailable)
        await session.stop()
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}

/// Watch conversations ship without speaker labels (#181 Task 14, deferred to #192). Speaker
/// identification heard only this iPhone's microphone, so it never relabels an Apple Watch line, and
/// prompts read a watch line as "You", like "Microphone".
extension MobileSpeakerTests {
    private func watchLine(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end,
                          speakerName: MobileFileTranscriber.speakerName)
    }

    func testAPassNeverRelabelsAppleWatchLines() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        // A watch drain appends to the open conversation when it is the watch recording.
        session.segments.append(watchLine("From the wrist.", 0.5, 3.5))
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.map(\.speakerName),
                       ["Speaker 1", "Speaker 2", "Microphone", "Apple Watch"])
        XCTAssertNil(session.segments[3].speakerID)
        XCTAssertEqual(session.speakerList.map(\.lines), [1, 1])
        await session.stop()
    }

    func testPromptsReadAnAppleWatchLineAsYou() async throws {
        let session = makeSession()
        session.segments = [watchLine("Ship it Friday.", 0, 2)]
        XCTAssertNil(MobileSession.promptSegment(session.segments[0]).speakerName)
        XCTAssertTrue(session.summarySource.contains("You: Ship it Friday."), session.summarySource)
        XCTAssertFalse(session.summarySource.contains("Apple Watch"))
        XCTAssertEqual(session.segments[0].speakerName, "Apple Watch", "The saved line keeps its label")
    }

    func testASpeakerCannotBeRenamedToTheWatchLabel() async throws {
        let session = makeSession()
        session.speakers.enabled = true
        try await recordTwoVoices(session)
        await session.runSpeakerPass()
        await session.stop()
        let speaker = try XCTUnwrap(session.speakerList.first)
        session.renameSpeaker(id: speaker.id, to: "Apple Watch")
        XCTAssertEqual(session.speakerList.first?.name, "Speaker 1", "A device name is not a participant")
    }
}
