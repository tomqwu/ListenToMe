import SwiftUI
import AppKit

struct PermissionsView: View {
    let permissions: PermissionsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Required")
                    .font(.title2).bold()
                Text(
                    "ListenToMe needs the following permissions to capture audio and transcribe " +
                    "your meetings. Grant them below or open System Settings."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)

            // Permission rows
            VStack(spacing: 12) {
                PermissionRow(
                    name: "Microphone",
                    purpose: "Captures your voice (the \"You\" channel).",
                    status: permissions.microphone,
                    isOptional: false,
                    onGrant: { permissions.requestMicrophone() },
                    onOpenSettings: { permissions.openSettings("Privacy_Microphone") }
                )
                PermissionRow(
                    name: "Speech Recognition",
                    purpose: "Transcribes captured audio on-device.",
                    status: permissions.speech,
                    isOptional: false,
                    onGrant: { permissions.requestSpeech() },
                    onOpenSettings: { permissions.openSettings("Privacy_SpeechRecognition") }
                )
                PermissionRow(
                    name: "Screen Recording",
                    purpose: "Captures other participants\u{2019} system audio (the \u{201C}Others\u{201D} channel).",
                    status: permissions.screenRecording,
                    isOptional: false,
                    onGrant: { permissions.requestScreenRecording() },
                    onOpenSettings: { permissions.openSettings("Privacy_ScreenCapture") }
                )
                PermissionRow(
                    name: "Accessibility",
                    purpose: "Enables the global \u{2318}\u{21E7}Space hotkey while other apps are focused.",
                    status: permissions.accessibility,
                    isOptional: true,
                    onGrant: { permissions.requestAccessibility() },
                    onOpenSettings: { permissions.openSettings("Privacy_Accessibility") }
                )
            }

            // Optional note
            Text("Accessibility is optional — the in-app buttons still work without it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            if permissions.accessibility != .granted {
                Text(
                    "If Accessibility already looks enabled in System Settings, toggle ListenToMe " +
                    "off and back on there — rebuilding the app invalidates the previous grant, so " +
                    "macOS reports it as not trusted until you re-enable it."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if permissions.screenRecording != .granted {
                Text(
                    "After enabling Screen Recording in System Settings, quit and reopen the app" +
                    " — macOS only detects it after a relaunch."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Divider().padding(.vertical, 16)

            HStack {
                Spacer()
                Button("Quit & Reopen") { permissions.relaunch() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let purpose: String
    let status: PermissionsModel.Status
    let isOptional: Bool
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).fontWeight(.medium)
                    if isOptional {
                        Text("(optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            statusBadge
            actionButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption).fontWeight(.medium)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption).fontWeight(.medium)
        case .notDetermined:
            Label("Not set", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.caption).fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .granted:
            EmptyView()
        case .denied:
            Button("Open Settings") { onOpenSettings() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .notDetermined:
            Button("Grant") { onGrant() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
