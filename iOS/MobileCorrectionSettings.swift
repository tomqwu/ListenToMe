import Foundation
import ListenToMeCore

extension MobileAISettings {
    var correctionModels: [OllamaCloudModel] { models.filter { Self.isFlash($0.name) } }

    var correctionAvailability: String? {
        if !hasKey && !usesCustomEndpoint { return "Add your Ollama API key in AI settings." }
        if correctionModel.isEmpty || !Self.isFlash(correctionModel) {
            return "Choose a Flash model for speech correction."
        }
        if !models.contains(where: { $0.name == correctionModel }) {
            return "Refresh models and choose an available Flash model."
        }
        return nil
    }

    func selectCorrectionModel(_ name: String) {
        guard correctionModels.contains(where: { $0.name == name }) else { return }
        correctionModel = name
    }

    func correctionClient() throws -> OllamaProvider {
        if let reason = correctionAvailability { throw RecordingError.message(reason) }
        let key = try MobileKeychain.read()
        guard !key.isEmpty || usesCustomEndpoint else {
            throw RecordingError.message("Add your Ollama API key in AI settings.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 12
        return OllamaProvider(model: correctionModel, baseURL: resolvedBaseURL, apiKey: key.isEmpty ? nil : key,
                              urlSession: URLSession(configuration: configuration),
                              options: .init(thinking: false, temperature: 0, maximumTokens: 700))
    }
}
