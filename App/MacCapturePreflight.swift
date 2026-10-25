import Foundation
import ListenToMeCore

/// The Mac adapter's capability → permission ordering; no capture or prompt precedes readiness.
@MainActor
enum MacCapturePreflight {
    static func prepare(gate: CaptureStartGate,
                        refresh: () async -> FeatureAvailability,
                        permission: (() async -> CapturePreflight.Decision)?,
                        blocked: (String) -> Void) async throws {
        guard let token = gate.begin() else { throw CancellationError() }
        defer { gate.finish(token) }
        let ready = try await gate.perform(token, prepare: {
            await refresh().canRun
        }, authorize: {
            guard let permission else { return true }
            return await gate.resolvePermission(token, check: permission, onBlocked: blocked)
        }, start: {})
        guard ready else { throw CancellationError() }
        try Task.checkCancellation()
    }
}
