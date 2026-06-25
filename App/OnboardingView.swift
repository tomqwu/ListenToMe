import SwiftUI
import AppKit

/// First-run onboarding sheet. Shown only once (gated by the `didCompleteOnboarding`
/// UserDefaults flag). Walks through the app's value prop, permission grants, optional
/// Ollama cloud key, and a final "Get started" step that sets the flag and dismisses.
struct OnboardingView: View {
    static let completionKey = "didCompleteOnboarding"

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var permissions = PermissionsModel()
    @State private var ollamaKey = KeychainStore.get("ollama") ?? ""

    private static let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(28)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 520, height: 460)
        .onAppear { permissions.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in permissions.refresh() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionsStep
        case 2: ollamaStep
        default: getStartedStep
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                icon: "waveform",
                title: "Welcome to ListenToMe",
                subtitle: "Your on-device meeting copilot — it listens, transcribes, and helps you respond."
            )
            VStack(alignment: .leading, spacing: 12) {
                onboardingFeature(
                    "doc.plaintext", "Transcript",
                    "A live, on-device transcript of you and everyone else."
                )
                onboardingFeature(
                    "ear", "Listener",
                    "A running summary and the open items to track."
                )
                onboardingFeature(
                    "bolt", "Quick",
                    "Instant suggestions — answers, recaps, follow-ups."
                )
                onboardingFeature(
                    "brain", "Deep",
                    "Detailed, considered answers when you need depth."
                )
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                icon: "lock.shield",
                title: "Permissions",
                subtitle: "ListenToMe captures and transcribes audio entirely on your Mac."
            )
            VStack(spacing: 10) {
                OnboardingPermissionRow(
                    name: "Microphone",
                    detail: "Captures your voice (the \u{201C}You\u{201D} channel).",
                    status: permissions.microphone,
                    onGrant: { permissions.requestMicrophone() },
                    onOpenSettings: { permissions.openSettings("Privacy_Microphone") }
                )
                OnboardingPermissionRow(
                    name: "Speech Recognition",
                    detail: "Transcribes captured audio on-device.",
                    status: permissions.speech,
                    onGrant: { permissions.requestSpeech() },
                    onOpenSettings: { permissions.openSettings("Privacy_SpeechRecognition") }
                )
                OnboardingPermissionRow(
                    name: "Screen Recording",
                    detail: "Captures other participants\u{2019} system audio.",
                    status: permissions.screenRecording,
                    onGrant: { permissions.requestScreenRecording() },
                    onOpenSettings: { permissions.openSettings("Privacy_ScreenCapture") }
                )
            }
            Text("You can revisit these any time from the shield button in the toolbar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var ollamaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                icon: "cloud",
                title: "Ollama",
                subtitle: "ListenToMe runs its AI panes through Ollama."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama API key (optional)").fontWeight(.medium)
                SecureField("Paste an ollama.com API key", text: $ollamaKey)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Leave this blank to use a local Ollama at localhost:11434. " +
                    "Add a key to route the AI panes through ollama.com instead."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var getStartedStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("You\u{2019}re all set")
                .font(.title2).bold()
            Text("Press Listen in the toolbar to start your first session.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
            }
            Spacer()
            stepDots
            Spacer()
            if step < Self.stepCount - 1 {
                Button("Continue") { withAnimation { step += 1 } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get started") { complete() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text(title).font(.title2).bold()
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingFeature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func complete() {
        KeychainStore.set(ollamaKey, for: "ollama")   // empty string clears the key (local Ollama)
        UserDefaults.standard.set(true, forKey: Self.completionKey)
        dismiss()
    }
}

// MARK: - Onboarding permission row

private struct OnboardingPermissionRow: View {
    let name: String
    let detail: String
    let status: PermissionsModel.Status
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badge
            action
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.cardBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption).fontWeight(.medium)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption).fontWeight(.medium)
        case .notDetermined:
            Label("Not set", systemImage: "circle.dotted")
                .foregroundStyle(.secondary).font(.caption).fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .granted:
            EmptyView()
        case .denied:
            Button("Open Settings") { onOpenSettings() }
                .buttonStyle(.bordered).controlSize(.small)
        case .notDetermined:
            Button("Grant") { onGrant() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }
}
