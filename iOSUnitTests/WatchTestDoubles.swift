import Foundation
import ListenToMeCore
@testable import ListenToMeIOS

/// Records every status the session publishes to the Apple Watch (issue #181).
@MainActor
final class FakeWatchLink: WatchLinking {
    private(set) var published: [PhoneRecorderStatus] = []

    func publish(_ status: PhoneRecorderStatus) { published.append(status) }
}

/// What happened, in order, across the fake transcriber and the fake recorder.
@MainActor
final class WatchEventLog {
    var events: [String] = []
}

/// Stands in for `MobileFileTranscriber`: scripted final lines per chunk, in recording time.
@MainActor
final class FakeWatchTranscriber: WatchAudioTranscribing {
    struct Line {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Final lines delivered for each chunk index.
    var script: [Int: [Line]] = [:]
    /// Suspends before delivering this chunk until `release()` or cancellation.
    var gateBefore: Int?
    /// Thrown before this chunk's lines are delivered.
    var failBefore: (index: Int, error: any Error)?
    /// Thrown after this chunk's lines are delivered.
    var failAfter: (index: Int, error: any Error)?
    /// Called after each line is delivered, with how many have been delivered so far.
    var onLine: ((Int) -> Void)?
    private var delivered = 0
    private(set) var locales: [Locale] = []
    /// The chunk indices of every call, in order.
    private(set) var calls: [[Int]] = []
    let events: WatchEventLog
    private var gate: CheckedContinuation<Void, Never>?

    init(events: WatchEventLog = WatchEventLog()) {
        self.events = events
    }

    var isWaiting: Bool { gate != nil }

    func release() {
        gate?.resume()
        gate = nil
    }

    func transcribe(_ chunks: [WatchAudioChunk], locale: Locale,
                    onFinal: @escaping @MainActor (TranscriptSegment) throws -> Void) async throws {
        locales.append(locale)
        calls.append(chunks.map(\.index))
        for chunk in chunks {
            if chunk.index == gateBefore {
                gateBefore = nil
                await withTaskCancellationHandler {
                    await withCheckedContinuation { gate = $0 }
                } onCancel: {
                    Task { @MainActor in self.release() }
                }
            }
            if Task.isCancelled {
                events.events.append("drainCancelled")
                throw CancellationError()
            }
            if let failBefore, failBefore.index == chunk.index { throw failBefore.error }
            for line in script[chunk.index] ?? [] {
                try onFinal(TranscriptSegment(source: .you, text: line.text, isFinal: true, start: line.start,
                                              end: line.end, speakerName: MobileFileTranscriber.speakerName))
                delivered += 1
                onLine?(delivered)
            }
            if let failAfter, failAfter.index == chunk.index { throw failAfter.error }
        }
    }
}

/// A recorder that only logs when it starts and stops.
@MainActor
final class EventLoggingRecorder: MobileRecording {
    let events: WatchEventLog

    init(events: WatchEventLog) {
        self.events = events
    }

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { events.events.append("recorderStart") }
    func stop() async throws { events.events.append("recorderStop") }
    func reconfigure() async throws {}
}

/// A recorder whose Stop does not return until the test lets it, like a long transcript finalizing.
@MainActor
final class SlowStopRecorder: MobileRecording {
    private(set) var stopCount = 0
    private var held: CheckedContinuation<Void, Never>?

    var isStopping: Bool { held != nil }

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {}
    func stop() async throws {
        stopCount += 1
        await withCheckedContinuation { held = $0 }
    }
    func reconfigure() async throws {}

    func finishStop() {
        held?.resume()
        held = nil
    }
}
