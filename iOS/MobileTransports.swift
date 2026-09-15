import Foundation

/// A `URLSession` keeps its threads, connection pool, TLS state and in-memory stores until it is
/// invalidated, so building a fresh ephemeral session for every summary, automatic Quick evaluation
/// and speech correction grew with meeting length and paid a new handshake each time. One session
/// per role is kept instead, rebuilt only when the destination or credential changes.
@MainActor
final class MobileTransports {
    struct Role: Hashable {
        let name: String
        let resourceTimeout: TimeInterval
    }
    /// Summaries stream for minutes; a correction that has not returned in seconds is useless.
    static let summary = Role(name: "summary", resourceTimeout: 480)
    static let correction = Role(name: "correction", resourceTimeout: 12)

    private var live: [String: (identity: String, session: URLSession)] = [:]
    /// How many sessions have been built. A request that reuses its transport does not raise it.
    private(set) var builtSessions = 0

    /// The session for `role`, reused while `identity` (endpoint plus credential) is unchanged.
    func session(for role: Role, identity: String) -> URLSession {
        if let existing = live[role.name], existing.identity == identity { return existing.session }
        // In-flight work on the old endpoint/key is allowed to finish; nothing new is scheduled.
        live[role.name]?.session.finishTasksAndInvalidate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = role.resourceTimeout
        let session = URLSession(configuration: configuration)
        live[role.name] = (identity, session)
        builtSessions += 1
        return session
    }

    func invalidateAll() {
        for entry in live.values { entry.session.finishTasksAndInvalidate() }
        live.removeAll()
    }
}
