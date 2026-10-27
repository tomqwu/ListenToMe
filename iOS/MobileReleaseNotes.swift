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
        .init(version: "1.19.1", title: "Reliable Watch audio imports", details: [
            "Fix an iPhone crash when opening received Watch audio for automatic language detection.",
            "Keep Watch capture running through recording-screen dismissal; use Stop to finish, or Continue after an audio interruption.",
            "Language detection, speaker analysis and transcription stay on-device. Saving playback audio remains optional."
        ]),
        .init(version: "1.19.0", title: "Record from your Apple Watch", details: [
            "Record on Apple Watch and send finished audio to your paired iPhone for on-device transcription when connected.",
            "Recording can continue with your wrist down; interruptions wait for your explicit Continue.",
            "Leaving during Start or Continue preparation cancels that attempt; a recording already underway keeps running.",
            "Keep Watch audio for playback only when Save audio recordings is on during iPhone import.",
            "Pending recordings survive interrupted handoffs and relaunch. After Stop, Delete removes waiting audio and its recovery state."
        ]),
        .init(version: "1.18.2", title: "A clearer Summary menu", details: [
            "Full summary now has its Summary icon in the More menu on iPhone and iPad."
        ]),
        .init(version: "1.18.1", title: "Keep each voice distinct", details: [
            "Live speaker identification uses a recording-scoped streaming model to improve brief alternating turns.",
            "Returning voices keep their labels and edited names through overlapping audio windows and quiet intervals.",
            "Stop finishes delayed speaker labels. Turning identification off clears its audio buffer and rejects late results.",
            "You can turn speaker labels off while listening and enable them again after Stop. Similar voices may still merge in group conversations.",
            "Speaker analysis stays on-device. Saved audio remains optional; enable Save audio recordings before listening for playback."
        ]),
        .init(version: "1.18.0", title: "Recording, review and recovery", details: [
            "Re-transcribe saved audio in a chosen language, review it and choose whether to replace the transcript. Notes and summaries are kept.",
            "Automatic reviews include instructions and references in their size limits. Stop and cancelled work stay bound to the right recording.",
            "Compatible older iPads use Apple's on-device dictation when advanced transcription is unavailable.",
            "Recording checks this device and language before enabling Start, with a clear reason and recovery when unavailable.",
            "Failed model or microphone setup shows the full error. Cancelling preparation does not show a false failure.",
            "Settings explains unavailable Apple Intelligence and offers explicit local or cloud provider setup. Recording needs no summary AI.",
            "Language choices and Automatic detection include languages supported by the available local dictation engine.",
            "Audio playback remains opt-in: enable Save audio recordings before listening, then use Play in the transcript after Stop."
        ]),
        .init(version: "1.17.0", title: "Your workspace, your conversation", details: [
            "Give Transcript or Quick more room in iPhone Duo. Your pane-width choice is remembered.",
            "Conversation vocabularies return when you reopen History and guide automatic Quick updates.",
            "Automatic language checks can start from speech activity even when the current language recognizes no words.",
            "Stop and backgrounding stay responsive during speaker labeling; old work cannot relabel a new recording.",
            "Summaries mark unfinished speech as provisional, and unchanged live text reuses its prepared snapshot.",
            "History search reuses unchanged passages when saving long conversations. Supported semantic languages are unchanged.",
            "Deleting a conversation clears History answers and citations, including answers still streaming.",
            "Set a context limit for your OpenAI-compatible server. Local Ollama requests size their context to the prompt.",
            "Ollama settings explain unsupported HTTP addresses and omitted URL parts without exposing query values."
        ]),
        .init(version: "1.16.0", title: "Your questions, your instructions", details: [
            "Prompt below Notes: ask a one-time question or save instructions for future summaries in this conversation.",
            "Choose a domain preset, edit it, then Ask or Save. Suggested presets never turn on by themselves.",
            "Rotate iPhone to see Transcript and Quick side by side. Portrait and larger text keep the stacked layout.",
            "All seven vocabulary presets now include Simplified Chinese terms for Chinese transcription.",
            "Privacy and Settings clarify which providers receive text and that audio is kept only when Save audio recordings is on."
        ]),
        .init(version: "1.15.0", title: "Find it, ask it, keep it", details: [
            "Two answers: Quick and Summary. The Deep tab is gone; a saved Deep analysis stays under Summary in History.",
            "Search History by meaning and Ask your history, with sources. Conversations name themselves after Stop.",
            "Select lines and tap Summarize selection. Tap a suggested prompt under Quick for a short answer.",
            "Vocabularies and My terms help recognition. Export as subtitles, text or JSON. Delete all conversations at once.",
            "Optional: keep the audio on this device and tap a line's time to play it. Long talks get better Quick answers."
        ]),
        .init(version: "1.14.0", title: "Your cloud AI, your key", details: [
            "Cloud AI: summarize with OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Groq, Mistral or xAI Grok using your own key.",
            "Each service keeps its own key in the Keychain and says plainly that it sends your transcript to that vendor.",
            "You choose every model. Apple Intelligence stays the default, and audio never leaves this device."
        ]),
        .init(version: "1.13.0", title: "Your notes, your languages, your server", details: [
            "Save to folder: each conversation becomes a Markdown note in a folder you pick, such as an Obsidian vault or iCloud Drive.",
            "Automatic language switches again when the language changes, and Undo goes back one switch.",
            "Pick any language this device can transcribe. Speakers keep their names after a long silence.",
            "Summaries can use your own OpenAI-compatible server. Settings → About lists open-source licenses."
        ]),
        .init(version: "1.12.0", title: "Names and languages, automatically", details: [
            "Speaker labels are on by default and get ready before you record, so even a short recording is labeled.",
            "Automatic language: this device hears which language you speak, switches and re-transcribes, with Undo."
        ]),
        .init(version: "1.11.0", title: "Know who said what", details: [
            "Optional speaker labels: Settings → Speakers marks lines Speaker 1, Speaker 2… on this device.",
            "Rename a speaker in Notes → Speakers and the name follows every line, History search and exports."
        ]),
        .init(version: "1.10.5", title: "Ready for the App Store", details: [
            "Privacy policy and support pages are linked from Settings.",
            "History warns about an unreadable saved conversation instead of hiding everything, and search now covers your notes."
        ]),
        .init(version: "1.10.4", title: "Quieter, safer, searchable", details: [
            "What's New shows only when the notes change, shared imports clean up after themselves, and your transcription language is remembered.",
            "Conversations are stored with device protection, can be kept out of iCloud backup, and History is searchable. " +
                "The app never contacts ollama.com unless you chose Ollama."
        ]),
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
