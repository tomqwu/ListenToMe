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
        let didStart: @MainActor () -> Void
        let didFinish: @MainActor (Error?, Bool) -> Void

        public init(prepare: @escaping @MainActor () async throws -> Void,
                    start: @escaping @MainActor () async throws -> Void,
                    stop: @escaping @MainActor () async throws -> Void,
                    didStart: @escaping @MainActor () -> Void,
                    didFinish: @escaping @MainActor (Error?, Bool) -> Void) {
            self.prepare = prepare; self.start = start; self.stop = stop
            self.didStart = didStart; self.didFinish = didFinish
        }
    }

    public private(set) var phase = Phase.idle
    @ObservationIgnored public var phaseChanged: (@MainActor (Phase) -> Void)?
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
                // Even failed preparation can allocate platform resources. Drain exactly once.
                transition(to: .stopping)
                try? await work.stop()
                finish(work, error: error is CancellationError ? nil : error, wasRecording: false)
            }
        }
        return true
    }

    /// Concurrent callers join the same teardown. Starting again is disabled until it finishes.
    public func stop() async {
        if let stopping = stopTask { await stopping.value; return }
        if let starting = startTask {
            starting.cancel()
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
        run = nil; operations = nil; startTask = nil; stopTask = nil
        // Publish idle for final checkpoints, but refuse reentrant starts until cleanup is complete.
        isCompleting = true
        transition(to: .idle)
        work.didFinish(error, wasRecording)
        isCompleting = false
    }
}
