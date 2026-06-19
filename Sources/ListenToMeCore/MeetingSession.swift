import Foundation
import Observation

/// Orchestrates capture -> transcription -> store -> proactive/on-demand responses.
/// Depends only on protocols, so it is fully unit-testable with mocks.
@MainActor
@Observable
public final class MeetingSession {
    public private(set) var isRunning = false
    public private(set) var isStreaming = false
    public private(set) var suggestion = ""
    public var notes = ""
    public var proactiveEnabled = true

    public let store: ConversationStore
    public let router: ModelRouter
    private var context: ContextEngine
    private let makeCapture: @Sendable () -> any AudioCapturing
    private let makeTranscriber: @Sendable () -> any Transcribing
    private var capture: (any AudioCapturing)?
    private var transcriber: (any Transcribing)?
    private let clock: @Sendable () -> TimeInterval

    private var pumpTasks: [Task<Void, Never>] = []
    private var responseTask: Task<Void, Never>?
    private var responseGeneration = 0
    private var runID = 0

    public init(store: ConversationStore,
                router: ModelRouter,
                context: ContextEngine,
                makeCapture: @escaping @Sendable () -> any AudioCapturing,
                makeTranscriber: @escaping @Sendable () -> any Transcribing,
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.router = router
        self.context = context
        self.makeCapture = makeCapture
        self.makeTranscriber = makeTranscriber
        self.clock = clock
    }

    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        runID += 1
        let myRun = runID
        let capture = makeCapture()
        let transcriber = makeTranscriber()
        // Store before the await so stop() can reach an in-flight capture (whose mic may already
        // be recording) if the user stops during permission/startup.
        self.capture = capture
        self.transcriber = transcriber
        do {
            try await capture.start()
        } catch {
            capture.stop()
            if runID == myRun {
                isRunning = false
                self.capture = nil
                self.transcriber = nil
            }
            throw error
        }
        guard isRunning, runID == myRun else { capture.stop(); return }

        let captureStream = capture.chunks
        pumpTasks.append(Task {
            for await chunk in captureStream {
                await transcriber.feed(chunk)
            }
        })

        let segmentStream = transcriber.segments
        pumpTasks.append(Task { [weak self] in
            for await segment in segmentStream {
                guard let self else { return }
                guard self.runID == myRun else { continue }   // ignore stale-session segments
                await self.ingest(segment)
            }
        })
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        responseTask?.cancel()
        capture?.stop()
        if let transcriber { Task { await transcriber.finish() } }
        capture = nil
        transcriber = nil
        pumpTasks.removeAll()
    }

    /// Applies a segment to the store and fires a proactive response when warranted.
    /// Proactive responses run in the background so the transcript pump never stalls.
    public func ingest(_ segment: TranscriptSegment) async {
        store.apply(segment)
        guard isRunning, proactiveEnabled,
              context.shouldFireProactive(for: segment, now: clock()) else { return }
        startResponse(.proactive)
    }

    /// On-demand response (hotkey / buttons). Awaits completion.
    public func respond(_ action: ResponseAction) async {
        await startResponse(action).value
    }

    /// For tests/UI that need to await the most recent response.
    public func waitForResponse() async {
        await responseTask?.value
    }

    /// Starts a streaming response, cancelling any in-flight one. Returns the task.
    @discardableResult
    private func startResponse(_ action: ResponseAction) -> Task<Void, Never> {
        responseTask?.cancel()
        responseGeneration += 1
        let generation = responseGeneration
        let request = PromptBuilder.build(
            context: context.buildContext(from: store, notes: notes),
            action: action
        )
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runResponse(request, generation: generation)
        }
        responseTask = task
        return task
    }

    private func runResponse(_ request: LLMRequest, generation: Int) async {
        guard generation == responseGeneration, !Task.isCancelled else { return }
        suggestion = ""
        isStreaming = true
        defer { if generation == responseGeneration { isStreaming = false } }
        do {
            for try await delta in router.stream(request) {
                if Task.isCancelled { return }
                if generation != responseGeneration { return }   // superseded by a newer response
                suggestion += delta
            }
        } catch {
            if generation == responseGeneration, !Task.isCancelled, !(error is CancellationError) {
                suggestion = "⚠️ \(error.localizedDescription)"
            }
        }
    }
}
