import Foundation

/// Serializes a window's close decision without invalidating context for a rejected close.
@MainActor
public final class ConversationCloseCoordinator {
    private var isPreparing = false
    public init() {}

    public func request(canBegin: Bool, prepare: @MainActor () async -> Bool,
                        accepted: @MainActor () -> Void) async -> Bool {
        guard canBegin, !isPreparing else { return false }
        isPreparing = true
        defer { isPreparing = false }
        guard await prepare() else { return false }
        accepted()
        return true
    }
}
