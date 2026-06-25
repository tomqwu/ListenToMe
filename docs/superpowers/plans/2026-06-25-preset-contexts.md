# Preset Context System Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add use-case presets (Meeting, Interview, etc.) that fill the Context-notes field and tailor the AI panes' behavior via persona guidance injected into prompts.

**Architecture:** A pure `PresetCatalog` in `ListenToMeCore` defines `Preset` values (notes template + persona guidance). `PromptContext` gains a `personaGuidance` field threaded through `ContextEngine.buildContext` → `PromptBuilder` (appended to system prompts), mirroring the existing `responseLanguage` pattern. `MeetingSession.personaGuidance` is set from a SwiftUI preset picker.

**Tech Stack:** Swift 6, SwiftUI, XCTest, ListenToMeCore SwiftPM package.

---

### Task 1: Preset model + catalog (Core)

**Files:**
- Create: `Sources/ListenToMeCore/PresetCatalog.swift`
- Test: `Tests/ListenToMeCoreTests/PresetCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class PresetCatalogTests: XCTestCase {
    func testNoneIsDefaultAndEmpty() {
        XCTAssertEqual(PresetCatalog.none.id, "none")
        XCTAssertTrue(PresetCatalog.none.notesTemplate.isEmpty)
        XCTAssertTrue(PresetCatalog.none.personaGuidance.isEmpty)
    }

    func testAllStartsWithNoneAndHasUniqueIDs() {
        XCTAssertEqual(PresetCatalog.all.first, PresetCatalog.none)
        XCTAssertEqual(Set(PresetCatalog.all.map(\.id)).count, PresetCatalog.all.count)
    }

    func testLookupByIDFallsBackToNone() {
        XCTAssertEqual(PresetCatalog.preset(id: "interview-candidate").id, "interview-candidate")
        XCTAssertEqual(PresetCatalog.preset(id: "nonexistent"), PresetCatalog.none)
    }

    func testRealPresetsHaveGuidanceAndNotes() {
        for preset in PresetCatalog.all where preset.id != "none" {
            XCTAssertFalse(preset.name.isEmpty, "\(preset.id) needs a name")
            XCTAssertFalse(preset.personaGuidance.isEmpty, "\(preset.id) needs guidance")
            XCTAssertFalse(preset.notesTemplate.isEmpty, "\(preset.id) needs a notes template")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PresetCatalogTests`
Expected: FAIL — `PresetCatalog` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A use-case preset: seeds the Context-notes field and tailors the AI panes via persona guidance.
public struct Preset: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Seed text placed into the Context-notes field (editable afterward).
    public let notesTemplate: String
    /// Short instruction appended to the AI panes' system prompts to set role/tone/focus.
    public let personaGuidance: String
    public init(id: String, name: String, notesTemplate: String, personaGuidance: String) {
        self.id = id
        self.name = name
        self.notesTemplate = notesTemplate
        self.personaGuidance = personaGuidance
    }
}

/// The built-in preset catalog. Pure and testable.
public enum PresetCatalog {
    public static let none = Preset(id: "none", name: "None", notesTemplate: "", personaGuidance: "")

    public static let all: [Preset] = [
        none,
        Preset(id: "meeting", name: "Meeting",
               notesTemplate: "Meeting topic:\nAttendees:\nMy role:\nGoals/decisions needed:",
               personaGuidance: "This is a work meeting. Help the user contribute: surface decisions, action items, and crisp talking points they can say next."),
        Preset(id: "one-on-one", name: "1:1",
               notesTemplate: "With (name/role):\nTopics to cover:\nMy goals:",
               personaGuidance: "This is a 1:1 conversation. Favor thoughtful, candid, supportive responses and good follow-up questions."),
        Preset(id: "standup", name: "Standup",
               notesTemplate: "Team:\nMy current work:\nBlockers:",
               personaGuidance: "This is a standup. Keep suggestions to brief status-style updates and concrete blockers/next steps."),
        Preset(id: "sales-call", name: "Sales call",
               notesTemplate: "Prospect/company:\nProduct:\nDeal stage:\nObjections expected:",
               personaGuidance: "This is a sales call. Help the user handle objections, qualify needs, and propose next steps persuasively but honestly."),
        Preset(id: "interview-candidate", name: "Interview (candidate)",
               notesTemplate: "Role:\nCompany:\nKey JD points:\nMy relevant experience:",
               personaGuidance: "The user is the candidate in a job interview. Quick: suggest concise first-person answers they can say aloud. Deep: give structured answers (e.g. STAR) with reasoning."),
        Preset(id: "interview-interviewer", name: "Interview (interviewer)",
               notesTemplate: "Role being filled:\nCandidate:\nSignals to assess:",
               personaGuidance: "The user is the interviewer. Suggest probing follow-up questions and note signals about the candidate's answers."),
        Preset(id: "technical-interview", name: "Technical interview",
               notesTemplate: "Role/stack:\nProblem area:\nMy approach:",
               personaGuidance: "This is a technical/coding interview where the user is the candidate. Deep: provide correct, well-explained solutions with complexity analysis and code. Quick: concise hints the user can voice while thinking aloud."),
        Preset(id: "lecture", name: "Lecture / study",
               notesTemplate: "Subject:\nTopic:\nWhat I want to understand:",
               personaGuidance: "This is a lecture or study session. Summarize key concepts, define terms, and surface questions worth asking."),
        Preset(id: "support", name: "Customer support",
               notesTemplate: "Product:\nCustomer issue:\nKnown fixes:",
               personaGuidance: "This is a customer support call. Help the user diagnose the issue and give clear, empathetic step-by-step guidance."),
        Preset(id: "medical", name: "Medical consult",
               notesTemplate: "Context (clinician/patient):\nConcern:\nHistory notes:",
               personaGuidance: "This is a medical consultation. Help organize symptoms, questions, and next steps. Be factual and cautious; do not give definitive diagnoses — defer to a professional."),
        Preset(id: "legal", name: "Legal consult",
               notesTemplate: "Matter:\nParties:\nKey facts:",
               personaGuidance: "This is a legal consultation. Help organize facts, issues, and questions. Be factual and cautious; this is not legal advice — defer to a qualified professional."),
        Preset(id: "brainstorm", name: "Brainstorm",
               notesTemplate: "Topic:\nConstraints:\nGoal:",
               personaGuidance: "This is a brainstorming session. Offer divergent ideas, build on what's said, and ask generative questions.")
    ]

    /// The preset with this id, or `none` if unknown.
    public static func preset(id: String) -> Preset {
        all.first { $0.id == id } ?? none
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PresetCatalogTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ListenToMeCore/PresetCatalog.swift Tests/ListenToMeCoreTests/PresetCatalogTests.swift
git commit -m "Add preset catalog (use-case contexts)"
```

---

### Task 2: Thread personaGuidance through PromptContext + PromptBuilder (Core)

**Files:**
- Modify: `Sources/ListenToMeCore/Prompt.swift`
- Test: `Tests/ListenToMeCoreTests/PromptBuilderTests.swift`

- [ ] **Step 1: Add the failing tests** (append to `PromptBuilderTests`, and extend the `ctx` helper)

Update the existing `ctx` helper signature to add `personaGuidance`:

```swift
    private func ctx(notes: String? = nil, summary: String? = nil,
                     responseLanguage: String? = nil, references: String? = nil,
                     personaGuidance: String? = nil) -> PromptContext {
        PromptContext(messages: [
            TranscriptSegment(source: .others, text: "What is our deploy plan?",
                              isFinal: true, start: 0, end: 1),
            TranscriptSegment(source: .you, text: "Good question.",
                              isFinal: true, start: 1, end: 2)
        ], notes: notes, summary: summary, responseLanguage: responseLanguage,
           references: references, personaGuidance: personaGuidance)
    }
```

Add tests:

```swift
    func testPersonaGuidanceAppendedToAllPanes() {
        let guidance = "The user is the candidate in a job interview."
        XCTAssertTrue(PromptBuilder.build(context: ctx(personaGuidance: guidance),
                                          action: .answerQuestion).system.contains(guidance))
        XCTAssertTrue(PromptBuilder.buildDeep(context: ctx(personaGuidance: guidance),
                                              action: .answerQuestion).system.contains(guidance))
        XCTAssertTrue(PromptBuilder.buildListener(context: ctx(personaGuidance: guidance))
                        .system.contains(guidance))
    }

    func testPersonaGuidanceOmittedWhenNilOrBlank() {
        XCTAssertFalse(PromptBuilder.build(context: ctx(personaGuidance: nil),
                                           action: .answerQuestion).system.contains("Context for this session"))
        XCTAssertFalse(PromptBuilder.build(context: ctx(personaGuidance: "  "),
                                           action: .answerQuestion).system.contains("Context for this session"))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PromptBuilderTests`
Expected: FAIL — `personaGuidance:` is not a parameter of `PromptContext.init`.

- [ ] **Step 3: Implement**

In `Prompt.swift`, add the field to `PromptContext`:

```swift
    /// Attached reference material (file/folder contents) to ground answers; nil = none.
    public let references: String?
    /// Use-case persona/role guidance from a preset, appended to every pane's system prompt.
    public let personaGuidance: String?
    public init(messages: [TranscriptSegment], notes: String?, summary: String? = nil,
                responseLanguage: String? = nil, references: String? = nil,
                personaGuidance: String? = nil) {
        self.messages = messages
        self.notes = notes
        self.summary = summary
        self.responseLanguage = responseLanguage
        self.references = references
        self.personaGuidance = personaGuidance
    }
```

Replace `systemWithLanguage` with a combined directive builder and update its three call sites
(`build`, `buildDeep`, `buildListener`) to use it:

```swift
    /// Appends preset persona guidance and a response-language directive to a system prompt.
    private static func systemWithDirectives(_ base: String, _ context: PromptContext) -> String {
        var system = base
        if let persona = context.personaGuidance,
           !persona.trimmingCharacters(in: .whitespaces).isEmpty {
            system += "\nContext for this session: \(persona)"
        }
        if let lang = context.responseLanguage,
           !lang.trimmingCharacters(in: .whitespaces).isEmpty {
            system += "\nAlways write your entire response in \(lang), regardless of the " +
                "language spoken in the transcript."
        }
        return system
    }
```

Then change `build` to `system: systemWithDirectives(systemPrompt, context)`, `buildDeep` to
`system: systemWithDirectives(deepSystemPrompt, context)`, and `buildListener` to
`system: systemWithDirectives(listenerSystemPrompt, context)`. Delete the old `systemWithLanguage`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PromptBuilderTests`
Expected: PASS (existing response-language tests still pass — the language directive text is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/ListenToMeCore/Prompt.swift Tests/ListenToMeCoreTests/PromptBuilderTests.swift
git commit -m "Inject preset persona guidance into pane system prompts"
```

---

### Task 3: Thread personaGuidance through ContextEngine + MeetingSession (Core)

**Files:**
- Modify: `Sources/ListenToMeCore/ContextEngine.swift`, `Sources/ListenToMeCore/MeetingSession.swift`
- Test: `Tests/ListenToMeCoreTests/ContextEngineTests.swift`

- [ ] **Step 1: Add the failing test** (append to `ContextEngineTests`)

```swift
    func testBuildContextIncludesTrimmedPersonaGuidance() {
        let store = ConversationStore()
        let engine = ContextEngine(debounce: 5)
        let ctx = engine.buildContext(from: store, notes: nil, personaGuidance: "  interview  ")
        XCTAssertEqual(ctx.personaGuidance, "interview")
    }

    func testBuildContextPersonaNilWhenEmpty() {
        let store = ConversationStore()
        let engine = ContextEngine(debounce: 5)
        XCTAssertNil(engine.buildContext(from: store, notes: nil, personaGuidance: "  ").personaGuidance)
        XCTAssertNil(engine.buildContext(from: store, notes: nil).personaGuidance)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ContextEngineTests`
Expected: FAIL — `personaGuidance:` not a parameter of `buildContext`.

- [ ] **Step 3: Implement**

In `ContextEngine.swift`, add the parameter and pass it through (trimmed → nil when empty):

```swift
    public func buildContext(from store: ConversationStore, notes: String?, maxChars: Int = 4000,
                             summary: String? = nil, responseLanguage: String? = nil,
                             references: String? = nil, personaGuidance: String? = nil) -> PromptContext {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLang = responseLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRefs = references?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersona = personaGuidance?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PromptContext(
            messages: store.recentContext(maxChars: maxChars),
            notes: (trimmed?.isEmpty == false) ? trimmed : nil,
            summary: (trimmedSummary?.isEmpty == false) ? trimmedSummary : nil,
            responseLanguage: (trimmedLang?.isEmpty == false) ? trimmedLang : nil,
            references: (trimmedRefs?.isEmpty == false) ? trimmedRefs : nil,
            personaGuidance: (trimmedPersona?.isEmpty == false) ? trimmedPersona : nil
        )
    }
```

In `MeetingSession.swift`, add a public property next to `responseLanguage`:

```swift
    /// Use-case persona guidance from the selected preset, injected into all pane prompts.
    public var personaGuidance: String?
```

Then add `personaGuidance: self.personaGuidance` to every `buildContext(...)` call in
`respondQuick`, `respondDeep`, the proactive-quick block in `ingest`, and `startListenerRefresh`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: PASS — full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/ListenToMeCore/ContextEngine.swift Sources/ListenToMeCore/MeetingSession.swift Tests/ListenToMeCoreTests/ContextEngineTests.swift
git commit -m "Thread persona guidance through ContextEngine and MeetingSession"
```

---

### Task 4: Preset picker UI (App)

**Files:**
- Modify: `App/MeetingView.swift`, `App/SettingsView.swift` (ProviderSettings persistence)

- [ ] **Step 1: Add persistence to `ProviderSettings`** (in `SettingsView.swift`)

```swift
    /// Selected use-case preset id; empty = none.
    static var presetID: String {
        get { UserDefaults.standard.string(forKey: "presetID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "presetID") }
    }
```

- [ ] **Step 2: Add preset state + picker to `MeetingView`**

Add state:

```swift
    @State private var presetID: String
```

Initialize in `init()` (after `transcriptionLocaleID`):

```swift
        _presetID = State(initialValue: ProviderSettings.presetID)
```

Apply persona on appear (in the existing `.onAppear`, after `responseLanguage`):

```swift
            session.personaGuidance = PresetCatalog.preset(id: presetID).personaGuidance
```

Add a picker to `referenceFilesRow` or the transcript header. Place it just above the
Context-notes `TextField` in `transcriptPane`, before the `TextField` line:

```swift
            Picker("Preset", selection: $presetID) {
                ForEach(PresetCatalog.all) { preset in Text(preset.name).tag(preset.id) }
            }
            .labelsHidden()
            .onChange(of: presetID) { _, newID in
                let preset = PresetCatalog.preset(id: newID)
                ProviderSettings.presetID = newID
                session.personaGuidance = preset.personaGuidance
                if !preset.notesTemplate.isEmpty { session.notes = preset.notesTemplate }
            }
            .help("Use-case preset — fills Context notes and tailors the AI panes")
```

- [ ] **Step 3: Build + lint**

Run: `make build && swiftlint lint --quiet`
Expected: `** BUILD SUCCEEDED **`, no SwiftLint errors.

- [ ] **Step 4: Commit**

```bash
git add App/MeetingView.swift App/SettingsView.swift
git commit -m "Add use-case preset picker to the transcript pane"
```

---

### Task 5: Coverage + full verification

- [ ] **Step 1: Run tests + coverage**

Run: `make test && bash scripts/check-coverage.sh`
Expected: all tests pass; coverage ≥ 95%.

- [ ] **Step 2: Codex review + PR**

Run the Codex branch review; open a PR; wait for CI; merge; rebuild + launch.
