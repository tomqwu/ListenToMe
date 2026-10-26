import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// These probes test native control wiring, not model accuracy. The real model is mandatory in
/// SpeakerModelQualityTests on the local Mac; supplying two identities here cannot replace it.
@MainActor
final class MobileStreamingSpeakerTests: MobileSpeakerTestCase {
    func testStopFlushesDelayedWordsEvenWhenNoNewSamplesArrive() async throws {
        let probe = StreamingSpeakerProbe()
        let recorder = recorder!
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder }, makeDiarizer: { probe })
        session.speakers.enabled = true
        try await record(session)
        recorder.feedAudio(seconds: 4)
        recorder.send("First voice.", 0, 2)
        recorder.send("Last brief voice.", 3, 4)
        await probe.respond(DiarizedWindow(segments: [DiarizedSegment(speakerId: "a", start: 0, duration: 2)],
                                           stableSpeakerIDScope: "recording", analyzedThrough: 3))
        await session.runSpeakerPass()
        XCTAssertEqual(session.segments.map(\.speakerName), ["Speaker 1", "Microphone"])
        await probe.respond(DiarizedWindow(segments: [DiarizedSegment(speakerId: "a", start: 0, duration: 2),
                                                     DiarizedSegment(speakerId: "b", start: 3, duration: 1)],
                                           stableSpeakerIDScope: "recording", analyzedThrough: 4))
        await session.stop()
        await session.speakerFinalPass?.value
        XCTAssertEqual(session.segments.map(\.speakerName), ["Speaker 1", "Speaker 2"])
        let calls = await probe.requests()
        XCTAssertEqual(calls.map(\.final), [false, true], "Stop must flush the model's right context without new audio")
        XCTAssertEqual(calls.map(\.start), [0, 0])
        let legacy = await probe.legacyCalls()
        XCTAssertEqual(legacy, 0, "The live route must not call the independent file pipeline")
        for _ in 0..<100 where (await probe.endedRuns()).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let ended = await probe.endedRuns()
        XCTAssertEqual(ended, calls.first.map { [$0.token] } ?? [])
    }

    func testDisablingSpeakerIdentificationReleasesItsRunAndRejectsLateResults() async throws {
        let probe = StreamingSpeakerProbe()
        let recorder = recorder!
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder }, makeDiarizer: { probe })
        session.speakers.enabled = true
        try await record(session)
        recorder.feedAudio(seconds: 4)
        recorder.send("Held voice.", 0, 4)
        await probe.respond(DiarizedWindow(segments: [DiarizedSegment(speakerId: "a", start: 0, duration: 4)],
                                           stableSpeakerIDScope: "held", analyzedThrough: 4))
        await probe.holdNext()
        let pass = Task { await session.runSpeakerPass() }
        for _ in 0..<200 where !(await probe.isHolding()) { try await Task.sleep(for: .milliseconds(5)) }
        let holding = await probe.isHolding()
        XCTAssertTrue(holding)
        session.speakers.enabled = false
        XCTAssertFalse(session.speakers.isRunning)
        XCTAssertEqual(recorder.speakerAudio?.retainedSampleCount, 0)
        recorder.feedAudio(seconds: 1)
        XCTAssertEqual(recorder.speakerAudio?.retainedSampleCount, 0, "The old audio callback is fenced after opt-out")
        XCTAssertEqual(session.state, .recording, "Speaker opt-out must not stop independent transcription")
        await probe.release()
        _ = await pass.value
        XCTAssertFalse(session.hasSpeakerLabels)
        await session.stop()
    }
}

actor StreamingSpeakerProbe: MobileSpeakerDiarizing {
    struct Request: Sendable { let start: Int; let token: Int; let final: Bool }
    nonisolated let requiresFinalFlush = true
    private var window = DiarizedWindow(segments: [])
    private var calls: [Request] = []
    private var legacyCount = 0
    private var ended: [Int] = []
    private var shouldHold = false
    private var held: CheckedContinuation<Void, Never>?
    func respond(_ window: DiarizedWindow) { self.window = window }
    func requests() -> [Request] { calls }
    func legacyCalls() -> Int { legacyCount }
    func endedRuns() -> [Int] { ended }
    func prepareModels() async throws {}
    func retryModelLoad() async {}
    func holdNext() { shouldHold = true }
    func isHolding() -> Bool { held != nil }
    func release() { held?.resume(); held = nil }
    func endRun(token: Int) async { ended.append(token) }
    func diarize(samples: [Float]) async throws -> DiarizedWindow {
        legacyCount += 1
        if shouldHold { shouldHold = false; await withCheckedContinuation { held = $0 } }
        return window
    }
    func diarizeLive(samples: [Float], startingAtSample: Int, runToken: Int, final: Bool) async throws -> DiarizedWindow {
        calls.append(Request(start: startingAtSample, token: runToken, final: final))
        if shouldHold { shouldHold = false; await withCheckedContinuation { held = $0 } }
        return window
    }
}
