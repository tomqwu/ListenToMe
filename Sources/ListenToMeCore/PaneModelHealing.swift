import Foundation

/// What a macOS pane should use after its route's model list changes (a refresh, an AI-mode switch).
///
/// - A model the user picked (`pinned`) that is still listed is kept.
/// - A picked model that is *not* listed is never overwritten in storage: the pane runs on the
///   fallback for now and the pick comes back when the model does.
/// - With `autoAssign` off — an OpenAI-compatible server, whose `/v1/models` may list hundreds of
///   hosted models from vendors the user never chose (issue #52) — nothing is ever picked from the
///   catalog: the pane keeps a listed choice or stays unset until the user picks one.
/// - Otherwise an unpinned pane follows the role default (`ModelRanking.roleDefaults`).
public enum PaneModelHealing {
    public struct Decision: Equatable, Sendable {
        /// The model the session uses now; empty means "not chosen".
        public let model: String
        /// Whether `model` replaces the stored choice.
        public let persist: Bool
        public init(model: String, persist: Bool) { self.model = model; self.persist = persist }
    }

    public static func decide(current: String, pinned: Bool, available: [String], fallback: String?,
                              autoAssign: Bool) -> Decision {
        let listed = available.contains(current)
        guard autoAssign else { return Decision(model: listed ? current : "", persist: false) }
        if pinned { return Decision(model: listed ? current : (fallback ?? current), persist: false) }
        let target = fallback ?? current
        return Decision(model: target, persist: target != current)
    }
}
