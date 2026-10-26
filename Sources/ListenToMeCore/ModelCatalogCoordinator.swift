import Foundation

/// Native discovery supplies metadata; Core owns refresh ordering and per-pane selection policy.
@MainActor
public final class ModelCatalogCoordinator {
    public struct Discovery: Sendable {
        public var names: [String]
        public var verifiedLocal: Set<String>
        public var unverified: Set<String>
        public var catalogFailed: Bool
        public var localReadiness: LocalOllamaReadiness?
        public var problem: String?

        public init(names: [String] = [], verifiedLocal: Set<String> = [], unverified: Set<String> = [],
                    catalogFailed: Bool = false, localReadiness: LocalOllamaReadiness? = nil, problem: String? = nil) {
            self.names = names; self.verifiedLocal = verifiedLocal; self.unverified = unverified
            self.catalogFailed = catalogFailed; self.localReadiness = localReadiness; self.problem = problem
        }
    }

    public struct Configuration: Sendable, Equatable {
        public let mode: AIProcessingMode
        /// Non-secret destination identity. Credentials stay in the native adapter.
        public let destination: String
        public let appleUnavailableReason: String?
        public init(mode: AIProcessingMode, destination: String, appleUnavailableReason: String? = nil) {
            self.mode = mode; self.destination = destination; self.appleUnavailableReason = appleUnavailableReason
        }
    }

    public struct Choice: Sendable {
        public let model: String
        public let pinned: Bool
        public init(model: String, pinned: Bool) { self.model = model; self.pinned = pinned }
    }

    public struct Update: Sendable {
        public let discovery: Discovery
        public let choices: [CopilotRole: PaneModelHealing.Decision]
        public let status: String
    }

    private var generation = UUID()
    private var task: Task<Void, Never>?
    public init() {}

    @discardableResult
    public func reload(configuration: @escaping @MainActor () -> Configuration,
                       choices: @escaping @MainActor () -> [CopilotRole: Choice],
                       discover: @escaping @MainActor () async -> Discovery,
                       apply: @escaping @MainActor (Update) -> Void) -> Task<Void, Never> {
        cancel()
        let token = generation
        let route = configuration()
        let work = Task {
            defer { if token == generation { task = nil } }
            guard !Task.isCancelled, token == generation, configuration() == route else { return }
            if route.mode == .off {
                apply(Update(discovery: Discovery(), choices: [:], status: "AI is off"))
                return
            }
            if route.mode == .apple {
                apply(Update(discovery: Discovery(names: ["Apple Intelligence"]),
                             choices: Dictionary(uniqueKeysWithValues: CopilotRole.allCases.map {
                                 ($0, .init(model: "Apple Intelligence", persist: false))
                             }), status: route.appleUnavailableReason ?? ""))
                return
            }
            let catalog = await discover()
            guard !Task.isCancelled, token == generation, configuration() == route else { return }
            apply(Self.resolve(catalog, route: route, choices: choices()))
        }
        task = work
        return work
    }

    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
    }

    private static func resolve(_ catalog: Discovery, route: Configuration,
                                choices: [CopilotRole: Choice]) -> Update {
        let autoAssign = route.mode != .openAI && route.mode != .cloudAI
        let defaults = autoAssign ? ModelRanking.roleDefaults(from: catalog.names, local: catalog.verifiedLocal) : [:]
        var decisions: [CopilotRole: PaneModelHealing.Decision] = [:]
        for role in CopilotRole.allCases {
            let current = choices[role] ?? Choice(model: "", pinned: false)
            decisions[role] = PaneModelHealing.decide(
                current: current.model, pinned: current.pinned, available: catalog.names,
                fallback: defaults[role], autoAssign: autoAssign,
                verificationUncertain: catalog.catalogFailed || catalog.unverified.contains(current.model))
        }
        var status = route.mode == .off ? "AI is off" : (catalog.problem ?? (catalog.names.isEmpty
            ? "No available AI models. Check Ollama and AI mode in Settings, then Refresh models." : ""))
        if route.mode == .local, let readiness = catalog.localReadiness,
           readiness.status != .ready || !readiness.unverified.isEmpty { status = readiness.message }
        if !autoAssign, !catalog.names.isEmpty, decisions.values.contains(where: { $0.model.isEmpty }) {
            let source = route.mode == .cloudAI ? "a cloud AI service's" : "an OpenAI-compatible server's"
            status = "Choose a model for each pane in the status rail. ListenToMe never picks one from \(source) list for you."
        }
        return Update(discovery: catalog, choices: decisions, status: status)
    }
}
