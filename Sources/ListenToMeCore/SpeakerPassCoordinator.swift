import Foundation

/// Owns a platform's explicit/periodic speaker pass and its preparation barrier. Resetting a run
/// invalidates pending preparation even when the model loader ignores task cancellation.
/// The adapter still guards results produced during an already-started analysis against its run ID.
@MainActor
public final class SpeakerPassCoordinator {
    private var generation = UUID()
    private var task: Task<Void, Never>?
    public var isRunning: Bool { task != nil }

    public init() {}

    @discardableResult
    public func start(prepare: @escaping @MainActor () async -> Void = {},
                      operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        cancel()
        let token = generation
        let next = Task { [weak self] in
            defer {
                if self?.generation == token { self?.task = nil }
            }
            guard !Task.isCancelled else { return }
            await prepare()
            guard let self, self.generation == token, !Task.isCancelled else { return }
            await operation()
        }
        task = next
        return next
    }

    /// Wait only for the pass observed on entry. A later recording never extends this wait.
    public func wait() async { await task?.value }

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
