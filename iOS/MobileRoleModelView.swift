import SwiftUI
import ListenToMeCore

struct MobileRoleModelView: View {
    @Bindable var ai: MobileAISettings
    let role: MobileSummaryMode
    @State private var operation: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") {
                    operation = Task { await ai.refreshSummaryModels() }
                }.disabled(ai.refreshing || ai.testing)
                if let status = ai.status { Text(status).font(.caption).accessibilityIdentifier("ollamaStatus") }
                Button(ai.testing ? "Testing connection…" : "Test this model") {
                    operation = Task { await ai.testConnection(for: role) }
                }.disabled(ai.availability(for: role) != nil || ai.testing)
            }
            if ai.provider == .cloud {
                MobileCloudModelSections(ai: ai, role: role)
            } else if ai.provider == .openAI {
                Section {
                    Text("Models listed by \(ai.summaryEndpointLabel). The list does not say where a model runs. "
                         + (role == .quick
                            ? "Quick and Auto need the model to answer in the Quick Summary JSON format; "
                                + "Test this model checks that."
                            : "Your selection stays fixed until you change it."))
                }
                Section("Server models") {
                    ForEach(ai.models(for: role)) { model in modelRow(model, for: role) }
                }
            } else {
                Section {
                    Text("Newest API update per DeepSeek, GLM, Qwen and Kimi variant. " +
                         "Models absent from the API are not offered. Your selection stays fixed until you change it.")
                }
                Section("Recent family variants") {
                    ForEach(OllamaCloudModel.recentVariants(in: ai.models(for: role))) { model in modelRow(model, for: role) }
                }
                Section("All API models") {
                    ForEach(ai.models(for: role)) { model in modelRow(model, for: role) }
                }
            }
        }.accessibilityIdentifier("roleModelList")
            .navigationTitle("\(role.title) model")
            .task {
                let empty = ai.provider == .openAI ? ai.openAI.models.isEmpty
                    : (ai.provider == .cloud ? ai.cloud.models.isEmpty : ai.models.isEmpty)
                if empty && ai.canRefreshSummaryModelsAutomatically { await ai.refreshSummaryModels() }
            }
            .onDisappear { operation?.cancel() }
    }

    private func modelRow(_ model: OllamaCloudModel, for role: MobileSummaryMode) -> some View {
        Button {
            ai.selectModel(model.name, for: role)
        } label: {
            HStack {
                Text(model.name).foregroundStyle(.primary)
                Spacer()
                if ai.selectedModel(for: role) == model.name { Image(systemName: "checkmark").accessibilityLabel("Selected") }
            }
        }.accessibilityIdentifier("model-\(model.name)")
            // A test result is recorded for the model that was tested; switching mid-test would muddle it.
            .disabled(ai.testing)
    }
}
