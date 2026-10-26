import Foundation
import Observation

/// Owns the user's pending Start across native capability and OS permission callbacks.
/// The UI begins synchronously, then finishes in a defer so even an unscheduled task can be cancelled.
@MainActor @Observable
public final class CaptureStartGate {
    private var token: UUID?
    private var acceptsStarts = true
    public init() {}
    public var isPending: Bool { token != nil }

    public func begin() -> UUID? {
        guard acceptsStarts, token == nil, !Task.isCancelled else { return nil }
        let next = UUID()
        token = next
        return next
    }
    public func cancel() { token = nil }
    public func close() { acceptsStarts = false; cancel() }
    public func reopen() { acceptsStarts = true }
    public func finish(_ token: UUID) { if self.token == token { self.token = nil } }
    public func isCurrent(_ token: UUID) -> Bool {
        acceptsStarts && self.token == token && !Task.isCancelled
    }

    /// Native permission errors use the same Start ownership as capture creation.
    public func resolvePermission(_ token: UUID, check: () async -> CapturePreflight.Decision,
                                  onBlocked: (String) -> Void) async -> Bool {
        guard isCurrent(token) else { return false }
        let decision = await check()
        guard isCurrent(token) else { return false }
        switch decision {
        case .blocked(let reason, _): onBlocked(reason); return false
        case .start: return isCurrent(token)
        case .requestAccess: return false
        }
    }

    /// Only the owning caller may proceed after each await. `finish` belongs in its defer, including errors.
    public func perform(_ token: UUID, prepare: () async -> Bool,
                        authorize: () async -> Bool, start: () async throws -> Void) async throws -> Bool {
        guard isCurrent(token) else { return false }
        guard await prepare(), isCurrent(token) else { return false }
        guard await authorize(), isCurrent(token) else { return false }
        try await start()
        return true
    }
}
