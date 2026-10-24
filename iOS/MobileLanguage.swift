import Foundation
import ListenToMeCore
import Observation
import Speech
import WhisperKit
import Tokenizers

/// Whisper's most likely language for some audio, and how sure it is.
struct LanguageGuess: Sendable, Equatable {
    /// Whisper's language code, such as "zh" or "es".
    let language: String
    /// Probability of `language` among Whisper's languages, 0–1.
    let probability: Double
}

/// The spoken-language seam (issue #197). The real one is a small multilingual Whisper model run on this
/// device; tests substitute a fake because the simulator has no microphone and no speech assets.
protocol MobileLanguageIdentifying: Sendable {
    /// Downloads the model on first use and loads it. Throws when it cannot.
    func prepare() async throws
    /// Loads only a model already downloaded by an interactive session.
    func prepareIfDownloaded() async throws -> Bool
    /// The most likely language of 16 kHz mono `samples`.
    func detect(samples: [Float]) async throws -> LanguageGuess
    /// Locale identifiers on-device transcription supports.
    func supportedLocales() async -> [String]
}

extension MobileLanguageIdentifying {
    func prepareIfDownloaded() async throws -> Bool { false }
}

/// Spoken-language identification with WhisperKit's multilingual "tiny" model (about 75 MB, downloaded
/// once from huggingface.co). Only the model is downloaded; audio never leaves the device. The model's
/// folder is kept out of iCloud and Finder backups because it can always be downloaded again.
actor WhisperLanguageIdentifier: MobileLanguageIdentifying {
    static let modelName = "tiny"
    /// About 73 MB of Core ML models plus a 3 MB tokenizer, measured for issue #197.
    static let downloadDescription = "about 75 MB"

    private let directory: URL
    private var kit: KitBox?
    private var loading: Task<KitBox, any Error>?

    init(directory: URL) {
        self.directory = directory
    }

    /// The app's language model: Whisper, or a stand-in that downloads nothing while the app hosts unit
    /// tests or runs under UI tests (DEBUG simulator builds launched with
    /// `LISTENTOME_LANGUAGE_MODEL_FIXTURE=1`). Mirrors `MobileSpeakers.deviceDiarizer`.
    static func deviceModel() -> any MobileLanguageIdentifying {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return StandInLanguageModel(failure: "The language model is not downloaded while unit tests run")
        }
        #if DEBUG && targetEnvironment(simulator)
        if environment["LISTENTOME_LANGUAGE_MODEL_FIXTURE"] == "1" { return StandInLanguageModel(failure: nil) }
        #endif
        return onDevice()
    }

    /// The app's identifier, with its model folder in Application Support and out of backups.
    static func onDevice() -> WhisperLanguageIdentifier {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("LanguageModels", isDirectory: true)
        try? PrivateStorage.createDirectory(at: directory)
        try? PrivateStorage.setExcludedFromBackup(true, at: directory)
        return WhisperLanguageIdentifier(directory: directory)
    }

    func prepare() async throws {
        _ = try await loadedKit()
    }

    func prepareIfDownloaded() async throws -> Bool {
        if kit != nil { return true }
        guard Self.isDownloaded(in: directory) else { return false }
        _ = try await loadedKit(allowDownload: false)
        return true
    }

    func detect(samples: [Float]) async throws -> LanguageGuess {
        let box = try await loadedKit()
        let result = try await box.kit.detectLangauge(audioArray: samples)
        let logProbability = result.langProbs[result.language] ?? -.infinity
        return LanguageGuess(language: result.language, probability: Double(exp(logProbability)))
    }

    func supportedLocales() async -> [String] {
        await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    }

    /// One load at a time; a failure is not kept, so the next recording tries again.
    private func loadedKit(allowDownload: Bool = true) async throws -> KitBox {
        if let kit { return kit }
        if let loading { return try await loading.value }
        let directory = directory
        let task = Task { try await Self.load(from: directory, allowDownload: allowDownload) }
        loading = task
        defer { loading = nil }
        let box = try await task.value
        kit = box
        return box
    }

    /// Loads the model already on this device without touching the network, or downloads it first.
    private static func isDownloaded(in directory: URL) -> Bool {
        let local = directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
        let parts = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
        let tokenizer = directory.appendingPathComponent("models/openai/whisper-\(modelName)/tokenizer.json")
        return FileManager.default.fileExists(atPath: tokenizer.path)
            && parts.allSatisfy { FileManager.default.fileExists(atPath: local.appendingPathComponent($0).path) }
    }

    private static func load(from directory: URL, allowDownload: Bool) async throws -> KitBox {
        let downloaded = isDownloaded(in: directory)
        guard downloaded || allowDownload else {
            throw RecordingError.message("The language model is not downloaded.")
        }
        let local = directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
        let folder = downloaded ? local : try await WhisperKit.download(variant: modelName, downloadBase: directory)
        // The tokenizer is fetched beside the model (downloadBase), never into Documents.
        let config = WhisperKitConfig(downloadBase: directory, modelFolder: folder.path, tokenizerFolder: directory,
                                      verbose: false, logLevel: .error, prewarm: false, load: allowDownload, download: false)
        let kit = try await WhisperKit(config)
        if !allowDownload {
            // WhisperKit's default tokenizer loader falls back to the Hub on corrupt cache files.
            // Supply a strictly local tokenizer before loading models so that fallback cannot run.
            let folder = directory.appendingPathComponent("models/openai/whisper-\(modelName)")
            let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
            kit.tokenizer = try MobileLanguageTokenizer(tokenizer)
            kit.textDecoder.isModelMultilingual = true
            try await kit.loadModels()
        }
        return KitBox(kit: kit)
    }

    /// `WhisperKit` is a non-Sendable class; this actor is its only user. Mirrors the macOS box.
    private final class KitBox: @unchecked Sendable {
        let kit: WhisperKit
        init(kit: WhisperKit) { self.kit = kit }
    }
}

/// A language model for tests: it loads at once (or fails with `failure`), downloads nothing, and always
/// hears the device's language, so nothing ever switches.
private struct StandInLanguageModel: MobileLanguageIdentifying {
    let failure: String?

    func prepare() async throws {
        if let failure { throw RecordingError.message(failure) }
    }

    func detect(samples: [Float]) async throws -> LanguageGuess {
        try await prepare()
        return LanguageGuess(language: Locale.current.language.languageCode?.identifier ?? "en", probability: 1)
    }

    func supportedLocales() async -> [String] { [] }
}
