import Foundation
import ListenToMeCore

/// Stop waiting promptly on cancellation even when CoreML ignores cancellation. The processing task
/// remains in MobileSpeakers' serial chain, so a later pass cannot overlap it. Its late result is ignored.
@MainActor
final class MobileSpeakerFileWait {
    private var continuation: CheckedContinuation<DiarizedWindow?, any Error>?
    private var result: Result<DiarizedWindow?, any Error>?

    static func value(of work: Task<DiarizedWindow?, any Error>) async throws -> DiarizedWindow? {
        let waiter = MobileSpeakerFileWait()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                Task {
                    do { waiter.finish(.success(try await work.value)) } catch { waiter.finish(.failure(error)) }
                }
            }
        } onCancel: {
            work.cancel()
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ value: Result<DiarizedWindow?, any Error>) {
        guard result == nil else { return }
        result = value
        continuation?.resume(with: value)
        continuation = nil
    }
}
