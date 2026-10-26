import Foundation
import ListenToMeCore

extension MeetingView {
    func reloadAndHealModels() async { await requestModelRefresh().value }

    @discardableResult
    func requestModelRefresh() -> Task<Void, Never> {
        session.aiEnabled = MacFeatureReadiness.aiCanRun(
            mode: ProviderSettings.aiMode, appleReason: MacDeviceCapabilities.appleReason(locale: currentCapabilityLocale))
        // Cancel previous-route answers immediately, before model discovery can suspend.
        for role in CopilotRole.allCases { session.setModel(role, session.models[role] ?? "") }
        localOllamaReadiness = nil
        return modelCatalog.reload(configuration: {
            let mode = ProviderSettings.aiMode
            let destination: String
            switch mode {
            case .openAI: destination = ProviderSettings.openAIBaseURL
            case .cloudAI: destination = ProviderSettings.cloudVendor?.rawValue ?? ""
            default: destination = mode.rawValue
            }
            return .init(mode: mode, destination: destination,
                         appleUnavailableReason: mode == .apple
                            ? MacDeviceCapabilities.appleReason(locale: currentCapabilityLocale) : nil)
        }, choices: {
            Dictionary(uniqueKeysWithValues: CopilotRole.allCases.map {
                ($0, .init(model: ProviderSettings.model(for: $0), pinned: ProviderSettings.isPinned($0)))
            })
        }, discover: { await Self.discoverChatModels() }, apply: { update in
            chatModels = update.discovery.names
            localOllamaReadiness = update.discovery.localReadiness
            verifiedLocalModels = update.discovery.verifiedLocal
            modelStatus = update.status
            for (role, decision) in update.choices {
                if decision.persist { ProviderSettings.setModel(decision.model, for: role) }
                session.setModel(role, decision.model)
            }
        })
    }

    /// Only the configured native endpoint receives catalog requests. Credentials stay native.
    nonisolated static func discoverChatModels() async -> OllamaModels.Discovery {
        if ProviderSettings.aiMode == .openAI { return await OpenAICompatibleModels.discover() }
        if ProviderSettings.aiMode == .cloudAI { return await CloudAIModels.discover() }
        return await OllamaModels.chatModels(
            baseURL: ollamaBaseURL(), apiKey: ollamaKey(), localOnly: ProviderSettings.aiMode != .cloud)
    }
}
