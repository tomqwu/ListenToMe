import SwiftUI
import ListenToMeCore

extension ProviderSettings {
    static var openAIContractLedger: OpenAICompatibleContractLedger {
        get { OpenAICompatibleContractLedger(failures: UserDefaults.standard.stringArray(forKey: "openAIQuickContractFailures") ?? []) }
        set { UserDefaults.standard.set(newValue.failures, forKey: "openAIQuickContractFailures") }
    }

    static func recordOpenAIContract(endpoint: URL, model: String, passed: Bool) {
        var ledger = openAIContractLedger
        ledger.record(endpoint, model: model, passed: passed)
        openAIContractLedger = ledger
    }
}

/// Only the saved route is tested: unsaved URL/key edits must never send a key to a different host.
struct OpenAICompatibilityView: View {
    let savedConfiguration: Bool
    @State private var operation: Task<Void, Never>?
    @State private var status: String?
    private var model: String { UserDefaults.standard.string(forKey: "openAIModel_quick") ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(operation == nil ? "Check Auto compatibility" : "Checking Auto compatibility…") { check() }
                .disabled(operation != nil || !savedConfiguration || model.isEmpty || ProviderSettings.openAIEndpoint() == nil)
                .accessibilityIdentifier("checkOpenAIAutoCompatibility")
            if operation != nil { Button("Cancel check") { operation?.cancel() } }
            Text("Sends only a short synthetic exchange to the saved server and Quick model, never your conversation. "
                 + "Save Settings and choose a Quick model in the status rail first. A format failure pauses Auto "
                 + "for that server and model; a successful recheck enables it again.")
                .font(.caption).foregroundStyle(.secondary)
            if let status { Text(status).font(.caption).accessibilityIdentifier("openAIAutoCompatibilityStatus") }
        }
        .onDisappear { operation?.cancel() }
    }

    private func check() {
        guard savedConfiguration, let endpoint = ProviderSettings.openAIEndpoint(), !model.isEmpty else { return }
        let testedModel = model
        let provider = ProviderSettings.openAIProvider(model: testedModel)
        let destination = OpenAICompatibleEndpoint.destinationLabel(endpoint)
        status = nil
        operation = Task {
            defer { operation = nil }
            do {
                let result = try await OpenAICompatibleContractProbe.run(provider: provider)
                try Task.checkCancellation()
                if let passed = result.ledgerResult {
                    ProviderSettings.recordOpenAIContract(endpoint: endpoint, model: testedModel, passed: passed)
                }
                switch result {
                case .compatible:
                    status = "\(testedModel) at \(destination) returned a valid Quick Summary update. Auto can use it."
                case .incompatible(let reason):
                    status = "\(testedModel) at \(destination) did not follow the Quick Summary format. Auto is paused "
                        + "for this model; choose another Quick model or recheck. Summary remains available. \(reason)"
                case .unavailable(let reason):
                    status = "Could not check \(testedModel) at \(destination): \(reason) The saved compatibility result is unchanged."
                }
            } catch {
                status = "Check cancelled. The saved compatibility result is unchanged."
            }
        }
    }
}
