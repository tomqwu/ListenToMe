import AVFoundation
import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// Hours-long Apple Watch recordings must reach History even when the iPhone leaves the foreground
/// partway through the import (WATCH-017).
@MainActor
final class MobileWatchLongRecordingTests: XCTestCase {
    private var root: URL!
    private var priorEnabled: Any?
    private var priorLanguage: Any?
    private var priorAutomatic: Any?
    private let recordingID = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    /// Each test part is 30 s of audio, so one diarization window covers two parts.
    private let partSeconds = 30

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        priorEnabled = UserDefaults.standard.object(forKey: MobileSpeakers.enabledKey)
        priorLanguage = UserDefaults.standard.object(forKey: MobileSession.languageKey)
        priorAutomatic = UserDefaults.standard.object(forKey: MobileLanguageDetection.automaticKey)
        UserDefaults.standard.set(true, forKey: MobileSpeakers.enabledKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(priorEnabled, forKey: MobileSpeakers.enabledKey)
        UserDefaults.standard.set(priorLanguage, forKey: MobileSession.languageKey)
        UserDefaults.standard.set(priorAutomatic, forKey: MobileLanguageDetection.automaticKey)
        try? FileManager.default.removeItem(at: root)
    }

    private func deliverPart(_ session: MobileSession, _ index: Int, isLast: Bool) throws {
        let url = root.appendingPathComponent("delivery-\(index).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for _ in 0..<partSeconds { try file.write(from: buffer) }
        let seconds = TimeInterval(partSeconds)
        let metadata = WatchChunkMetadata(recordingID: recordingID, index: index, startOffset: TimeInterval(index) * seconds,
                                          duration: seconds, isLast: isLast, startedAt: startedAt, watchBuild: "test")
        XCTAssertEqual(session.watchInbox.accept(fileAt: url, metadata: metadata.transferMetadata, now: Date()), .stored)
    }

    private func partExists(_ session: MobileSession, _ index: Int) -> Bool {
        FileManager.default.fileExists(atPath: session.watchInbox.chunkURL(recordingID: recordingID, index: index).path)
    }

    /// Given a long Watch recording with speaker identification on, when the iPhone leaves the
    /// foreground partway through the import, then the parts already handled are saved as text and
    /// their audio is gone, and the next foreground finishes the rest without repeating any line.
    func testInterruptedLongImportKeepsProgressAndResumes() async throws {
        let parts = 8
        let model = LongRecordingSpeakerModel(holdAtPass: 3)
        let transcriber = FakeWatchTranscriber()
        for index in 0..<parts {
            let start = TimeInterval(index * partSeconds)
            transcriber.script[index] = [.init(text: "Part \(index)", start: start + 1,
                                               end: start + TimeInterval(partSeconds))]
        }
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() },
                                    makeWatchTranscriber: { transcriber }, makeDiarizer: { model })
        session.applicationIsActive = { true }
        session.languageChoice = "en-US"
        session.speakers.startPreparing()
        await session.speakers.preparation?.value
        for index in 0..<parts { try deliverPart(session, index, isLast: index == parts - 1) }

        session.importWatchInbox()
        for _ in 0..<500 {
            if await model.isHolding { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let holding = await model.isHolding
        XCTAssertTrue(holding, "The speaker model reached its third window")
        // The iPhone leaves the foreground (screen lock): the drain is cancelled.
        session.watchDrainTask?.cancel()
        await session.watchDrainTask?.value
        await model.release()

        let record = try XCTUnwrap(session.history.first { MobileSession.isFromAppleWatch($0) },
                                   "Text from the parts already handled is in History")
        let saved = record.segments?.map(\.text) ?? []
        XCTAssertFalse(saved.isEmpty, "An interruption keeps the parts already transcribed")
        XCTAssertEqual(saved, (0..<saved.count).map { "Part \($0)" })
        XCTAssertFalse(partExists(session, 0), "Audio already saved as text is removed")
        XCTAssertTrue(transcriber.calls.allSatisfy { $0.count <= MobileSession.watchPartsPerPass },
                      "Each pass handles a bounded number of parts: \(transcriber.calls)")

        session.importWatchInbox()
        await session.watchDrainTask?.value
        let finished = try XCTUnwrap(session.history.first { MobileSession.isFromAppleWatch($0) })
        XCTAssertEqual(finished.segments?.map(\.text), (0..<parts).map { "Part \($0)" })
        XCTAssertEqual(finished.isComplete, true)
        XCTAssertTrue((0..<parts).allSatisfy { !partExists(session, $0) })
    }
}

/// Diarizes a single voice and suspends on one pass until released.
private actor LongRecordingSpeakerModel: MobileSpeakerDiarizing {
    private let holdAtPass: Int
    private var passes = 0
    private var gate: CheckedContinuation<Void, Never>?
    var isHolding: Bool { gate != nil }

    init(holdAtPass: Int) { self.holdAtPass = holdAtPass }

    func release() { gate?.resume(); gate = nil }
    func prepareModels() async throws {}
    func retryModelLoad() async {}
    func diarize(samples: [Float]) async throws -> DiarizedWindow {
        passes += 1
        if passes == holdAtPass { await withCheckedContinuation { gate = $0 } }
        return DiarizedWindow(segments: [DiarizedSegment(speakerId: "voice", start: 0,
                                                        duration: Double(samples.count) / 16_000)],
                              embeddings: ["voice": [1, 0]])
    }
}
