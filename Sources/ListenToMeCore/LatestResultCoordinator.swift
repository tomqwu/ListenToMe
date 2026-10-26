import Foundation

/// A window/run owns one background value request. Only its latest active result may publish.
@MainActor
public final class LatestResultCoordinator<Value: Sendable> {
    private var generation = UUID()
    private var task: Task<Void, Never>?
    public init() {}

    @discardableResult
    public func start(load: @escaping @MainActor () async -> Value,
                      apply: @escaping @MainActor (Value) -> Void) -> Task<Void, Never> {
        cancel()
        let token = generation
        let work = Task {
            defer { if token == generation { task = nil } }
            guard !Task.isCancelled, token == generation else { return }
            let value = await load()
            guard !Task.isCancelled, token == generation else { return }
            apply(value)
        }
        task = work
        return work
    }

    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
    }
}
