import Observation
import SwiftUI

/// Owns preparing UI; the recorder separately owns activated audio.
@MainActor @Observable
final class WatchPreparation {
    private(set) var isPending = false
    private(set) var problem: String?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func run(operation: @escaping @MainActor () async throws -> Void,
             onSuccess: @escaping @MainActor () -> Void = {},
             onFailure: @escaping @MainActor () -> Void = {}) {
        cancel()
        generation &+= 1
        let current = generation
        problem = nil
        isPending = true
        task = Task { @MainActor [weak self] in
            // Do not even begin OS consent work after cancel, replacement or view-owner release.
            guard !Task.isCancelled, self?.generation == current else { return }
            do {
                try await operation()
                guard let self, self.generation == current else { return }
                self.isPending = false
                self.task = nil
                guard !Task.isCancelled else { return }
                onSuccess()
            } catch {
                guard let self, self.generation == current else { return }
                self.isPending = false
                self.task = nil
                guard !(error is CancellationError), !Task.isCancelled else { return }
                self.problem = error.localizedDescription
                onFailure()
            }
        }
    }

    func cancel(onCancel: () -> Void = {}) {
        guard isPending else { return }
        generation &+= 1
        task?.cancel()
        task = nil
        isPending = false
        problem = nil
        onCancel()
    }

    func sceneChanged(_ phase: ScenePhase, isRecording: Bool = false, onCancel: () -> Void) {
        // Permission UI can make the app inactive. Background means it was actually left.
        if phase == .background {
            if isRecording { cancel() } else { cancel(onCancel: onCancel) }
        }
    }
}
