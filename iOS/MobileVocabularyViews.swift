import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

/// The non-blocking suggestion (issue #222): "Sounds like a medical conversation — add the Medical
/// vocabulary?" It never turns anything on by itself, and each preset is offered once per conversation.
struct MobileVocabularyBanner: View {
    let session: MobileSession

    var body: some View {
        if let suggestion = session.vocabulary.banner(for: session.id) {
            VStack(alignment: .leading, spacing: 8) {
                switch suggestion.stage {
                case .offered:
                    Label(suggestion.domain.suggestionText, systemImage: "text.book.closed")
                        .font(.callout.weight(.medium)).foregroundStyle(MobileStyle.ink)
                        .accessibilityIdentifier("vocabularySuggestionText")
                    if let notice = suggestion.domain.notice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { offeredButtons(suggestion) }
                        VStack(alignment: .leading, spacing: 6) { offeredButtons(suggestion) }
                    }
                case .added:
                    Label("\(suggestion.domain.name) vocabulary is on for this conversation.",
                          systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(MobileStyle.ink)
                        .accessibilityIdentifier("vocabularyAddedText")
                    HStack(spacing: 10) {
                        Button("Use by default") { session.useSuggestedVocabularyByDefault() }
                            .buttonStyle(.bordered).accessibilityIdentifier("vocabularyUseByDefault")
                        Button("Done") { session.vocabulary.dismissSuggestion() }
                            .accessibilityIdentifier("vocabularyDone")
                    }.font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(MobileStyle.accent.opacity(0.1)))
            .padding(.horizontal, 20).padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("vocabularySuggestion")
        }
    }

    @ViewBuilder private func offeredButtons(_ suggestion: SessionVocabulary.Suggestion) -> some View {
        Button("Add") { session.addSuggestedVocabulary() }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("vocabularyAdd")
        Button("Not now") { session.vocabulary.dismissSuggestion() }
            .buttonStyle(.bordered).accessibilityIdentifier("vocabularyNotNow")
        Button("Don’t suggest \(suggestion.domain.name) again") { session.vocabulary.muteSuggested() }
            .font(.caption).accessibilityIdentifier("vocabularyMute")
    }
}

/// Settings → Vocabularies, as one row in the Settings form.
struct MobileVocabularySettingsLink: View {
    let session: MobileSession

    var body: some View {
        Section {
            NavigationLink {
                MobileVocabularySettingsView(session: session)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Vocabularies", systemImage: "text.book.closed")
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("vocabularySettings")
        } footer: {
            Text("Domain terms and your own words help recognition, AI correction and summaries. " +
                 "Stored on this device.")
        }
    }

    private var summary: String {
        let settings = session.vocabulary.settings
        let names = session.vocabulary.catalog.domains.filter { settings.isDefault($0.id) }.map(\.name)
        let mine = settings.myTerms.isEmpty ? "No terms of your own" : "\(settings.myTerms.count) of your terms"
        return (names.isEmpty ? "No presets by default" : names.joined(separator: ", ")) + " · " + mine
    }
}

struct MobileVocabularySettingsView: View {
    let session: MobileSession
    @State private var newTerm = ""
    @State private var problem: String?
    @State private var editing: Int?
    @State private var editText = ""
    @State private var importing = false
    @State private var importResult: String?

    private var vocabulary: SessionVocabulary { session.vocabulary }

    private func binding<Value>(_ keyPath: WritableKeyPath<VocabularySettings, Value>) -> Binding<Value> {
        Binding(get: { vocabulary.settings[keyPath: keyPath] }, set: { vocabulary.settings[keyPath: keyPath] = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Suggest vocabularies", isOn: binding(\.suggestionsEnabled))
                    .accessibilityIdentifier("vocabularySuggestionsToggle")
                Text("After about a minute of speech, ListenToMe checks on this device whether the conversation " +
                     "sounds medical, legal, technical… and may offer a vocabulary. Nothing is sent anywhere and " +
                     "nothing turns on without you.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(vocabulary.catalog.domains.filter { vocabulary.settings.isMuted($0.id) }) { domain in
                    Button("Suggest \(domain.name) again") { vocabulary.settings.setMuted(domain.id, false) }
                        .accessibilityIdentifier("unmute-\(domain.id)")
                }
            } header: { Text("Suggestions") }
            Section {
                ForEach(vocabulary.catalog.localized(for: session.vocabularyLanguage).domains) { domain in presetRow(domain) }
                Toggle("Organize summaries by domain", isOn: binding(\.domainSummaryLayout))
                    .accessibilityIdentifier("vocabularyLayoutToggle")
            } header: { Text("Presets") } footer: {
                Text("Presets use Simplified Chinese terms for Chinese (Simplified) transcription, and English terms " +
                     "for other languages. My terms accepts any language. Speech recognition receives at " +
                     "most \(ActiveVocabulary.recognitionLimit) terms: My terms first (up to " +
                     "\(ActiveVocabulary.myTermsRecognitionShare) when a preset is on), then the presets'.")
            }
            myTermsSection
        }
        .navigationTitle("Vocabularies").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("vocabularySettingsForm")
        .onChange(of: vocabulary.settings) { _, _ in session.applyVocabularyToRecording() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
            importResult = importTerms(result)
        }
        .alert("Edit term", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Term", text: $editText).accessibilityIdentifier("editTermField")
            Button("Save") {
                if let index = editing, !vocabulary.settings.replaceTerm(at: index, with: editText) {
                    problem = vocabulary.settings.rejection(of: editText, replacing: index)
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    @ViewBuilder private func presetRow(_ domain: VocabularyDomain) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(domain.name, isOn: Binding(get: { vocabulary.settings.isDefault(domain.id) },
                                              set: { vocabulary.settings.setDefault(domain.id, $0) }))
                .accessibilityIdentifier("preset-\(domain.id)")
            Text("\(domain.terms.count) terms · \(domain.description)").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("preset-detail-\(domain.id)")
            if let notice = domain.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
            if !vocabulary.settings.isDefault(domain.id), vocabulary.domainIDs(for: session.id).contains(domain.id) {
                HStack {
                    Text("On for this conversation").font(.caption).foregroundStyle(MobileStyle.accent)
                    Spacer()
                    Button("Turn off") {
                        vocabulary.remove(domain.id, from: session.id)
                        session.applyVocabularyToRecording()
                    }.font(.caption).buttonStyle(.borderless)
                }
            }
        }
    }

    private var myTermsSection: some View {
        Section {
            Toggle("Use My terms", isOn: binding(\.myTermsEnabled)).accessibilityIdentifier("myTermsToggle")
            HStack {
                TextField("Add a name, product or phrase", text: $newTerm)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(addNewTerm).accessibilityIdentifier("newTermField")
                Button("Add", action: addNewTerm).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("addTermButton")
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("termProblem")
            }
            ForEach(Array(vocabulary.settings.myTerms.enumerated()), id: \.element) { index, term in
                Button(term) { editText = term; editing = index }
                    .foregroundStyle(.primary).accessibilityIdentifier("myTerm-\(term)")
            }
            .onDelete { offsets in vocabulary.settings.myTerms.remove(atOffsets: offsets) }
            Button("Import from a text file…") { importing = true }.accessibilityIdentifier("importTerms")
            ShareLink("Export as plain text", item: vocabulary.settings.exportedText)
                .disabled(vocabulary.settings.myTerms.isEmpty).accessibilityIdentifier("exportTerms")
            if let importResult { Text(importResult).font(.caption).accessibilityIdentifier("importResult") }
        } header: { Text("My terms") } footer: {
            Text("People, products and company jargon, in any language. One term per line when importing. " +
                 "Long-press a transcript line to add a word from it.")
        }
    }

    private func addNewTerm() {
        problem = vocabulary.addTerm(newTerm)
        if problem == nil { newTerm = "" }
    }

    private func importTerms(_ result: Result<URL, Error>) -> String {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let added = vocabulary.settings.importTerms(from: try String(contentsOf: url, encoding: .utf8))
            return added == 1 ? "Added 1 term." : "Added \(added) terms."
        } catch {
            return "Could not import: \(error.localizedDescription)"
        }
    }
}

/// "Add to My terms" from a transcript line: one tap on a word or name from the line, or type your own.
struct MobileAddTermSheet: View {
    let line: String
    let add: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var added: [String] = []
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("From this line") {
                    Text(line).font(.callout).foregroundStyle(.secondary)
                    let candidates = VocabularyText.candidates(in: line)
                    if candidates.isEmpty { Text("No distinctive words in this line. Type one below.") }
                    ForEach(candidates, id: \.self) { term in
                        Button { submit(term) } label: {
                            HStack {
                                Text(term).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: added.contains(term) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(MobileStyle.accent)
                            }
                        }.disabled(added.contains(term)).accessibilityIdentifier("candidate-\(term)")
                    }
                }
                Section("Or type it") {
                    TextField("Term", text: $custom).onSubmit { submit(custom) }
                        .accessibilityIdentifier("customTermField")
                    Button("Add to My terms") { submit(custom) }
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Add to My terms").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("addTermDone") }
        }
    }

    private func submit(_ term: String) {
        problem = add(term)
        if problem == nil { added.append(term); if term == custom { custom = "" } }
    }
}
