import Foundation
import Observation

/// New is a save transaction: it must finish the current drain and save decision before reset.
@MainActor @Observable
public final class NewConversationCoordinator {
    public private(set) var isBusy = false
    @ObservationIgnored private var task: Task<Void, Never>?
    public init() {}

    @discardableResult
    public func begin(checkpoint: @escaping @MainActor () -> Void,
                      stop: @escaping @MainActor () async -> Void,
                      persist: @escaping @MainActor () -> Bool,
                      resolveUnsaved: @escaping @MainActor () -> Bool,
                      reset: @escaping @MainActor (_ persisted: Bool) -> Void) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        task = Task {
            defer { isBusy = false; task = nil }
            checkpoint()
            await stop()
            let persisted = persist()
            guard persisted || resolveUnsaved() else { return }
            reset(persisted)
        }
        return true
    }

    public func wait() async { await task?.value }
}
