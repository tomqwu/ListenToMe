/// Optional Ollama generation controls. Existing summary requests keep the server defaults.
public struct OllamaGenerationOptions: Sendable {
    public let thinking: Bool?
    public let temperature: Double?
    public let maximumTokens: Int?

    public init(thinking: Bool? = nil, temperature: Double? = nil, maximumTokens: Int? = nil) {
        self.thinking = thinking
        self.temperature = temperature
        self.maximumTokens = maximumTokens
    }
}
