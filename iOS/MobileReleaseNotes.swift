import SwiftUI

/// Release notes are bundled and available offline. What's New is gated on the newest bundled
/// release — not on the installed build — so a TestFlight build that changes no notes never
/// re-presents the same sheet. `identity` stays the build string for the Settings version label.
enum MobileReleaseNotes {
    static let seenKey = "lastAcknowledgedReleaseBuild"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
    static var identity: String { "\(version) (\(build))" }
    static var versionLabel: String { "Version \(version) · Build \(build)" }

    /// Version plus a stable digest of the notes themselves, so editing a bundled entry re-presents
    /// it while a pure build bump does not. `Hasher` is seeded per process and cannot be stored.
    static func identity(for release: Release) -> String {
        var hash: UInt64 = 5381
        for byte in ([release.title] + release.details).joined(separator: "\u{1}").utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return "\(release.version)-\(String(hash, radix: 36))"
    }
    static var notesIdentity: String { releases.first.map(identity(for:)) ?? version }

    /// The newest bundled entry is the update being announced, even if its version does not match a
    /// hot-fixed or downgraded build.
    static func badge(for release: Release) -> String {
        release.version == releases.first?.version ? "IN THIS UPDATE" : "VERSION \(release.version)"
    }

    /// True only for an install that has already acknowledged different notes. A first launch after
    /// install has nothing stored: it seeds the acknowledgement so a new user's first screen is the
    /// app, not a full-screen "IN THIS UPDATE" for software they have never run.
    static func shouldPresent(defaults: UserDefaults = .standard, identity: String = notesIdentity) -> Bool {
        guard let seen = defaults.string(forKey: seenKey) else {
            acknowledge(defaults: defaults, identity: identity)
            return false
        }
        return seen != identity
    }
    static func acknowledge(defaults: UserDefaults = .standard, identity: String = notesIdentity) {
        defaults.set(identity, forKey: seenKey)
    }

    struct Release: Identifiable {
        let version: String
        let title: String
        let details: [String]
        var id: String { version }
    }
    static let releases: [Release] = [
        .init(version: "1.10.3", title: "Recording that survives the real world", details: [
            "Calls, AirPods and switching apps no longer end a recording silently; you are told why it stopped and can resume.",
            "Calendar imports keep meeting links private, Apple Intelligence Quick answers are plain bullets, and typing no longer costs a save per keystroke."
        ]),
        .init(version: "1.10.2", title: "On-device by default, or your own server", details: [
            "New installs summarize on-device with Apple Intelligence. A provider you already chose is kept.",
            "Optional Ollama server URL: use a server you run. Your cloud key is never sent there.",
            "Summaries now say who said what, and never read your typed notes as speech."
        ]),
        .init(version: "1.10.1", title: "Know what changed", details: [
            "See the installed version and release highlights after an update.",
            "Reopen this changelog anytime from More → What’s New."
        ]),
        .init(version: "1.10.0", title: "Automatic reviews", details: [
            "Auto updates Quick, Summary and Deep when new speech calls for a review. Manual Generate is still available.",
            "Quick stays concise, with clearer progress and recovery when a model response needs another try."
        ])
    ]
}

struct MobileReleaseNotesView: View {
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        MobileBrand()
                        Text("What’s New").font(.largeTitle.bold()).foregroundStyle(MobileStyle.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(MobileReleaseNotes.versionLabel).font(.subheadline.weight(.medium))
                            .foregroundStyle(MobileStyle.accent).accessibilityIdentifier("releaseVersion")
                    }
                    ForEach(MobileReleaseNotes.releases) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(MobileReleaseNotes.badge(for: release))
                                .font(.caption.weight(.semibold)).foregroundStyle(MobileStyle.accent)
                            Text(release.title).font(.title3.bold()).foregroundStyle(MobileStyle.ink)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(release.details, id: \.self) { detail in
                                Label { Text(detail).foregroundStyle(MobileStyle.ink).fixedSize(horizontal: false, vertical: true) }
                                    icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(MobileStyle.accent) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(MobileCard())
                    }
                }.frame(maxWidth: 620).padding(24).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("releaseNotesScroll")
                .background(MobileStyle.canvas)
                .safeAreaInset(edge: .bottom) {
                    Button(action: close) { Text("Continue").font(.headline).frame(maxWidth: .infinity) }
                        .buttonStyle(MobileRecordStyle(recording: false)).frame(maxWidth: 620).padding(.horizontal, 24).padding(.vertical, 12)
                        .frame(maxWidth: .infinity).background(MobileStyle.canvas)
                        .accessibilityIdentifier("releaseNotesContinue")
                }
        }
    }
}
