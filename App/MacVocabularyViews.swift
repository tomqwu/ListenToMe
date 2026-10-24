import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

/// The on-device vocabulary suggestion above the transcript (issue #222). It never turns anything on by
/// itself. It also hosts the "Add to My terms" sheet opened from a transcript line's context menu.
struct MacVocabularyBanner: View {
    @Bindable var vocabulary: SessionVocabulary
    let conversationID: String
    /// Re-applies the vocabularies to the session after a choice changes them.
    let apply: () -> Void

    var body: some View {
        Group {
            if let suggestion = vocabulary.banner(for: conversationID) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: suggestion.stage == .added ? "checkmark.circle" : "text.book.closed")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.stage == .added
                             ? "\(suggestion.domain.name) vocabulary is on for this conversation."
                             : suggestion.domain.suggestionText)
                            .foregroundStyle(Theme.ink)
                        if suggestion.stage == .offered, let notice = suggestion.domain.notice {
                            Text(notice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if suggestion.stage == .offered {
                        Button("Add") { vocabulary.addSuggested(); apply() }.keyboardShortcut(.defaultAction)
                        Button("Not now") { vocabulary.dismissSuggestion() }
                        Button("Don’t suggest \(suggestion.domain.name) again") { vocabulary.muteSuggested() }
                    } else {
                        Button("Use by default") { vocabulary.useSuggestedByDefault(); apply() }
                        Button("Done") { vocabulary.dismissSuggestion() }
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.08))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("vocabularySuggestion")
            }
        }
        .sheet(isPresented: Binding(get: { vocabulary.termSourceLine != nil },
                                    set: { if !$0 { vocabulary.termSourceLine = nil } })) {
            MacAddTermSheet(line: vocabulary.termSourceLine ?? "") { term in
                let problem = vocabulary.addTerm(term)
                if problem == nil { apply() }
                return problem
            } done: { vocabulary.termSourceLine = nil }
        }
    }
}

/// "Add to My terms" from a transcript line: one click on a word or name from it, or type your own.
struct MacAddTermSheet: View {
    let line: String
    let add: (String) -> String?
    let done: () -> Void
    @State private var custom = ""
    @State private var added: [String] = []
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to My terms").font(.title3).bold()
            Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            let candidates = VocabularyText.candidates(in: line)
            if candidates.isEmpty { Text("No distinctive words in this line. Type one below.").font(.callout) }
            FlowButtons(terms: candidates, added: added) { submit($0) }
            HStack {
                TextField("Or type a term", text: $custom).textFieldStyle(.roundedBorder).onSubmit { submit(custom) }
                Button("Add") { submit(custom) }.disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            HStack { Spacer(); Button("Done", action: done).keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 460)
    }

    private func submit(_ term: String) {
        problem = add(term)
        if problem == nil { added.append(term); if term == custom { custom = "" } }
    }
}

/// Candidate terms as wrapping buttons.
private struct FlowButtons: View {
    let terms: [String]
    let added: [String]
    let tap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(terms, id: \.self) { term in
                Button { tap(term) } label: {
                    Label(term, systemImage: added.contains(term) ? "checkmark.circle.fill" : "plus.circle")
                        .lineLimit(1)
                }.disabled(added.contains(term))
            }
        }
    }
}

/// Settings → Vocabularies. Applies immediately, like Save to folder; the meeting window reloads the
/// choices when Settings closes.
struct MacVocabularySettings: View {
    private let store = VocabularySettingsStore()
    private let catalog = VocabularyCatalog.bundled
    @State private var settings = VocabularySettingsStore().load()
    @State private var newTerm = ""
    @State private var problem: String?

    var body: some View {
        Text("Vocabularies").font(.headline)
        Toggle("Suggest a vocabulary when a conversation sounds medical, legal, technical…",
               isOn: $settings.suggestionsEnabled)
        ForEach(catalog.domains.filter { settings.isMuted($0.id) }) { domain in
            Button("Suggest \(domain.name) again") { settings.setMuted(domain.id, false) }
        }
        ForEach(catalog.domains) { domain in
            Toggle(isOn: Binding(get: { settings.isDefault(domain.id) }, set: { settings.setDefault(domain.id, $0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(domain.name) · \(domain.terms.count) terms")
                    if let notice = domain.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
        Toggle("Organize summaries by domain", isOn: $settings.domainSummaryLayout)
        Toggle("Use My terms", isOn: $settings.myTermsEnabled)
        HStack {
            TextField("Add a name, product or phrase", text: $newTerm).textFieldStyle(.roundedBorder)
                .onSubmit(addTerm)
            Button("Add", action: addTerm).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Import…", action: importTerms)
            Button("Export…", action: exportTerms).disabled(settings.myTerms.isEmpty)
        }
        if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        ForEach(settings.myTerms, id: \.self) { term in
            HStack {
                Text(term)
                Spacer()
                Button { settings.removeTerm(term) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove \(term)")
            }
        }
        Text("Terms help on-device recognition (at most \(ActiveVocabulary.recognitionLimit): My terms first, " +
             "up to \(ActiveVocabulary.myTermsRecognitionShare) when a preset is on), AI summaries and answers. " +
             "Presets are English-first; My terms accept any language. The suggestion is checked on this Mac; " +
             "nothing is sent anywhere, and a vocabulary is never turned on without you. Right-click a transcript " +
             "line to add a word.")
            .font(.caption).foregroundStyle(.secondary)
            .onChange(of: settings) { _, new in store.save(new) }
    }

    private func addTerm() {
        problem = settings.rejection(of: newTerm)
        if problem == nil { settings.addTerm(newTerm); newTerm = "" }
    }

    private func importTerms() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a text file with one term per line."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = settings.importTerms(from: try String(contentsOf: url, encoding: .utf8))
            problem = added == 1 ? "Added 1 term." : "Added \(added) terms."
        } catch {
            problem = "Could not import: \(error.localizedDescription)"
        }
    }

    private func exportTerms() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "My terms.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportedText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            problem = "Could not export: \(error.localizedDescription)"
        }
    }
}

extension MeetingView {
    /// Hands the active vocabularies to the session: recognition terms to the transcriber (live, no
    /// restart) and the domain guidance into the persona line every pane's prompt carries, so its cost
    /// is measured with the rest of the prompt scaffold.
    func applyVocabulary() {
        let active = vocabulary.active(for: currentSessionID)
        session.contextualStrings = active.recognitionTerms()
        let window = ProviderSettings.aiMode == .apple ? PromptBudget.appleIntelligenceCharacters : nil
        let limit = VocabularyPrompt.characterLimit(forPromptWindow: window)
        session.personaGuidance = VocabularyPrompt.combined(
            persona: PresetCatalog.preset(id: presetID).personaGuidance,
            guidance: VocabularyPrompt.guidance(for: active, characterLimit: limit))
    }

    /// Counts newly finalized lines toward the on-device suggestion check.
    func considerVocabularySuggestion() {
        vocabulary.heard(transcript: store.utterances.map(\.text), conversationID: currentSessionID)
    }
}
