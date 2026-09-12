import Foundation
import FoundationModels

@main
struct AppleQuickBenchmark {
    static func main() async throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instructions = input["system"] as? String, let body = input["input"] else { return }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let prompt = String(decoding: payload, as: UTF8.self)
        let started = ContinuousClock.now
        var output: [String: Any] = [:]
        do {
            guard SystemLanguageModel.default.availability == .available else {
                throw NSError(domain: "ModelUnavailable", code: 1)
            }
            output["response"] = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: instructions)
                    return try await session.respond(to: prompt).content
                }
                group.addTask { try await Task.sleep(for: .seconds(15)); throw URLError(.timedOut) }
                defer { group.cancelAll() }
                return try await group.next() ?? ""
            }
        } catch { output["error"] = String(describing: error) }
        let elapsed = ContinuousClock.now - started
        output["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let encoded = try JSONSerialization.data(withJSONObject: output)
        print(String(decoding: encoded, as: UTF8.self))
    }
}
