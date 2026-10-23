import Foundation
import ListenToMeCore

/// Actions for the cloud AI presets (issue #214), with the status text the settings show.
extension MobileAISettings {
    /// Where summaries go, as the Summary provider picker sees it.
    enum SummaryRoute: Hashable {
        case apple, ollama, openAI
        case cloud(CloudAIPreset.ID)
    }

    var summaryRoute: SummaryRoute {
        switch provider {
        case .apple: return .apple
        case .ollama: return .ollama
        case .openAI: return .openAI
        case .cloud: return cloud.vendor.map(SummaryRoute.cloud) ?? .apple
        }
    }

    /// Applies a picker choice. Choosing a cloud service selects it and nothing else: no key, no model.
    func selectSummaryRoute(_ route: SummaryRoute) {
        switch route {
        case .apple: provider = .apple
        case .ollama: provider = .ollama
        case .openAI: provider = .openAI
        case .cloud(let id):
            cloud.select(id)
            provider = .cloud
            status = nil
        }
    }

    func refreshCloudModels() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let count = try await cloud.refresh()
            status = "Fetched \(count) models from \(cloud.destinationLabel). Choose a model for each role; "
                + "ListenToMe never picks one for you."
        } catch is CancellationError {
            status = "The service changed while refreshing. Refresh again."
        } catch {
            status = "Could not refresh models from \(cloud.destinationLabel): \(Self.errorMessage(error)) "
                + "Your selection is kept."
        }
    }

    @discardableResult
    func saveCloudKey(_ value: String, typedFor: CloudAIPreset.ID? = nil) -> Bool {
        do {
            status = try cloud.saveKey(value, typedFor: typedFor)
            return true
        } catch { status = Self.errorMessage(error); return false }
    }
}
