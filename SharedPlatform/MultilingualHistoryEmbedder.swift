import Foundation
import CoreML
import Embeddings
import NaturalLanguage
import ListenToMeCore

/// Optional installed MPNet runtime. Original Apple routing remains the default.
/// Oversized text gets no semantic vector: keyword search retains its complete original content.
actor MultilingualHistoryEmbedder: HistoryEmbedder {
    nonisolated static let modelIdentifier = "mpnet-4328cf26390c98c5e3c738b4460a05b95f4911f5-mean128-content-v2"
    nonisolated static let maximumTokens = 128
    nonisolated let signature: String
    private let fallback: any HistoryEmbedder
    private let directory: URL?
    private var bundle: XLMRoberta.ModelBundle?
    private var pending: Task<HistoryVector?, Never>?
    private var pendingID: UUID?
    private static let languages: Set<String> = ["de", "es", "ja", "ko"]

    /// The app's asset store verifies the pinned manifest before supplying this local directory.
    init(installedModelDirectory: URL? = nil,
         fallback: any HistoryEmbedder = NaturalLanguageEmbedder()) {
        self.fallback = fallback
        directory = installedModelDirectory
        signature = installedModelDirectory == nil ? fallback.signature
            : Self.modelIdentifier + "+" + fallback.signature
    }

    nonisolated func relevanceGroup(for model: String) -> String {
        model == Self.modelIdentifier ? Self.modelIdentifier : fallback.relevanceGroup(for: model)
    }

    func embed(_ text: String) async -> HistoryVector? {
        guard !Task.isCancelled else { return nil }
        if usesMultilingual(text) { return await multilingual(text) }
        let result = await fallback.embed(text)
        return Task.isCancelled ? nil : result
    }

    func embed(_ text: String, transcribedIn language: String) async -> HistoryVector? {
        guard !Task.isCancelled else { return nil }
        let code = Locale(identifier: language).language.languageCode?.identifier
        if directory != nil, code.map(Self.languages.contains) == true {
            return await multilingual(text, language: language)
        }
        let result = await fallback.embed(text, transcribedIn: language)
        return Task.isCancelled ? nil : result
    }

    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        guard !Task.isCancelled else { return [] }
        // Short queries have unreliable language guesses. Query every compatible stored model.
        var result = await fallback.embedQuery(query, models: models.subtracting([Self.modelIdentifier]))
        guard !Task.isCancelled else { return [] }
        if directory != nil, models.contains(Self.modelIdentifier), let vector = await multilingual(query, kind: .query) {
            result.append(vector)
        }
        return Task.isCancelled ? [] : result
    }

    private func usesMultilingual(_ text: String) -> Bool {
        guard directory != nil else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage.map { Self.languages.contains($0.rawValue) } == true
    }

    private func multilingual(_ text: String, language: String? = nil,
                              kind: HistoryContentEligibility.Kind = .passage) async -> HistoryVector? {
        guard !Task.isCancelled else { return nil }
        // Reject only known insufficient content. Unsupported lexical tagging stays unknown;
        // it must not manufacture content evidence or be described as a small-talk quality pass.
        guard HistoryContentEligibility.evaluate(text, language: language, kind: kind) != .insufficientContent else {
            return nil
        }
        let previous = pending
        let id = UUID()
        // An actor can reenter while loading/materializing tensors. The chain serializes both.
        let operation = Task { [self] in
            _ = await previous?.value
            guard !Task.isCancelled else { return Optional<HistoryVector>.none }
            return await forward(text)
        }
        pending = operation
        pendingID = id
        let result = await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        if pendingID == id { pending = nil; pendingID = nil }
        return Task.isCancelled ? nil : result
    }

    private func forward(_ text: String) async -> HistoryVector? {
        do {
            try Task.checkCancellation()
            guard let directory, directory.isFileURL else { return nil }
            if bundle == nil {
                // Local-folder overload only. Missing assets never trigger a Hub download.
                for name in ["config.json", "model.safetensors", "sentencepiece.bpe.model",
                             "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json"] {
                    let file = directory.appendingPathComponent(name)
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return nil }
                }
                let data = try Data(contentsOf: directory.appendingPathComponent("tokenizer_config.json"))
                guard var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                config["tokenizer_class"] = "XLMRobertaTokenizer"
                let loaded = try await XLMRoberta.loadModelBundle(
                    from: directory, loadConfig: LoadConfig(tokenizerConfig: TokenizerConfig(config: .data(config))))
                try Task.checkCancellation()
                bundle = loaded
            }
            guard let bundle else { return nil }
            let tokens = try bundle.tokenizer.tokenizeText(text, maxLength: nil)
            guard tokens.count <= Self.maximumTokens, tokens.first == 0, tokens.last == 2 else { return nil }
            try Task.checkCancellation()
            let ids = MLTensor(shape: [1, tokens.count], scalars: tokens)
            let pooled = bundle.model(inputIds: ids).sequenceOutput.mean(alongAxes: 1, keepRank: false)
            let raw = await pooled.cast(to: Float.self).shapedArray(of: Float.self).scalars
            try Task.checkCancellation()
            let norm = sqrt(raw.reduce(Float(0)) { $0 + $1 * $1 })
            guard raw.count == 768, raw.allSatisfy(\.isFinite), norm.isFinite, norm > 0 else { return nil }
            return HistoryVector(model: Self.modelIdentifier, values: raw)
        } catch {
            return nil
        }
    }
}
