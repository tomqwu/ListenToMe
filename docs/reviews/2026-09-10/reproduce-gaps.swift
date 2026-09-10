// Read-only synthetic probes. No microphone, network, credentials, or saved user sessions.
// Compile against the locally built ListenToMeCore package; see evidence.md.
import Foundation
import ListenToMeCore

@main
struct ReviewProbes {
    static func main() async {
        let store = ConversationStore()
        let first = "Alice owns the launch checklist, due Friday."
        store.apply(TranscriptSegment(source: .others, text: first, isFinal: true, start: 0, end: 1))
        for index in 1...20 {
            store.apply(TranscriptSegment(source: .others, text: String(repeating: "Later topic. ", count: 40),
                                          isFinal: true, start: Double(index), end: Double(index + 1)))
        }
        let context = ContextEngine().buildContext(from: store, notes: nil)
        let listener = PromptBuilder.buildListener(context: context)
        print("EARLY_ACTION_ABSENT_FROM_LISTENER_PROMPT=\(!listener.messages.contains { $0.content.contains(first) })")
        let suppliedSummary = ContextEngine().buildContext(from: store, notes: nil, summary: first)
        let withSummary = PromptBuilder.buildListener(context: suppliedSummary)
        print("SUPPLIED_PRIOR_SUMMARY_IGNORED_BY_LISTENER_BUILDER=\(!withSummary.messages.contains { $0.content.contains(first) })")

        let partials = ConversationStore()
        partials.apply(TranscriptSegment(source: .others, text: "Remote is still speaking", isFinal: false, start: 0, end: 2))
        partials.apply(TranscriptSegment(source: .you, text: "Yes", isFinal: true, start: 1, end: 2))
        print("MIC_FINAL_CLEARS_REMOTE_PARTIAL=\(partials.partial == nil)")

        let order = ConversationStore()
        order.apply(TranscriptSegment(source: .you, text: "Later", isFinal: true, start: 10, end: 12))
        order.apply(TranscriptSegment(source: .others, text: "Earlier", isFinal: true, start: 2, end: 4))
        print("ARRIVAL_ORDER_DIFFERS_FROM_CAPTURE_ORDER=\(order.utterances.map(\.start) == [10, 2])")

        let provider = OllamaProvider(model: "synthetic", baseURL: URL(string: "http://localhost")!) { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("{\"error\":\"model failed during generation\"}")
                continuation.finish()
            }
        }
        var text = ""
        do {
            for try await delta in provider.stream(LLMRequest(system: "test", messages: [])) { text += delta }
            print("STREAM_ERROR_REPORTED_AS_EMPTY_SUCCESS=\(text.isEmpty)")
        } catch {
            print("STREAM_ERROR_REPORTED_AS_EMPTY_SUCCESS=false")
        }
    }
}
