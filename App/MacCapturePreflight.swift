import Foundation
import ListenToMeCore

/// The Mac adapter's capability → permission ordering; no capture or prompt precedes readiness.
@MainActor
enum MacCapturePreflight {
    static func prepare(gate: CaptureStartGate,
                        refresh: @escaping () async -> FeatureAvailability,
                        permission: (() async -> CapturePreflight.Decision)?,
                        blocked: @escaping (String) -> Void) async throws {
        guard let token = gate.begin() else { throw CancellationError() }
        defer { gate.finish(token) }
        // OS metadata/consent callbacks need not observe Task cancellation. Only this resource-free
        // preflight may be abandoned; the capture coordinator still owns real capture teardown.
        let reply = PreflightReply()
        let worker = Task {
            do {
                let ready = try await gate.perform(token, prepare: {
                    await refresh().canRun
                }, authorize: {
                    guard let permission else { return true }
                    return await gate.resolvePermission(token, check: permission, onBlocked: blocked)
                }, start: {})
                reply.finish(.success(ready))
            } catch { reply.finish(.failure(error)) }
        }
        defer { worker.cancel() }
        let ready = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await reply.wait()
        } onCancel: {
            worker.cancel()
            Task { @MainActor in reply.finish(.failure(CancellationError())) }
        }
        guard ready else { throw CancellationError() }
        try Task.checkCancellation()
    }
}

/// Main-actor serialization makes completion-before-wait and cancellation/late callback races safe.
@MainActor
private final class PreflightReply {
    private var result: Result<Bool, Error>?
    private var continuation: CheckedContinuation<Bool, Error>?

    func wait() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            if let result { continuation.resume(with: result) }
            else { self.continuation = continuation }
        }
    }

    func finish(_ result: Result<Bool, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: result)
    }
}
