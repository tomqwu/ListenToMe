import Foundation

/// Heuristics for ordering Ollama model names by capability and assigning role-appropriate
/// defaults: Quick wants the lightest/fastest model, Deep the heaviest/strongest, Listener a
/// balanced middle. Pure (no I/O) so it is fully unit-testable.
public enum ModelRanking {
    /// Lowercased tokens of a model name, split on the usual separators ("-", ":", ".", "/",
    /// space).
    static func tokens(_ model: String) -> [String] {
        model.lowercased().split(whereSeparator: { "-:./ ".contains($0) }).map(String.init)
    }

    /// True if any token of `model` *begins with* `marker`. Token-prefix matching (not raw
    /// substring) rejects cross-token false hits like "gemini" ⊃ "mini" while still catching
    /// variant forms like "reasoning" ~ "reason" and "codellama"/"codegemma" ~ "code".
    static func hasMarker(_ model: String, _ marker: String) -> Bool {
        tokens(model).contains { $0.hasPrefix(marker) }
    }

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
        if hasMarker(model, "coder") || hasMarker(model, "code") { score += 40 }
        if hasMarker(model, "pro") { score += 60 }
        if hasMarker(model, "reason") || hasMarker(model, "r1") || hasMarker(model, "think") {
            score += 50
        }
        // Keywords that pull toward "Quick" (lighter/faster).
        if hasMarker(model, "flash") || hasMarker(model, "mini") || hasMarker(model, "lite")
            || hasMarker(model, "fast") || hasMarker(model, "small") { score -= 30 }
        return score
    }

    /// Models sorted ascending by `weight` (lightest first); ties broken by name for stability.
    public static func ranked(_ models: [String]) -> [String] {
        models.sorted {
            let (w0, w1) = (weight($0), weight($1))
            return w0 != w1 ? w0 < w1 : $0 < $1
        }
    }

    /// Substring markers of fast/lightweight models (good for Quick), highest priority first.
    static let fastPatterns = ["flash", "mini", "nano", "lite", "small", "fast"]
    /// Substring markers of strong/reasoning models (good for Deep), highest priority first.
    /// "pro" leads so a curated flagship (e.g. `deepseek-v4-pro`) is preferred over a merely-large
    /// model such as `mistral-large-3:675b`, which a raw parameter-size sort would otherwise pick.
    static let strongPatterns = ["pro", "reason", "think", "coder", "code", "ultra", "max", "large"]

    /// Among `ranked` (ascending weight), the match for the earliest pattern in `patterns`.
    /// `heaviest` picks the highest-weight match (Deep); otherwise the lightest match (Quick).
    static func match(in ranked: [String], patterns: [String], heaviest: Bool) -> String? {
        for pattern in patterns {
            let hits = ranked.filter { hasMarker($0, pattern) }
            if let pick = heaviest ? hits.last : hits.first { return pick }
        }
        return nil
    }

    /// A default model per role from the available list: Quick = a curated fast model (else the
    /// lightest), Deep = a curated strong/reasoning model (else the heaviest), Listener = a balanced
    /// middle of the remaining models. Picks distinct models when enough are available and reuses
    /// them when fewer exist. Returns empty when no models are available.
    ///
    /// Privacy: auto-defaults are **local-first**. When the list mixes local and `:cloud` models,
    /// only local models are considered, so an unpinned pane never silently sends transcripts to
    /// Ollama Cloud. Cloud models are auto-selected only when no local chat model exists (e.g. the
    /// user set a cloud API key, opting into the cloud route).
    public static func roleDefaults(from models: [String]) -> [CopilotRole: String] {
        let local = models.filter { !$0.contains(":cloud") }
        let rankedPool = ranked(local.isEmpty ? models : local)
        guard let lightest = rankedPool.first, let heaviest = rankedPool.last else { return [:] }
        let quick = match(in: rankedPool, patterns: fastPatterns, heaviest: false) ?? lightest
        // Pick Deep from the models not already taken by Quick, so a name matching both pattern
        // sets (e.g. a "coder-lite" model) can't collapse both panes onto one model.
        let deepPool = rankedPool.filter { $0 != quick }
        let deepCandidates = deepPool.isEmpty ? rankedPool : deepPool
        let deep = match(in: deepCandidates, patterns: strongPatterns, heaviest: true)
            ?? deepCandidates.last ?? heaviest
        let rest = rankedPool.filter { $0 != quick && $0 != deep }
        let listener = rest.isEmpty ? quick : rest[(rest.count - 1) / 2]
        return [.quick: quick, .listener: listener, .deep: deep]
    }

    /// The default model for a single role from the available list, or nil if none are available.
    public static func defaultModel(for role: CopilotRole, from models: [String]) -> String? {
        roleDefaults(from: models)[role]
    }

    /// Curated one-line "good for" hints for known Ollama model families, matched as the first
    /// substring hit (most specific first). Used to annotate the per-pane model dropdowns.
    static let descriptions: [(key: String, hint: String)] = [
        ("deepseek-v4-pro", "competitive coding & reasoning"),
        ("deepseek-v4-flash", "fast, cost-efficient"),
        ("deepseek", "strong reasoning"),
        ("glm-5.1", "long-horizon agentic"),
        ("glm", "agentic, self-host"),
        ("kimi", "agent swarms, long runs"),
        ("qwen3-coder", "repo-level coding"),
        ("qwen", "general & coding"),
        ("minimax-m3", "frontier, multimodal"),
        ("minimax", "high-throughput coding"),
        ("gemini", "fast, general"),
        ("gpt-oss", "fast, general"),
        ("devstral", "agentic coding"),
        ("nemotron", "NVIDIA-optimized agents"),
        ("mistral-large", "large, general"),
        ("ministral", "small & fast"),
        ("codegemma", "coding"),
        ("codellama", "coding"),
        ("gemma", "general"),
        ("llama", "general"),
        ("phi", "small & fast")
    ]

    /// A short "good for" hint for a model name: a curated description when the family is known,
    /// otherwise a capability heuristic (coding / reasoning / fast / general).
    public static func describe(_ model: String) -> String {
        let lower = model.lowercased()
        if let match = descriptions.first(where: { lower.contains($0.key) }) { return match.hint }
        if hasMarker(model, "coder") || hasMarker(model, "code") { return "coding" }
        if hasMarker(model, "pro") || hasMarker(model, "reason") || hasMarker(model, "think") {
            return "strong reasoning"
        }
        if hasMarker(model, "flash") || hasMarker(model, "mini") || hasMarker(model, "nano")
            || hasMarker(model, "lite") || hasMarker(model, "fast") || hasMarker(model, "small") {
            return "fast"
        }
        return "general"
    }
}
