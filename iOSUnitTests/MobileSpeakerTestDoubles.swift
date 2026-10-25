import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// iOS keeps only the speaker audio the next pass can still need (issue #180).
final class SpeakerAudioBufferReleaseTests: XCTestCase {
    func testAnalyzedAudioIsReleasedButIndexesStayAbsolute() {
        let buffer = SpeakerAudioBuffer()
        let generation = buffer.currentGeneration()
        let block = SpeakerAudioBuffer.blockSize
        buffer.append(samples: (0..<(block * 3 + 10)).map { Float($0) }, sampleRate: 16_000, timestamp: 0,
                      generation: generation)
        buffer.discardAudio(before: block * 2 + 5)
        XCTAssertEqual(buffer.sampleCount, block * 3 + 10)
        XCTAssertEqual(buffer.retainedSampleCount, block + 10)
        let early = buffer.snapshot(fromSample: 0)
        XCTAssertEqual(early.startSample, block * 2, "A snapshot never starts before what is retained")
        XCTAssertEqual(early.samples.first, Float(block * 2))
        let late = buffer.snapshot(fromSample: block * 3 + 1)
        XCTAssertEqual(late.startSample, block * 3)
        XCTAssertEqual(late.samples.count, 10)
        buffer.discardAudio(before: block * 10)
        XCTAssertEqual(buffer.retainedSampleCount, 10, "The block being filled is never released")
        buffer.discardAudio(before: 0)
        XCTAssertEqual(buffer.retainedSampleCount, 10)
        buffer.reset()
        XCTAssertEqual(buffer.retainedSampleCount, 0)
        XCTAssertEqual(buffer.snapshot().startSample, 0)
    }
}

@MainActor
final class SpeakerTestRecorder: MobileRecording {
    private(set) var speakerAudio: SpeakerAudioBuffer?
    private var generation = 0
    private var receive: (@MainActor (TranscriptSegment) -> Void)?

    func attachSpeakerAudio(_ buffer: SpeakerAudioBuffer?) {
        speakerAudio = buffer
        generation = buffer?.currentGeneration() ?? 0
    }
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { receive = onSegment }
    func stop() async throws { receive = nil }
    func reconfigure() async throws {}

    /// Silence at the diarizer's own rate, so the buffer holds exactly what was fed.
    func feedAudio(seconds: Int) {
        speakerAudio?.append(samples: [Float](repeating: 0, count: seconds * 16_000), sampleRate: 16_000,
                             timestamp: 0, generation: generation)
    }

    /// A final line, in the recorder's own (per-recording) time.
    func send(_ text: String, _ start: TimeInterval, _ end: TimeInterval) {
        receive?(TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end,
                                   speakerName: MobileSession.microphoneLabel))
    }
}

actor FakeDiarizer: MobileSpeakerDiarizing {
    private var segments: [DiarizedSegment] = []
    private var embeddings: [String: [Float]] = [:]
    private var modelFailure: String?
    private var failNext = false
    private var failing = false
    private var holdNextCall = false
    private var held: CheckedContinuation<Void, Never>?
    private var callCount = 0
    private var retryCount = 0
    private var sampleCount = 0
    private var prepareCount = 0
    private var holdNextPrepareCall = false
    private var heldPrepare: CheckedContinuation<Void, Never>?

    func respond(_ segments: [DiarizedSegment], embeddings: [String: [Float]] = [:]) {
        self.segments = segments
        self.embeddings = embeddings
    }
    func failModels(_ reason: String) { modelFailure = reason }
    func failOnce() { failNext = true }
    func failAlways() { failing = true }
    func holdNext() { holdNextCall = true }
    func holding() -> Bool { held != nil }
    func release() { held?.resume(); held = nil }
    func recover() { modelFailure = nil }
    func calls() -> Int { callCount }
    func retries() -> Int { retryCount }
    func lastSampleCount() -> Int { sampleCount }
    /// Model preparations requested without audio (toggle-on, launch, Start, Retry).
    func prepares() -> Int { prepareCount }
    func holdNextPrepare() { holdNextPrepareCall = true }
    func holdingPrepare() -> Bool { heldPrepare != nil }
    func releasePrepare() { heldPrepare?.resume(); heldPrepare = nil }

    func prepareModels() async throws {
        prepareCount += 1
        if holdNextPrepareCall {
            holdNextPrepareCall = false
            await withCheckedContinuation { heldPrepare = $0 }
        }
        if let modelFailure { throw SpeakerDiarizer.DiarizationError.modelsUnavailable(modelFailure) }
    }

    func diarize(samples: [Float]) async throws -> DiarizedWindow {
        callCount += 1
        sampleCount = samples.count
        if holdNextCall {
            holdNextCall = false
            await withCheckedContinuation { held = $0 }
        }
        if failing { throw SpeakerDiarizer.DiarizationError.notEnoughAudio }
        if let modelFailure { throw SpeakerDiarizer.DiarizationError.modelsUnavailable(modelFailure) }
        if failNext { failNext = false; throw SpeakerDiarizer.DiarizationError.notEnoughAudio }
        return DiarizedWindow(segments: segments, embeddings: embeddings)
    }

    func retryModelLoad() async { retryCount += 1 }
}

/// Counts automatic Quick checks and answers each with a valid "keep" decision.
actor CountingQuickProvider: LLMProvider {
    nonisolated let id = "speaker-quick-test"
    private var requests = 0
    func count() -> Int { requests }
    private func record() { requests += 1 }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.record()
                continuation.yield(#"{"action":"keep","context":"Talked budget.","bullets":[],"reviews":[]}"#)
                continuation.finish()
            }
        }
    }
}

/// Holds one correction until the test releases it.
@MainActor
final class HeldCorrectionProvider: LLMProvider {
    nonisolated let id = "speaker-correction-test"
    private var held: AsyncThrowingStream<String, Error>.Continuation?
    var isHolding: Bool { held != nil }
    func release(_ text: String) { held?.yield(text); held?.finish(); held = nil }
    private func hold(_ continuation: AsyncThrowingStream<String, Error>.Continuation) { held = continuation }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { @MainActor in self.hold(continuation) } }
    }
}

/// Drives the session's actual periodic loop without waiting for its production interval.
actor ManualSpeakerClock {
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var order: [UUID] = []

    func sleep(_ delay: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waiters[id] = continuation
                order.append(id)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        order.removeAll { $0 == id }
    }

    func advance() -> Bool {
        guard let id = order.first else { return false }
        order.removeFirst()
        waiters.removeValue(forKey: id)?.resume()
        return true
    }
}
