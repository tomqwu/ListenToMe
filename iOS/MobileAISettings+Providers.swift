import Foundation
import ListenToMeCore

/// Provider-aware wording and actions for the summary roles. Speech correction always uses the
/// Ollama connection (`endpointDescription`); summaries use whichever provider is selected, so the
/// two destinations are named separately and never confused (issue #52).
extension MobileAISettings {
    /// Exact URL summaries go to, for settings and status text.
    var summaryEndpointDescription: String {
        if provider == .cloud { return cloud.preset?.baseURL.absoluteString ?? "no cloud AI service chosen" }
        guard provider == .openAI else { return endpointDescription }
        return openAI.isConfigured ? openAI.baseURL : "no OpenAI-compatible server set"
    }

    /// Prose destination for summaries: "Ollama Cloud", your Ollama URL, or the OpenAI-compatible label.
    var summaryEndpointLabel: String {
        switch provider {
        case .openAI: return openAI.destinationLabel
        case .cloud: return cloud.destinationLabel
        default: return endpointLabel
        }
    }

    /// `summaryEndpointLabel` for the start of a sentence ("Your server at …"). URLs are left as typed.
    var summaryEndpointTitle: String {
        let label = summaryEndpointLabel
        guard provider == .openAI, let first = label.first else { return label }
        return first.uppercased() + label.dropFirst()
    }

    /// Whether opening a summary model list may fetch it without being asked: only from a server the
    /// user entered, or Ollama Cloud with a saved key. Never on Apple Intelligence.
    var canRefreshSummaryModelsAutomatically: Bool {
        switch provider {
        case .openAI: return openAI.isConfigured
        // Listing models sends only the key the user gave this vendor, never a transcript.
        case .cloud: return cloud.hasKey
        default: return canRefreshAutomatically
        }
    }

    /// Why Auto is paused although the selected models are available (see `MobileOpenAISettings`).
    var automaticQuickReason: String? {
        switch provider {
        case .openAI: return openAI.automaticQuickReason
        case .cloud: return cloud.automaticQuickReason
        default: return nil
        }
    }

    /// Refreshes the model list of the selected summary provider.
    func refreshSummaryModels() async {
        if provider == .cloud { await refreshCloudModels(); return }
        guard provider == .openAI else { await refresh(); return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let count = try await openAI.refresh()
            status = "Fetched \(count) models from \(openAI.baseURL)/models. "
                + "The list does not show where a model runs; use Test connection to check one."
        } catch is CancellationError {
            status = "The server changed while refreshing. Refresh again."
        } catch {
            status = "Could not refresh models from \(summaryEndpointDescription): "
                + "\(Self.errorMessage(error)) Your selection is kept."
        }
    }

    func saveOpenAIBaseURL(_ value: String) -> Bool {
        let result = openAI.saveBaseURL(value)
        status = result.message
        return result.saved
    }

    func clearOpenAIServer() { status = openAI.clearServer() }

    @discardableResult
    func saveOpenAIKey(_ value: String) -> Bool {
        do {
            status = try openAI.saveKey(value)
            return true
        } catch { status = Self.errorMessage(error); return false }
    }

    /// A short synthetic exchange sent to the Quick model in the evaluator's exact request shape.
    static let quickContractProbe = "You: Let's move the launch to Friday. Dana will update the rollout checklist."

    /// Checks that the OpenAI-compatible Quick model holds the Auto JSON contract, and records the
    /// outcome so Auto pauses with an explanation instead of failing every few seconds.
    func testQuickContract() async {
        // Everything named in the result is captured now: the selection may change while it runs.
        let cloudRoute = provider == .cloud
        let vendor = cloud.vendor
        let model = selectedModel(for: .quick)
        let destination = summaryEndpointLabel
        let record: (Bool) -> Void = { [openAI, cloud] passed in
            if cloudRoute { cloud.recordContract(model: model, passed: passed, vendor: vendor) } else {
                openAI.recordContract(model: model, passed: passed)
            }
        }
        do {
            let client = try self.client(for: .quick)
            let request = try QuickSummaryContext.manualRequest(source: Self.quickContractProbe)
            _ = try await QuickSummaryReader.evaluate(request, provider: client)
            record(true)
            status = "Connection verified: \(model) at \(destination) returned a valid Quick Summary "
                + "update, so Auto and Quick can use it."
        } catch where OpenAICompatibleContractLedger.isContractFailure(error) {
            // A reasoning-only or empty answer is as unusable to Auto as malformed JSON.
            record(false)
            if error is LLMOutputLimitError || (error as? AnthropicError) == .cutOff {
                // A Quick update cut off at the cap is unreadable JSON every time (#215).
                status = "\(model) stopped at its output limit before finishing a Quick Summary update. Auto is "
                    + "paused for this model; raise its output limit, or use it for Summary and Deep."
            } else {
                status = "\(model) answered, but not in the Quick Summary format that Auto and Quick need "
                    + "(\(error.localizedDescription)) Auto is paused for this model; Summary and Deep can still use it."
            }
        } catch {
            status = "Connection test failed: \(Self.errorMessage(error))"
        }
    }
}
