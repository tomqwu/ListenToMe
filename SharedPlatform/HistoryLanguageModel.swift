import Foundation
import Observation
import ListenToMeCore

/// Explicit optional History-model setup, independent of the summary provider.
@MainActor @Observable
final class HistoryLanguageModel {
    enum State: Equatable { case notInstalled, checking, downloading, ready, removing, failed(String) }
    static let enabledKey = "multilingualHistorySearchEnabled"
    static let shared = makeShared()
    private static func makeShared() -> HistoryLanguageModel {
#if DEBUG && targetEnvironment(simulator)
        if let mode = ProcessInfo.processInfo.environment["LISTENTOME_HISTORY_MODEL_FIXTURE"] {
            // UI automation exercises the production controls without a network or model download.
            let defaults = UserDefaults(suiteName: "history-controls-fixture-" + UUID().uuidString)!
            let directory = URL(fileURLWithPath: "/synthetic-history-model")
            return HistoryLanguageModel(defaults: defaults,
                lookup: { mode == "installed" ? directory : nil },
                install: { progress in
                    progress(0.25)
                    try await Task.sleep(for: .seconds(60))
                    return directory
                }, remove: {})
        }
#endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "ListenToMe Dev" : "ListenToMe"
        let assets = HistoryModelAssets(directory: base.appendingPathComponent(folder + "/History Models"))
        let model = HistoryLanguageModel(defaults: .standard, lookup: { await assets.installedDirectory() },
                                        install: { progress in
            try await assets.install(progress: progress)
            guard let folder = await assets.installedDirectory() else {
                throw HistoryModelAssets.AssetError.invalidAsset("installation")
            }
            return folder
        }, remove: { try await assets.remove() })
        model.didChange = { HistorySearchModel.useMultilingualModel(at: $0) }
        return model
    }
    private(set) var state: State = .notInstalled
    private(set) var enabled: Bool
    private(set) var progress = 0.0
    private(set) var activeDirectory: URL?
    @ObservationIgnored var didChange: (URL?) -> Void = { _ in }
    typealias Lookup = @Sendable () async -> URL?
    typealias Install = @Sendable (@escaping @Sendable (Double) -> Void) async throws -> URL
    typealias Remove = @Sendable () async throws -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lookup: Lookup
    @ObservationIgnored private let install: Install
    @ObservationIgnored private let erase: Remove
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var checked = false
    private var installed: URL?

    init(defaults: UserDefaults, lookup: @escaping Lookup, install: @escaping Install,
         remove: @escaping Remove) {
        self.defaults = defaults; self.lookup = lookup; self.install = install; erase = remove
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    func refreshIfNeeded() { if !checked { refresh() } }
    func refresh() {
        guard state != .downloading, state != .removing, state != .checking else { return }
        checked = true; generation += 1
        let mine = generation
        state = .checking
        task = Task {
            let folder = await lookup()
            guard mine == generation, !Task.isCancelled else { return }
            installed = folder
            state = folder == nil ? .notInstalled : .ready
            publish(enabled ? folder : nil)
        }
    }

    /// The button explicitly grants the asset download and subsequent local indexing.
    func download() {
        guard state != .downloading, state != .removing, state != .checking else { return }
        generation += 1
        let mine = generation
        state = .downloading; progress = 0
        task = Task {
            do {
                let folder = try await install { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.generation == mine, self.state == .downloading else { return }
                        self.progress = min(1, max(0, value))
                    }
                }
                guard mine == generation, !Task.isCancelled else { return }
                installed = folder; state = .ready; progress = 1
                setEnabled(true)
            } catch {
                guard mine == generation, !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        generation += 1; task?.cancel()
        state = installed == nil ? .notInstalled : .ready
        progress = 0
    }

    func setEnabled(_ value: Bool) {
        guard !value || (state == .ready && installed != nil) else { return }
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        publish(value ? installed : nil)
    }

    func remove() {
        guard state != .removing else { return }
        generation += 1; task?.cancel()
        let mine = generation
        setEnabled(false)
        installed = nil; state = .removing; progress = 0
        task = Task {
            do {
                try await erase()
                guard mine == generation else { return }
                state = .notInstalled
            } catch {
                guard mine == generation else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func publish(_ directory: URL?) {
        guard directory != activeDirectory else { return }
        activeDirectory = directory
        didChange(directory)
    }
    func waitForOperation() async { await task?.value }
}
