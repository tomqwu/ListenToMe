import SwiftUI

/// The installed build is the identity; release notes are bundled and available offline.
enum MobileReleaseNotes {
    static let seenKey = "lastAcknowledgedReleaseBuild"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
    static var identity: String { "\(version) (\(build))" }
    static var versionLabel: String { "Version \(version) · Build \(build)" }
    static func shouldPresent(defaults: UserDefaults = .standard, identity: String = identity) -> Bool {
        defaults.string(forKey: seenKey) != identity
    }
    static func acknowledge(defaults: UserDefaults = .standard, identity: String = identity) {
        defaults.set(identity, forKey: seenKey)
    }

    struct Release: Identifiable {
        let version: String
        let title: String
        let details: [String]
        var id: String { version }
    }
    static let releases: [Release] = [
        .init(version: "1.10.2", title: "On-device by default, or your own server", details: [
            "New installs summarize on-device with Apple Intelligence. A provider you already chose is kept.",
            "Settings accepts an optional Ollama server URL, so summaries can use an Ollama server you run."
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
                            Text(release.version == MobileReleaseNotes.version ? "IN THIS UPDATE" : "VERSION \(release.version)")
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
