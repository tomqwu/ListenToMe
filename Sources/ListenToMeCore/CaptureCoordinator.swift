import Foundation
import Observation

/// Owns asynchronous capture transitions independently of a view or platform recorder.
/// Adapters supply device work and persistence; a run token fences late recorder callbacks.
@MainActor @Observable
public final class CaptureCoordinator {
    public enum Phase: Equatable { case idle, preparing, recording, stopping }
    public struct Run: Equatable, Sendable { fileprivate let id = UUID() }
    public struct Operations {
        let prepare: @MainActor () async throws -> Void
        let start: @MainActor () async throws -> Void
        let stop: @MainActor () async throws -> Void
        let interrupt: @MainActor () -> Void
        let didStart: @MainActor () -> Void
        let didFinish: @MainActor (Error?, Bool) -> Void

        public init(prepare: @escaping @MainActor () async throws -> Void,
                    start: @escaping @MainActor () async throws -> Void,
                    stop: @escaping @MainActor () async throws -> Void,
                    interrupt: @escaping @MainActor () -> Void = {},
                    didStart: @escaping @MainActor () -> Void,
                    didFinish: @escaping @MainActor (Error?, Bool) -> Void) {
            self.prepare = prepare; self.start = start; self.stop = stop
            self.interrupt = interrupt
            self.didStart = didStart; self.didFinish = didFinish
        }
    }

    public private(set) var phase = Phase.idle
    public private(set) var wantsCapture = false
    @ObservationIgnored private var restarting = false
    @ObservationIgnored private var restartGeneration = UUID()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored public var phaseChanged: (@MainActor (Phase) -> Void)?
    @ObservationIgnored private var completions: [@MainActor () -> Void] = []
    @ObservationIgnored private var isCompleting = false
    @ObservationIgnored private var run: Run?
    @ObservationIgnored private var operations: Operations?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    public init() {}

    /// Includes final utterances emitted while Stop drains, but excludes completed and superseded runs.
    public func acceptsEvents(from candidate: Run) -> Bool { run == candidate && phase != .idle }

    @discardableResult
    public func start(_ makeOperations: (Run) -> Operations) -> Bool {
        guard phase == .idle, !isCompleting else { return false }
        wantsCapture = true
        interrupted = false
        let token = Run()
        run = token
        let work = makeOperations(token)
        operations = work
        transition(to: .preparing)
        startTask = Task {
            do {
                try Task.checkCancellation()
                try await work.prepare()
                try Task.checkCancellation()
                try await work.start()
                try Task.checkCancellation()
                transition(to: .recording)
                work.didStart()
                startTask = nil
            } catch {
                // A late OS failure after Stop belongs to the cancelled run, not the current UI.
                let wasCancelled = Task.isCancelled || error is CancellationError
                // Even failed preparation can allocate platform resources. Drain exactly once.
                transition(to: .stopping)
                try? await work.stop()
                finish(work, error: wasCancelled ? nil : error, wasRecording: false)
            }
        }
        return true
    }

    /// Concurrent callers join the same teardown. Starting again is disabled until it finishes.
    public func stop() async {
        revokeRecordingIntent()
        await stopRun()
    }

    /// Checkpoints run synchronously before another Start can enter. Optional work runs separately;
    /// adapters must fence that work to the stopped conversation/run.
    public func requestStop(after completion: @escaping @MainActor () -> Void = {},
                            background: @escaping @MainActor () async -> Void = {}) {
        revokeRecordingIntent()
        completions.append {
            completion()
            Task { await background() }
        }
        if phase == .idle {
            if !isCompleting { finishCompletions() }
        } else {
            Task { await stopRun() }
        }
    }

    /// A newer locale supersedes an older queued restart. Stop always wins over both.
    public func restart(_ makeOperations: @escaping @MainActor (Run) -> Operations) {
        guard wantsCapture else { return }
        restartTask?.cancel()
        let generation = UUID()
        restartGeneration = generation
        restarting = true
        restartTask = Task {
            await stopRun()
            guard restartGeneration == generation else { return }
            defer { restarting = false; restartTask = nil }
            guard wantsCapture, !Task.isCancelled else { return }
            start(makeOperations)
        }
    }

    private func revokeRecordingIntent() {
        wantsCapture = false
        restarting = false
        restartGeneration = UUID()
        restartTask?.cancel(); restartTask = nil
        startTask?.cancel()
    }

    private func stopRun() async {
        if let stopping = stopTask { await stopping.value; return }
        if let starting = startTask {
            starting.cancel()
            if !interrupted { interrupted = true; operations?.interrupt() }
            transition(to: .stopping)
            await starting.value
            return
        }
        guard phase == .recording, let work = operations else { return }
        transition(to: .stopping)
        let task = Task {
            var failure: Error?
            do { try await work.stop() } catch { failure = error }
            finish(work, error: failure, wasRecording: true)
        }
        stopTask = task
        await task.value
    }

    private func transition(to phase: Phase) {
        guard self.phase != phase else { return }
        self.phase = phase
        phaseChanged?(phase)
    }

    private func finish(_ work: Operations, error: Error?, wasRecording: Bool) {
        if !restarting || error != nil { wantsCapture = false }
        run = nil; operations = nil; startTask = nil; stopTask = nil
        // Publish idle for final checkpoints, but refuse reentrant starts until cleanup is complete.
        isCompleting = true
        transition(to: .idle)
        work.didFinish(error, wasRecording)
        finishCompletions()
    }

    private func finishCompletions() {
        isCompleting = true
        while !completions.isEmpty {
            let ready = completions
            completions = []
            for completion in ready { completion() }
        }
        isCompleting = false
    }
}
