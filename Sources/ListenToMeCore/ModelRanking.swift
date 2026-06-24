import Foundation

/// Heuristics for ordering Ollama model names by capability and assigning role-appropriate
/// defaults: Quick wants the lightest/fastest model, Deep the heaviest/strongest, Listener a
/// balanced middle. Pure (no I/O) so it is fully unit-testable.
public enum ModelRanking {
    /// A rough "capability weight" used only for *ordering* (not absolute meaning): larger
    /// parameter counts and reasoning/coding keywords score higher; "flash"/"mini"/"lite" lower.
    public static func weight(_ model: String) -> Double {
        let lower = model.lowercased()
        var score = 0.0
        // Parameter size, e.g. "12b", "70b", "7b", "1.5b" -> its numeric value.
        if let range = lower.range(of: "([0-9]+(\\.[0-9]+)?)b", options: .regularExpression) {
            score += Double(lower[range].dropLast()) ?? 0   // drop trailing "b"
        }
        // Keywords that push a model toward "Deep" (stronger/slower).
        if lower.contains("coder") || lower.contains("code") { score += 40 }
        if lower.contains("pro") { score += 60 }
        if lower.contains("reason") || lower.contains("-r1") || lower.contains("think") { score += 50 }
        // Keywords that pull toward "Quick" (lighter/faster).
        if lower.contains("flash") || lower.contains("mini") || lower.contains("lite")
            || lower.contains("fast") || lower.contains("small") { score -= 30 }
        return score
    }

    /// Models sorted ascending by `weight` (lightest first); ties broken by name for stability.
    public static func ranked(_ models: [String]) -> [String] {
        models.sorted {
            let (w0, w1) = (weight($0), weight($1))
            return w0 != w1 ? w0 < w1 : $0 < $1
        }
    }

    /// A default model per role from the available list: Quick = lightest, Deep = heaviest,
    /// Listener = middle. Picks distinct models when enough are available and reuses them when
    /// fewer than three exist. Returns empty when no models are available.
    ///
    /// Privacy: auto-defaults are **local-first**. When the list mixes local and `:cloud` models,
    /// only local models are considered, so an unpinned pane never silently sends transcripts to
    /// Ollama Cloud. Cloud models are auto-selected only when no local chat model exists (e.g. the
    /// user set a cloud API key, opting into the cloud route).
    public static func roleDefaults(from models: [String]) -> [CopilotRole: String] {
        let local = models.filter { !$0.contains(":cloud") }
        let ranked = ranked(local.isEmpty ? models : local)
        guard let fastest = ranked.first, let strongest = ranked.last else { return [:] }
        let middle = ranked[(ranked.count - 1) / 2]
        return [.quick: fastest, .listener: middle, .deep: strongest]
    }

    /// The default model for a single role from the available list, or nil if none are available.
    public static func defaultModel(for role: CopilotRole, from models: [String]) -> String? {
        roleDefaults(from: models)[role]
    }
}
