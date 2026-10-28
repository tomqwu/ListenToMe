import Foundation
import Observation

@MainActor public protocol TranscriptTranslating: AnyObject {
    func sourceLanguage(for text: String, hint: String?) -> String?
    func availability(source: String, target: String) async -> FeatureAvailability
    func translate(_ text: String, source: String, target: String) async throws -> String
    func cancel()
}

/// A single coalescing worker translates completed lines. Originals never enter an AI provider.
@MainActor @Observable public final class LiveTranslationCoordinator {
    public private(set) var availability: FeatureAvailability = .temporarilyUnavailable(reason: "Record speech to translate.")
    public private(set) var isTranslating = false
    public private(set) var isDraining = false
    public private(set) var preparationSource: String?
    public private(set) var problems: [UUID: String] = [:]
    public var translator: (any TranscriptTranslating)?
    private let requestTimeout: Duration
    public init(translator: (any TranscriptTranslating)? = nil, requestTimeout: Duration = .seconds(45)) {
        self.translator = translator; self.requestTimeout = requestTimeout
    }
    private struct Input: Equatable {
        let id: UUID
        let text: String
        let hint: String?
    }
    private struct Result {
        let input: Input
        let text: String
    }
    private var suspended = false
    private var conversationID: String?
    private var options = ConversationLanguageOptions()
    private var inputs: [Input] = []
    private var results: [UUID: Result] = [:]
    private var blocked: [UUID: (source: String?, readiness: FeatureAvailability)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var activeInput: Input?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored var deadlineWait: @MainActor (Duration) async throws -> Void = { duration in
        try await Task.sleep(for: duration)
    }
    private var stoppingReason: String?

    public func update(conversationID: String, segments: [TranscriptSegment], fallbackLanguage: String?,
                       options: ConversationLanguageOptions) {
        let changed = self.conversationID != conversationID
            || self.options.translateTranscript != options.translateTranscript
            || self.options.translationTarget != options.translationTarget
        let previous = Dictionary(inputs.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        self.conversationID = conversationID
        self.options = options
        inputs = segments.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Input(id: $0.id, text: $0.text, hint: $0.language ?? fallbackLanguage) }
        if changed {
            results = [:]; problems = [:]; blocked = [:]
            invalidateWork()
        } else {
            let current = Dictionary(inputs.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            let removed = Set(results.compactMap { current[$0.key] == $0.value.input ? nil : $0.key })
            for id in removed { results[id] = nil }
            for id in Array(problems.keys) where current[id] != previous[id] { problems[id] = nil; blocked[id] = nil }
            if let activeInput, !inputs.contains(activeInput) { invalidateWork() }
        }
        refreshStatus()
        startWorker()
    }

    public func hasCompleted(_ segment: TranscriptSegment) -> Bool {
        options.translateTranscript && results[segment.id]?.input.text == segment.text
    }

    public func text(for segment: TranscriptSegment) -> String? {
        guard options.translateTranscript, segment.isFinal, let result = results[segment.id],
              result.input.text == segment.text, !result.text.isEmpty else { return nil }
        return result.text
    }

    public func reset() {
        invalidateWork(); conversationID = nil; options = .init()
        inputs = []; results = [:]; problems = [:]; blocked = [:]; refreshStatus()
    }

    public func setSuspended(_ suspended: Bool) {
        guard suspended != self.suspended else { return }
        self.suspended = suspended
        if suspended { invalidateWork() } else { startWorker() }
    }

    public func retry() {
        guard !isTranslating, !isDraining else { return }
        problems = [:]; blocked = [:]; refreshStatus(); startWorker()
    }

    public var pendingCount: Int {
        options.translateTranscript ? inputs.filter { results[$0.id] == nil && problems[$0.id] == nil }.count : 0
    }

    private func invalidateWork(reason: String? = nil) {
        generation = UUID(); deadline?.cancel(); deadline = nil
        isTranslating = false; isDraining = task != nil
        stoppingReason = isDraining ? (reason ?? "Stopping translation… Your original text is kept. "
            + "If this does not finish, close and reopen the app.") : nil
        task?.cancel(); translator?.cancel()
        // Keep the worker slot until even an uncooperative native call returns. Repeated changes
        // cannot create unlimited concurrent model jobs; its defer starts the latest work instead.
        refreshStatus()
    }

    private func current(_ input: Input, generation: UUID) -> Bool {
        self.generation == generation && !suspended && options.translateTranscript && inputs.contains(input)
    }

    private func startWorker() {
        guard task == nil, !suspended, options.translateTranscript, pendingCount > 0 else { return }
        let generation = generation
        isTranslating = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.deadline?.cancel(); self.deadline = nil
                self.task = nil; self.activeInput = nil
                self.isTranslating = false; self.isDraining = false; self.stoppingReason = nil
                self.refreshStatus(); self.startWorker()
            }
            while self.generation == generation, !Task.isCancelled,
                  let input = self.inputs.first(where: { self.results[$0.id] == nil && self.problems[$0.id] == nil }) {
                self.activeInput = input
                self.deadline = Task { [weak self, requestTimeout, deadlineWait] in
                    do { try await deadlineWait(requestTimeout) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.timedOut(input, generation: generation)
                }
                await self.translate(input, generation: generation)
                self.deadline?.cancel(); self.deadline = nil
                await Task.yield()
            }
        }
    }

    private func timedOut(_ input: Input, generation: UUID) {
        guard current(input, generation: generation), activeInput == input, results[input.id] == nil else { return }
        let reason = "Translation stopped responding. Your original text is kept. Try again."
        // Stop the whole pending batch instead of spending one deadline per remaining paragraph.
        // The actual native slot stays occupied until cancellation completes; never abandon it
        // and multiply model requests when the service ignores cancellation.
        for pending in inputs where results[pending.id] == nil && problems[pending.id] == nil {
            fail(pending, .temporarilyUnavailable(reason: reason))
        }
        invalidateWork(reason: "Translation stopped responding. Your original text is kept. "
            + "Waiting for the on-device service to stop. If this does not finish, close and reopen the app.")
    }

    private func translate(_ input: Input, generation: UUID) async {
        guard input.text.count <= 10_000 else {
            fail(input, .unsupported(reason: "This line is too long to translate. Split it into shorter lines.")); return
        }
        guard OutputLanguage.option(options.translationTarget) != nil else {
            fail(input, .unsupported(reason: "Choose an available translation language.")); return
        }
        guard let translator else {
            fail(input, .temporarilyUnavailable(reason: "On-device translation is unavailable here.")); return
        }
        guard let source = translator.sourceLanguage(for: input.text, hint: input.hint) else {
            fail(input, .temporarilyUnavailable(reason: "The spoken language could not be identified.")); return
        }
        let target = options.translationTarget
        // Same-language content needs no model or asset lookup; the original remains the display.
        if Self.languageIdentity(source) == Self.languageIdentity(target) {
            results[input.id] = Result(input: input, text: ""); refreshStatus(); return
        }
        let readiness = await translator.availability(source: source, target: target)
        guard current(input, generation: generation), !Task.isCancelled else { return }
        guard readiness.canRun else { fail(input, readiness, source: source); return }
        do {
            let value = try await translator.translate(input.text, source: source, target: target)
            guard current(input, generation: generation), !Task.isCancelled else { return }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 20_000 else {
                fail(input, .temporarilyUnavailable(reason: "Translation returned no usable text.")); return
            }
            results[input.id] = Result(input: input, text: value); refreshStatus()
        } catch {
            guard current(input, generation: generation), !Task.isCancelled else { return }
            fail(input, .temporarilyUnavailable(reason: "Translation failed. Your original text is kept. Retry when ready."))
        }
    }

    private func fail(_ input: Input, _ readiness: FeatureAvailability, source: String? = nil) {
        problems[input.id] = readiness.reason ?? "Translation is unavailable."
        blocked[input.id] = (source, readiness); refreshStatus()
    }

    private func refreshStatus() {
        preparationSource = nil
        if let stoppingReason {
            availability = .temporarilyUnavailable(reason: stoppingReason)
        } else if let problem = inputs.compactMap({ blocked[$0.id] }).first {
            availability = problem.readiness; preparationSource = problem.source
        } else if inputs.isEmpty {
            availability = .temporarilyUnavailable(reason: "Record speech to translate.")
        } else {
            availability = .ready
        }
    }

    public static func languageIdentity(_ identifier: String) -> String {
        let language = Locale(identifier: identifier).language
        return [language.languageCode?.identifier, language.script?.identifier].compactMap { $0 }.joined(separator: "-")
    }
}
