import Foundation
import Observation

/// Owns one import until its transcription drain finishes, including after a Cancel request.
@MainActor @Observable
public final class FileImportCoordinator {
    public private(set) var isActive = false
    @ObservationIgnored private var task: Task<Void, Never>?
    public init() {}

    @discardableResult
    public func begin(operation: @escaping @MainActor () async throws -> Void,
                      failed: @escaping @MainActor (Error) -> Void) -> Bool {
        guard !isActive else { return false }
        isActive = true
        task = Task {
            defer { isActive = false; task = nil }
            guard !Task.isCancelled else { return }
            do { try await operation() }
            catch { if !Task.isCancelled { failed(error) } }
        }
        return true
    }

    public func cancel() { task?.cancel() }
    public func wait() async { await task?.value }
}
