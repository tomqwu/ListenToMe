import AVFoundation
import Foundation
import ListenToMeCore
import XCTest

/// Real streaming inference. The file probe controls preparation/cancellation only; voice output
/// always comes from the production LS-EEND model and the checked-in synthetic audio.
@MainActor
final class SpeakerStreamingModelTests: XCTestCase {
    func testOverlappingWindowsAndFinalFlushDoNotFeedAudioTwice() async throws {
        let audio = try load("returning-two-voices")
        let model = MobileSpeakers.productionDiarizer()
        let prefix = Array(audio.prefix(20 * 16_000))
        let first = try await model.diarizeLive(samples: prefix, startingAtSample: 0, runToken: 1, final: false)
        let duplicate = try await model.diarizeLive(samples: prefix, startingAtSample: 0, runToken: 1, final: false)
        XCTAssertEqual(first, duplicate, "Repeating a window cannot advance the model clock")
        let growing = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        let shifted = try await model.diarizeLive(samples: Array(audio.dropFirst(10 * 16_000)),
                                                  startingAtSample: 10 * 16_000, runToken: 1, final: false)
        XCTAssertEqual(shifted.stableSpeakerIDScope, growing.stableSpeakerIDScope)
        XCTAssertEqual(try XCTUnwrap(shifted.analyzedThrough), try XCTUnwrap(growing.analyzedThrough) - 10,
                       accuracy: 0.001, "A moving overlap must not feed or advance already-seen audio")
        let cropped = growing.segments.compactMap { segment -> DiarizedSegment? in
            let lower = max(10, segment.start)
            let upper = segment.start + segment.duration
            guard upper > lower else { return nil }
            return DiarizedSegment(speakerId: segment.speakerId, start: lower - 10, duration: upper - lower)
        }
        XCTAssertEqual(shifted.segments.count, cropped.count)
        for (actual, expected) in zip(shifted.segments, cropped) {
            XCTAssertEqual(actual.speakerId, expected.speakerId)
            XCTAssertEqual(actual.start, expected.start, accuracy: 0.001)
            XCTAssertEqual(actual.duration, expected.duration, accuracy: 0.001)
        }
        let final = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: true)
        let again = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: true)
        XCTAssertEqual(final, again, "Stop may drain the decoder only once")
        XCTAssertEqual(first.stableSpeakerIDScope, final.stableSpeakerIDScope)
        let duration = Double(audio.count) / 16_000
        XCTAssertLessThanOrEqual(try XCTUnwrap(growing.analyzedThrough), duration)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(final.analyzedThrough), try XCTUnwrap(growing.analyzedThrough))
        XCTAssertEqual(try XCTUnwrap(final.analyzedThrough), duration, accuracy: 0.11)
        XCTAssertTrue(final.segments.allSatisfy { $0.start >= 0 && $0.start + $0.duration <= duration + 0.001 })
        try assertKnownTurns(final, fixture: "returning-two-voices")
    }

    func testRejectedAudioAfterFinalFlushDoesNotEraseTheCompletedResult() async throws {
        let model = MobileSpeakers.productionDiarizer()
        let audio = try load("brief-two-voices")
        let final = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: true)
        do {
            _ = try await model.diarizeLive(samples: audio + [Float](repeating: 0, count: 16_000),
                                            startingAtSample: 0, runToken: 1, final: false)
            XCTFail("A finalized recording cannot accept more audio")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await model.diarizeLive(samples: audio, startingAtSample: 40 * 16_000,
                                            runToken: 1, final: false)
            XCTFail("A late callback after a gap cannot reopen a finalized recording")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let repeated = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: true)
        XCTAssertEqual(repeated, final, "A rejected late callback must not reset a completed recording")
    }

    func testGapAndNewRecordingCreateFreshEpochsAndOldCleanupCannotResetThem() async throws {
        let model = MobileSpeakers.productionDiarizer()
        let audio = try load("brief-two-voices")
        let first = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        let gap = try await model.diarizeLive(samples: audio, startingAtSample: 40 * 16_000, runToken: 1, final: false)
        XCTAssertNotEqual(first.stableSpeakerIDScope, gap.stableSpeakerIDScope,
                          "Unheard audio cannot silently carry a previous person's slot identity")
        let next = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 2, final: false)
        XCTAssertNotEqual(gap.stableSpeakerIDScope, next.stableSpeakerIDScope)
        await model.endRun(token: 1)
        let afterOldCleanup = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 2, final: false)
        XCTAssertEqual(afterOldCleanup, next)
        do {
            _ = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: true)
            XCTFail("A closed recording cannot re-enter the model")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testLongRecordingBoundsPredictionHistoryWithoutResettingItsIdentityOrClock() async throws {
        let model = try XCTUnwrap(MobileSpeakers.productionDiarizer() as? MobileConversationDiarizer)
        let audio = try load("brief-two-voices")
        let first = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        let firstSlots = try assertKnownTurns(first, fixture: "brief-two-voices", completeTurnsOnly: true)
        var tracker = SpeakerIdentityTracker(namespace: "long-recording")
        let firstMapping = tracker.reconcile(first.segments, stableSpeakerIDScope: first.stableSpeakerIDScope)
        let danielSlot = try XCTUnwrap(firstSlots["Daniel"])
        let daniel = try XCTUnwrap(firstMapping[danielSlot])
        tracker.rename(id: daniel.id, name: "Known Daniel")
        let silence = [Float](repeating: 0, count: 20 * 16_000)
        for start in stride(from: 20, to: 640, by: 20) {
            let window = try await model.diarizeLive(samples: silence, startingAtSample: start * 16_000,
                                                     runToken: 1, final: false)
            XCTAssertEqual(window.stableSpeakerIDScope, first.stableSpeakerIDScope)
        }
        let retained = await model.retainedPredictionFrames
        XCTAssertGreaterThan(retained, 0)
        XCTAssertLessThanOrEqual(retained, 6_000, "Actual retained probabilities must remain bounded")
        let returning = try await model.diarizeLive(samples: audio, startingAtSample: 640 * 16_000, runToken: 1, final: true)
        XCTAssertEqual(returning.stableSpeakerIDScope, first.stableSpeakerIDScope)
        XCTAssertEqual(try XCTUnwrap(returning.analyzedThrough), 20, accuracy: 0.11,
                       "Trimming old probabilities must not rewind absolute model time")
        let returningSlots = try assertKnownTurns(returning, fixture: "brief-two-voices")
        XCTAssertEqual(returningSlots, firstSlots, "Each actual voice must retain its slot; an exchanged pair is wrong")
        let later = returning.segments.map {
            DiarizedSegment(speakerId: $0.speakerId, start: $0.start + 640, duration: $0.duration)
        }
        let nextMapping = tracker.reconcile(later, since: 640, stableSpeakerIDScope: returning.stableSpeakerIDScope)
        XCTAssertEqual(nextMapping[try XCTUnwrap(returningSlots["Daniel"])]?.id, daniel.id)
        XCTAssertEqual(nextMapping[try XCTUnwrap(returningSlots["Daniel"])]?.name, "Known Daniel")
        await model.endRun(token: 1)
        let ended = await model.retainedPredictionFrames
        XCTAssertEqual(ended, 0)
    }

    func testFileReadinessFailureRequiresRetryAndFileAnalysisCannotMutateLiveState() async throws {
        let file = SpeakerFilePreparationProbe(fail: true)
        let model = MobileConversationDiarizer(fileModel: file)
        let audio = try load("brief-two-voices")
        do { _ = try await model.diarize(samples: audio); XCTFail("Imports cannot initiate model downloads") }
        catch {}
        var calls = await file.counts()
        XCTAssertEqual(calls.prepare, 0)
        XCTAssertEqual(calls.analyze, 0)
        do { try await model.prepareModels(); XCTFail("Both pipelines must be ready") } catch {}
        do { try await model.prepareModels(); XCTFail("The preparation failure must remain latched") } catch {}
        calls = await file.counts()
        XCTAssertEqual(calls.prepare, 1)
        await model.retryModelLoad()
        try await model.prepareModels()
        let first = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        let imported = try await model.diarize(samples: audio)
        XCTAssertEqual(imported.segments.first?.speakerId, "import-only")
        let afterImport = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false)
        XCTAssertEqual(afterImport, first)
        calls = await file.counts()
        XCTAssertEqual(calls.prepare, 2)
        XCTAssertEqual(calls.retry, 1)
        XCTAssertEqual(calls.analyze, 1)
    }

    func testCancellationDuringPreparationCannotFeedAnEndedRun() async throws {
        let file = SpeakerFilePreparationProbe(hold: true)
        let model = MobileConversationDiarizer(fileModel: file)
        let audio = try load("brief-two-voices")
        let pending = Task { try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 1, final: false) }
        for _ in 0..<5_000 {
            if await file.counts().prepare > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let entered = await file.counts().prepare
        XCTAssertEqual(entered, 1, "Cancel only after real live preparation reached the held file gate")
        pending.cancel()
        await file.release()
        do { _ = try await pending.value; XCTFail("Cancelled preparation cannot produce labels") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await model.endRun(token: 1)
        let retained = await model.retainedPredictionFrames
        XCTAssertEqual(retained, 0)
        let next = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 2, final: true)
        try assertKnownTurns(next, fixture: "brief-two-voices")
        await model.endRun(token: 1)
        let repeated = try await model.diarizeLive(samples: audio, startingAtSample: 0, runToken: 2, final: true)
        XCTAssertEqual(repeated, next)
    }

    private func directory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Speakers")
    }

    private func load(_ name: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: directory().appendingPathComponent(name + ".wav"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
    }

    @discardableResult
    private func assertKnownTurns(_ window: DiarizedWindow, fixture: String, completeTurnsOnly: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line) throws -> [String: String] {
        struct Manifest: Decodable { struct Turn: Decodable { let voice: String; let start: Double; let end: Double }; let turns: [Turn] }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: directory().appendingPathComponent(fixture + ".json")))
        var voiceSlots: [String: String] = [:]
        for turn in manifest.turns {
            if completeTurnsOnly, turn.end > (window.analyzedThrough ?? 0) { continue }
            let totals = window.segments.reduce(into: [String: Double]()) { totals, segment in
                totals[segment.speakerId, default: 0] += max(0, min(turn.end, segment.start + segment.duration) - max(turn.start, segment.start))
            }
            let best = try XCTUnwrap(totals.max { $0.value < $1.value }, file: file, line: line)
            XCTAssertGreaterThanOrEqual(best.value, (turn.end - turn.start) * 0.3, file: file, line: line)
            if let slot = voiceSlots[turn.voice] { XCTAssertEqual(best.key, slot, file: file, line: line) }
            else { voiceSlots[turn.voice] = best.key }
        }
        XCTAssertEqual(Set(voiceSlots.values).count, Set(manifest.turns.map(\.voice)).count,
                       "Known different voices must not merge", file: file, line: line)
        return voiceSlots
    }
}

private actor SpeakerFilePreparationProbe: MobileSpeakerDiarizing {
    private var fail: Bool
    private var hold: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private var preparation = 0
    private var analysis = 0
    private var retries = 0
    init(fail: Bool = false, hold: Bool = false) { self.fail = fail; self.hold = hold }
    func counts() -> (prepare: Int, analyze: Int, retry: Int) { (preparation, analysis, retries) }
    func prepareModels() async throws {
        preparation += 1
        if hold { await withCheckedContinuation { waiter = $0 } }
        if fail { throw SpeakerDiarizer.DiarizationError.modelsUnavailable("File assets unavailable") }
    }
    func retryModelLoad() { retries += 1; fail = false }
    func diarize(samples: [Float]) -> DiarizedWindow {
        analysis += 1
        return DiarizedWindow(segments: [DiarizedSegment(speakerId: "import-only", start: 0, duration: 3)])
    }
    func release() { hold = false; waiter?.resume(); waiter = nil }
}
