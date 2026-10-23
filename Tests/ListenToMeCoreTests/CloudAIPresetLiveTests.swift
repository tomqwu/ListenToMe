import XCTest
@testable import ListenToMeCore

/// Live check of one cloud AI preset with a real key (issue #214). SKIPPED unless `LTM_CLOUD_PRESET`
/// (`openai`, `anthropic`, `gemini`, `deepseek`, `openrouter`, `groq`, `mistral`, `xai`),
/// `LTM_CLOUD_KEY` and `LTM_CLOUD_MODEL` are all set, so `swift test` and CI never reach a vendor.
/// The key comes from the environment only; never commit one.
///
///     LTM_CLOUD_PRESET=anthropic LTM_CLOUD_MODEL=claude-opus-5-5 LTM_CLOUD_KEY=… \
///         swift test --filter CloudAIPresetLiveTests
final class CloudAIPresetLiveTests: XCTestCase {
    func testRealVendorListsModelsStreamsASummaryAndHoldsTheQuickContract() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["LTM_CLOUD_PRESET"], let id = CloudAIPreset.ID(rawValue: raw),
              let key = env["LTM_CLOUD_KEY"], !key.isEmpty,
              let model = env["LTM_CLOUD_MODEL"], !model.isEmpty else {
            throw XCTSkip("live only: set LTM_CLOUD_PRESET, LTM_CLOUD_KEY and LTM_CLOUD_MODEL")
        }
        let preset = CloudAIPreset.preset(id)
        let models = try await CloudAICatalog().fetch(preset, apiKey: key)
        XCTAssertTrue(models.contains(model), "\(model) is not listed by \(preset.vendor): \(models.prefix(20))")

        let provider = preset.provider(model: model, apiKey: key)
        let summary = PromptBuilder.build(
            context: PromptContext(
                messages: [TranscriptSegment(source: .others, text: "Can you ship the beta by Friday?",
                                             isFinal: true, start: 0, end: 2)],
                notes: nil),
            action: .recap)
        var text = ""
        for try await delta in provider.stream(summary) { text += delta }
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let quick = try QuickSummaryContext.manualRequest(source: "You: Let's move the launch to Friday.")
        let decision = try await QuickSummaryReader.evaluate(quick, provider: provider, timeout: .seconds(60))
        XCTAssertTrue(["keep", "publish"].contains(decision.action))
    }
}
