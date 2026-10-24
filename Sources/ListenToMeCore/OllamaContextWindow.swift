import Foundation

/// Local runners may default to 4K even when the model supports a much larger window.
/// Use byte-count budgeting (not an English-only characters/token guess), reserve output space,
/// and reject requests that cannot fit rather than silently losing their opening.
public enum OllamaContextWindow {
    public struct Allocation: Equatable, Sendable {
        public let contextTokens: Int
        public let outputTokens: Int
    }

    public static func allocate(metadata: Data, request: LLMRequest,
                                maximumTokens: Int? = nil) throws -> Allocation {
        guard let info = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let model = info["model_info"] as? [String: Any],
              let architecture = model["general.architecture"] as? String,
              let limit = model["\(architecture).context_length"] as? Int, limit > 0 else {
            throw OllamaStreamError.server("Ollama did not report this model's context capacity. Refresh or update the model before retrying.")
        }
        let requestedOutput = maximumTokens ?? 4_096
        guard requestedOutput > 0, requestedOutput <= 65_536 else {
            throw OllamaStreamError.server("The requested Ollama answer limit cannot fit a bounded context window.")
        }
        let capacity = min(limit, 65_536)
        let output = min(requestedOutput, max(1, capacity / 4))
        let modelMessages = (info["messages"] as? [[String: String]])?.compactMap { $0["content"] } ?? []
        let contents = [request.system, info["system"] as? String ?? ""]
            + request.messages.map(\.content) + modelMessages
        let promptBytes = contents.reduce(0) { $0 + $1.utf8.count }
        let templateBytes = (info["template"] as? String)?.utf8.count ?? 0
        // Include role delimiters and template literals for every message, plus a generous margin.
        let needed = promptBytes + (templateBytes + 128) * contents.count + 1_024 + output
        guard needed <= capacity else {
            throw OllamaStreamError.server("This conversation exceeds the selected local model's safe context window. " +
                "No text was sent for an answer. Use a shorter selection or a model with a larger context.")
        }
        let bucket = [8_192, 16_384, 32_768, 65_536].first { $0 >= needed } ?? 65_536
        return Allocation(contextTokens: min(bucket, capacity), outputTokens: output)
    }
}
