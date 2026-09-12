import Foundation
import ListenToMeCore
@main
struct AppleQuickBenchmark {
    static func main() async throws {
        let input = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
        let payload = try JSONSerialization.data(withJSONObject: input["input"]!)
        let request = LLMRequest(system: QuickSummaryContext.instructions,
            messages: [.init(role: "user", content: String(decoding: payload, as: UTF8.self))], purpose: .quickEvaluation)
        let started = ContinuousClock.now
        var output: [String: Any] = [:]
        do {
            var text = ""
            for try await delta in AppleIntelligenceProvider().stream(request) { text += delta }
            _ = try QuickSummaryDecision.parse(text)
            output["response"] = text
        } catch { output["error"] = String(describing: error) }
        let elapsed = ContinuousClock.now - started
        output["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
    }
}
