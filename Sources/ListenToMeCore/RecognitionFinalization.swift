import Foundation

/// Waits for the specific recognition tasks present at Stop, including callbacks that arrive
/// before the waiter starts. A deadline or cancellation closes the drain permanently.
public actor RecognitionFinalization {
    private var pending: Set<UUID>
    private var result: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    public init(tokens: Set<UUID>) {
        pending = tokens
        if tokens.isEmpty { result = true }
    }

    public func complete(_ token: UUID) {
        guard result == nil else { return }
        pending.remove(token)
        if pending.isEmpty { resolve(true) }
    }

    public func wait(timeout: Duration) async -> Bool {
        if Task.isCancelled { resolve(false) }
        if let result { return result }
        let deadline = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            resolve(false)
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let result { continuation.resume(returning: result) }
                else { waiters.append(continuation) }
            }
        } onCancel: {
            Task { await self.resolve(false) }
        }
    }

    private func resolve(_ success: Bool) {
        guard result == nil else { return }
        result = success
        let completed = waiters
        waiters.removeAll()
        for waiter in completed { waiter.resume(returning: success) }
    }
}
