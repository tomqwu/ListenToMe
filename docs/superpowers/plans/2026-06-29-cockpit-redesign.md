# Cockpit Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-layout the ListenToMe main window into a "cockpit": a slim top bar (with a single ⚙ Configure popover), transcript on the **left**, the live Listener / situational-awareness pane in the **center** (with a glowing accent ring), Quick reply on the **right**, and the Deep answer as a full-width **bottom** strip — all in a dark "Glass HUD" visual style.

**Architecture:** Pure SwiftUI view-layer change. No engine/model logic changes — `MeetingSession`, `ConversationStore`, and `MeetingSession.listenerSummary/quickSuggestion/deepAnswer` stay exactly as they are. We (1) add Glass-HUD design tokens + a `.hudPanel(ring:)` modifier to `Theme.swift`; (2) move the left status rail's controls into a top-bar **Configure** popover; (3) recompose `MeetingView.body` from `VStack{topBar; HSplitView{rail, transcript, copilot}; footer}` into `VStack{slimTopBar; VSplitView{ HSplitView{transcript, listenerCenter, quick}; deepStrip }; footer}`; (4) apply the Glass-HUD styling; (5) update docs.

**Tech Stack:** SwiftUI (macOS), AppKit interop for dynamic colors, SwiftPM `ListenToMeCore` library. Build via `make` (Xcode under the hood).

## Global Constraints

- **No engine/behavior changes.** Only files under `App/` (plus the smoke-test doc) change. Do **not** touch `Sources/ListenToMeCore/`.
- **Preserve every existing action.** Listen/Stop, elapsed timer, refresh-models, import-audio, export menu (Markdown/Recap/PDF), copy-session, search, permissions, settings, language, proactive toggle, preset, per-role model pickers, references, load-from-calendar, identify-speakers, session stats — all must remain reachable after the redesign.
- **Verification reality:** this repo has **no UI unit tests** (engine-only tests in `Tests/ListenToMeCoreTests`). View tasks are verified by `make build` (must compile clean) plus the stated visual check via `make run`. Do **not** invent SwiftUI unit tests — that breaks the established pattern.
- **Build command:** `make build` (runs `make gen` first). **Run:** `make run`. **Full check:** `make e2e`.
- **Theme is the single source of truth** for color/chrome (`App/Theme.swift`). New visual tokens go there, never hard-coded in views.
- **Dark-default, but keep light usable.** All new color tokens use `Theme.dynamic(light:dark:)` so both appearances resolve (the app merely *defaults* to dark).
- **Accent values (verbatim):** accent indigo `#5b63f0` = `Theme.accent`; deep purple `#7c4ddb` = `Theme.accentDeep`; HUD panel stroke ≈ `#2b3a6b`.

---

### Task 1: Glass-HUD theme foundation

Add the Glass-HUD design tokens and a reusable `.hudPanel(ring:)` modifier to `Theme.swift`. No view consumes it yet — this task only extends the token set and must compile. The `ring` variant is the glowing accent treatment for the center Listener pane; the plain variant is for the side/bottom panels.

**Files:**
- Modify: `App/Theme.swift` (add tokens after line 43; add a `HudPanel` modifier + `.hudPanel` extension)

**Interfaces:**
- Consumes: existing `Theme.dynamic(light:dark:)` (private), `Theme.accent`, `Theme.cornerRadius`, `Theme.paneSpacing`.
- Produces (used by Tasks 2–4):
  - `Theme.glassPanelFill: Color` — translucent panel fill
  - `Theme.glassStroke: Color` — HUD panel hairline/glow stroke
  - `Theme.glassStrokeStrong: Color` — brighter stroke for emphasis
  - `func View.hudPanel(ring: Bool = false, padding: CGFloat = Theme.paneSpacing) -> some View`

- [ ] **Step 1: Add the Glass-HUD color tokens and an alpha helper**

In `App/Theme.swift`, immediately after the `static let paneSpacing: CGFloat = 10` line (currently line 43), insert:

```swift

    // MARK: Glass HUD

    /// Translucent panel fill layered over `.ultraThinMaterial` for the "instrument cluster" look.
    /// dark = deep navy at ~55% / light = white at ~60%.
    static let glassPanelFill = dynamicA(light: nsColorA(1, 1, 1, 0.60),
                                         dark: nsColorA(0.075, 0.086, 0.149, 0.55))
    /// HUD panel hairline — a cool indigo so the dark panels read as glowing instruments. ≈ `#2b3a6b`.
    static let glassStroke = dynamic(light: nsColor(0.882, 0.871, 0.933),
                                     dark: nsColor(0.169, 0.227, 0.420))
    /// Brighter stroke for emphasis / hover. ≈ `#3a4a8b`.
    static let glassStrokeStrong = dynamic(light: nsColor(0.804, 0.792, 0.882),
                                           dark: nsColor(0.227, 0.290, 0.545))
```

- [ ] **Step 2: Add the alpha-aware color helpers**

In `App/Theme.swift`, in the `// MARK: Helpers` section, immediately after the existing `nsColor(_:_:_:)` function (currently ends at line 49), insert:

```swift

    private static func nsColorA(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Alpha-preserving variant of `dynamic(light:dark:)`.
    private static func dynamicA(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
```

- [ ] **Step 3: Add the `HudPanel` modifier**

In `App/Theme.swift`, inside `enum Theme`, immediately after the closing brace of the `PaneCard` struct (currently line 76, just before the final `}` of the enum), insert:

```swift

    /// Glass-HUD panel chrome: translucent fill over `.ultraThinMaterial`, a glowing indigo stroke,
    /// and an outer shadow. `ring: true` is the emphasized treatment for the live center pane
    /// (accent stroke + accent glow), used to mark "where we are right now".
    struct HudPanel: ViewModifier {
        var ring: Bool = false
        var padding: CGFloat = Theme.paneSpacing

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Theme.glassPanelFill)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(ring ? Theme.accent.opacity(0.9) : Theme.glassStroke,
                                lineWidth: ring ? 1.5 : 1)
                )
                .shadow(color: (ring ? Theme.accent : Color.black).opacity(ring ? 0.30 : 0.22),
                        radius: ring ? 22 : 12, y: ring ? 0 : 4)
        }
    }
```

- [ ] **Step 4: Add the `.hudPanel` View extension**

In `App/Theme.swift`, inside the existing `extension View { ... }` block (after the `paneCard` function, currently around line 83), insert:

```swift

    /// Wraps the view in the Glass-HUD panel chrome. `ring: true` for the live center pane.
    func hudPanel(ring: Bool = false, padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.HudPanel(ring: ring, padding: padding))
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `make build`
Expected: builds cleanly (no errors). Nothing visually changes yet — no view uses `.hudPanel` this task.

- [ ] **Step 6: Commit**

```bash
git add App/Theme.swift
git commit -m "feat(ui): add Glass-HUD theme tokens and .hudPanel modifier"
```

---

### Task 2: Configure popover (fold the rail's controls into the top bar)

Create a single ⚙ **Configure** popover holding everything the left status rail held (language, proactive, models, references, load-from-calendar, identify-speakers, session stats) and add it to the **slim top bar**, which also surfaces the preset inline and keeps every existing icon action. The old `statusRail` still exists in the layout after this task (controls are temporarily reachable in *both* places) — that's intentional so the app stays buildable and testable; the rail is removed in Task 3.

**Files:**
- Create: `App/ConfigurePanel.swift`
- Modify: `App/CommandCenterPanes.swift` (drop `private` from `railSection`, `speakersRailSection`, `languageBinding`, `presetBinding` so the popover/slim-bar in other files can call them)
- Modify: `App/MeetingView.swift` (add `@State showConfigure`; replace `topControlBar` with `slimTopBar`; call `slimTopBar` from `body`)

**Interfaces:**
- Consumes: `MeetingView.railSection(_:content:)`, `.speakersRailSection()`, `.languageBinding(session:)`, `.presetBinding(session:)`, `.modelPicker(role:session:label:)`, `.referenceFilesRow(session:)`, `.loadFromCalendar(session:)`, `MeetingView.languageOptions`, `MeetingView.railRoleName(_:)` (make non-private as needed), session stat helpers `youCount`/`othersCount`/`approxTokens`, `ProviderSettings.transcriptionEngine`, `CommandCenterLabels.engine(_:)`, `PresetCatalog.all`, `CopilotRole.allCases`.
- Produces (used by Task 3+): `func MeetingView.configurePopover(session:) -> some View`, `func MeetingView.slimTopBar(session:showPermissions:) -> some View`, `@State MeetingView.showConfigure`.

- [ ] **Step 1: Relax access on the rail helpers so other files can call them**

In `App/CommandCenterPanes.swift`, change these four declarations from `private func` to `func` (remove the `private` keyword only — leave the bodies unchanged):
- `private func speakersRailSection()` (line ~74) → `func speakersRailSection()`
- `private func railSection<Content: View>(...)` (line ~87) → `func railSection<Content: View>(...)`
- `private func railRoleName(_ role: CopilotRole) -> String` (line ~96) → `func railRoleName(_ role: CopilotRole) -> String`
- `private func languageBinding(session:)` (line ~318) → `func languageBinding(session:)`
- `private func presetBinding(session:)` (line ~331) → `func presetBinding(session:)`

Also change the three session-stat computed properties from `private var` to `var` (lines ~105–108):
- `private var youCount: Int` → `var youCount: Int`
- `private var othersCount: Int` → `var othersCount: Int`
- `private var approxTokens: Int` → `var approxTokens: Int`

- [ ] **Step 2: Create the Configure popover**

Create `App/ConfigurePanel.swift`:

```swift
import SwiftUI
import ListenToMeCore

// MARK: - Configure popover
//
// The slim cockpit top bar keeps only Listen + timer + preset visible; everything that used to live
// in the left status rail (language, proactive, per-role models, references, calendar, identify
// speakers, session stats) is one ⚙ click away here. Reuses the same `railSection`/`modelPicker`
// helpers as the old rail so behavior (and the onChange side effects in the bindings) is identical.

extension MeetingView {
    func configurePopover(session: MeetingSession) -> some View {
        @Bindable var session = session
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                railSection("Engine") {
                    Text(CommandCenterLabels.engine(ProviderSettings.transcriptionEngine))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                    Picker("Language", selection: languageBinding(session: session)) {
                        ForEach(Self.languageOptions, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("Transcription language — applies the next time you press Listen")
                }

                railSection("Proactive") {
                    Toggle("Proactive replies", isOn: $session.proactiveEnabled)
                        .controlSize(.small).labelsHidden()
                        .toggleStyle(.switch)
                        .help("Let Quick/Listener react automatically as the conversation flows")
                }

                railSection("Models") {
                    ForEach(CopilotRole.allCases, id: \.self) { role in
                        modelPicker(role: role, session: session, label: railRoleName(role))
                    }
                }

                railSection("References") {
                    Button { loadFromCalendar(session: session) } label: {
                        Label("Load from Calendar", systemImage: "calendar")
                    }
                    .controlSize(.small)
                    .help("Fill Context notes from your current or next calendar meeting")
                    referenceFilesRow(session: session)
                }

                if ProviderSettings.speakerDiarizationEnabled { speakersRailSection() }

                railSection("Session") {
                    StatRow(key: "turns", value: "\(store.utterances.count)")
                    StatRow(key: "you / others", value: "\(youCount) / \(othersCount)")
                    StatRow(key: "~tok", value: "\(approxTokens)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 320, height: 440)
    }
}
```

- [ ] **Step 3: Add the `showConfigure` state**

In `App/MeetingView.swift`, add a state property next to the other sheet/popover flags (after `@State private var showSearch = false`, line ~17):

```swift
    @State private var showConfigure = false
```

- [ ] **Step 4: Replace `topControlBar` with `slimTopBar`**

In `App/MeetingView.swift`, replace the entire `topControlBar(session:showPermissions:)` function (lines ~265–308, the doc comment above it too) with:

```swift
    // MARK: - Slim top bar (cockpit)

    /// The cockpit's slim control strip. Always visible: Listen/Stop + elapsed timer + the current
    /// preset. A single ⚙ Configure popover holds the deeper controls (language / proactive / models /
    /// references / calendar / identify speakers / stats). The familiar icon actions (refresh-models,
    /// import, export, copy, search, permissions, settings) stay on the right so nothing is lost.
    private func slimTopBar(session: MeetingSession, showPermissions: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Button(wantsCapture ? "Stop" : "Listen") { toggleCapture(session: session) }
                .buttonStyle(.borderedProminent)
                .disabled(session.isTranscribingFile)
            if session.isRunning {
                RecordingIndicator()
                Text(elapsedLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
            }
            if session.isTranscribingFile {
                ProgressView().controlSize(.small)
                Text("Transcribing…").foregroundStyle(Theme.ink2)
            }

            Divider().frame(height: 18)

            Picker("Preset", selection: presetBinding(session: session)) {
                ForEach(PresetCatalog.all) { Text($0.name).tag($0.id) }
            }
            .labelsHidden().controlSize(.small).fixedSize()
            .help("Use-case preset — fills Context notes and tailors the AI panes")

            Button { showConfigure = true } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
            }
            .help("Models, language, proactive, references, speakers…")
            .popover(isPresented: $showConfigure, arrowEdge: .bottom) {
                configurePopover(session: session)
            }

            Spacer()

            Button { Task { await reloadModels() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh installed Ollama models")
            Button { importAudioFile(session: session) } label: { Image(systemName: "waveform") }
                .help("Import an audio file and transcribe it")
                .disabled(wantsCapture || session.isTranscribingFile)
            Menu {
                Button("Full transcript (Markdown)…") { exportSession() }
                Button("Recap (Markdown)…") { exportRecap() }
                Button("PDF…") { exportPDF() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .help("Export the session as Markdown or PDF")
            Button { copySessionMarkdown() } label: { Image(systemName: "list.clipboard") }
                .help("Copy the transcript + AI notes as Markdown")
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .help("Search past meetings")
            Button { showPermissions.wrappedValue = true } label: { Image(systemName: "lock.shield") }
                .help("Microphone / system-audio permissions")
            Button { openSettings($showSettings) } label: { Image(systemName: "gearshape") }
                .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.windowBackground)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
```

- [ ] **Step 5: Point `body` at `slimTopBar`**

In `App/MeetingView.swift` `body`, change the first child of the outer `VStack` (line ~182) from:

```swift
            topControlBar(session: session, showPermissions: $showPermissions)
```
to:
```swift
            slimTopBar(session: session, showPermissions: $showPermissions)
```

(Leave the rest of `body` — the `HSplitView { statusRail; transcriptColumn; copilotColumn }` and footer — unchanged for now; Task 3 recomposes it.)

- [ ] **Step 6: Build to verify it compiles**

Run: `make build`
Expected: builds cleanly.

- [ ] **Step 7: Visual check**

Run: `make run`
Expected: the top bar now shows Listen + a **preset dropdown** + a **⚙ Configure** button + the icon row. Clicking **Configure** opens a popover containing Engine/Language, Proactive, Models, References (calendar + reference files), Speakers (if enabled), and Session stats. Changing language/models/proactive there behaves exactly as the old rail did. The old left rail is still present (duplicate controls) — expected at this step.

- [ ] **Step 8: Commit**

```bash
git add App/ConfigurePanel.swift App/CommandCenterPanes.swift App/MeetingView.swift
git commit -m "feat(ui): slim top bar with a Configure popover holding the rail controls"
```

---

### Task 3: Recompose the cockpit layout

Switch `MeetingView.body` to the cockpit grid: drop the left `statusRail` (its controls now live in the Configure popover) and the right `copilotColumn`; lay out **transcript (left) · Listener center · Quick (right)** in an `HSplitView`, with the **Deep** answer as a full-width **bottom** strip via an outer `VSplitView`. Trim the transcript's input zone to just the Context-notes field (calendar + references moved to Configure in Task 2). Panels are unstyled here (default backgrounds); Glass-HUD styling lands in Task 4.

**Files:**
- Modify: `App/MeetingView.swift` (`body` inner layout)
- Modify: `App/CommandCenterPanes.swift` (delete `statusRail`; add `listenerCenter`, `quickColumn`, `deepStrip`; trim `transcriptInputZone`; re-width `transcriptColumn`; keep `listenerBox`/`quickBox`/`deepBox` as the inner `RoleBox` builders)

**Interfaces:**
- Consumes: `MeetingView.transcriptColumn(session:notes:)`, `.listenerBox(session:)`, `.quickBox(session:)`, `.deepBox(session:)` (existing private `RoleBox` builders).
- Produces (used by Task 4): `func listenerCenter(session:) -> some View`, `func quickColumn(session:) -> some View`, `func deepStrip(session:) -> some View`.

- [ ] **Step 1: Recompose `body`'s inner layout**

In `App/MeetingView.swift` `body`, replace the `HSplitView { ... }.frame(maxHeight: .infinity)` block (lines ~191–198) with:

```swift
            // Cockpit grid: transcript (left) · live Listener (center) · Quick (right), with the Deep
            // answer as a full-width bottom strip. Outer VSplitView lets the user resize the Deep
            // height; the inner HSplitView keeps the three columns horizontally draggable (PR #50).
            VSplitView {
                HSplitView {
                    transcriptColumn(session: session, notes: $session.notes)
                    listenerCenter(session: session)
                    quickColumn(session: session)
                }
                .frame(maxHeight: .infinity)
                deepStrip(session: session)
            }
            .frame(maxHeight: .infinity)
```

- [ ] **Step 2: Delete `statusRail` and re-width / glass `transcriptColumn`**

In `App/CommandCenterPanes.swift`, **delete** the entire `statusRail(session:)` function (lines ~14–66). Leave `speakersRailSection`, `railSection`, `railRoleName`, the stat helpers, `modelPicker`, `languageBinding`, `presetBinding` in place — they're now used by the Configure popover.

Then change `transcriptColumn`'s outer frame + background (lines ~139–141) so it sits on the **left** as a narrower column with the glass treatment. Replace:

```swift
        .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity)
        .background(Theme.cardBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }
```
with:
```swift
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
        .background(Theme.cardBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }
```

- [ ] **Step 3: Trim `transcriptInputZone` to notes-only**

In `App/CommandCenterPanes.swift`, replace the `transcriptInputZone(session:notes:)` body (lines ~201–216) — the calendar button and `referenceFilesRow` now live in the Configure popover — with:

```swift
    private func transcriptInputZone(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Context notes (injected into prompts)", text: notes, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(Theme.cardBackground2)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }
```

- [ ] **Step 4: Delete `copilotColumn`; add the center / right / bottom builders**

In `App/CommandCenterPanes.swift`, **delete** the `copilotColumn(session:)` function (lines ~220–243). Keep `listenerBox`, `quickBox`, and `deepBox` (the `RoleBox` builders) exactly as they are. Immediately after `deepBox` (line ~290), add the three cockpit panes:

```swift

    // MARK: Cockpit panes (center Listener · right Quick · bottom Deep)

    /// The live center pane — situational awareness. The prominent "where are we right now"
    /// instrument; gets the accent ring so it reads as the cockpit's focal point.
    func listenerCenter(session: MeetingSession) -> some View {
        listenerBox(session: session)
            .frame(minWidth: 360, idealWidth: 460, maxWidth: .infinity)
    }

    /// The right Quick-reply column.
    func quickColumn(session: MeetingSession) -> some View {
        quickBox(session: session)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 440)
    }

    /// The full-width bottom strip: the on-request Deep answer.
    func deepStrip(session: MeetingSession) -> some View {
        deepBox(session: session)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 90, idealHeight: 150)
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `make build`
Expected: builds cleanly. (If the compiler flags `statusRail`/`copilotColumn` as still-referenced, you missed a call site in `body` — fix per Step 1.)

- [ ] **Step 6: Visual check**

Run: `make run`
Expected: the window now reads as a cockpit — **Transcript on the left**, **Listener in the center**, **Quick on the right**, and a **Deep** strip across the bottom (drag the horizontal divider above Deep to resize it; drag the vertical dividers to resize the three columns). No left rail. All controls still reachable via ⚙ Configure. Transcript's bottom zone now shows only the Context-notes field.

- [ ] **Step 7: Commit**

```bash
git add App/MeetingView.swift App/CommandCenterPanes.swift
git commit -m "feat(ui): recompose main window into the cockpit grid"
```

---

### Task 4: Apply the Glass-HUD visual style

Dress the cockpit in the "Glass HUD" look: a subtle dark gradient window background, glassy translucent panels with glowing indigo strokes, and an accent **ring** around the live center Listener pane. This is where "dark spaceship / instrument cluster" replaces the flat cards.

**Files:**
- Modify: `App/Theme.swift` (add a `windowGradient`)
- Modify: `App/MeetingView.swift` (apply `windowGradient` behind `body`)
- Modify: `App/CommandCenterPanes.swift` (apply `.hudPanel(ring:)` to the cockpit panes; glass-tint the transcript column)

**Interfaces:**
- Consumes: `View.hudPanel(ring:padding:)` and `Theme.glassStroke` (Task 1); `Theme.windowGradient` (this task).
- Produces: `Theme.windowGradient: LinearGradient`.

- [ ] **Step 1: Add a window gradient token**

In `App/Theme.swift`, in the `// MARK: Glass HUD` section (after `glassStrokeStrong`, from Task 1), add:

```swift

    /// Subtle top-to-bottom depth behind the cockpit panels (deep spaceship backdrop).
    static let windowGradient = LinearGradient(
        colors: [
            dynamic(light: nsColor(0.973, 0.969, 0.988), dark: nsColor(0.055, 0.063, 0.110)),
            dynamic(light: nsColor(0.945, 0.941, 0.969), dark: nsColor(0.086, 0.094, 0.157))
        ],
        startPoint: .top, endPoint: .bottom)
```

- [ ] **Step 2: Paint the window gradient behind `body`**

In `App/MeetingView.swift` `body`, change the root `.background(Theme.windowBackground)` (line ~201) to:

```swift
        .background(Theme.windowGradient)
```

- [ ] **Step 3: Glass the three AI panes**

In `App/CommandCenterPanes.swift`, update the three cockpit builders from Task 3 so each panel gets HUD chrome. The center gets the **ring**; add outer padding so the panels float over the gradient. Replace the `listenerCenter`/`quickColumn`/`deepStrip` bodies with:

```swift
    func listenerCenter(session: MeetingSession) -> some View {
        listenerBox(session: session)
            .hudPanel(ring: true, padding: 4)
            .padding(6)
            .frame(minWidth: 360, idealWidth: 460, maxWidth: .infinity)
    }

    func quickColumn(session: MeetingSession) -> some View {
        quickBox(session: session)
            .hudPanel(padding: 4)
            .padding(6)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 440)
    }

    func deepStrip(session: MeetingSession) -> some View {
        deepBox(session: session)
            .hudPanel(padding: 4)
            .padding(6)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 90, idealHeight: 150)
    }
```

- [ ] **Step 4: Glass-tint the transcript column**

In `App/CommandCenterPanes.swift`, in `transcriptColumn`, change its solid background to the translucent glass fill so the left column matches the HUD. Replace (the lines edited in Task 3 Step 2):

```swift
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
        .background(Theme.cardBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }
```
with:
```swift
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
        .background(.ultraThinMaterial)
        .background(Theme.glassPanelFill)
        .overlay(Rectangle().fill(Theme.glassStroke).frame(width: 1), alignment: .trailing)
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `make build`
Expected: builds cleanly.

- [ ] **Step 6: Visual check**

Run: `make run`
Expected: a dark, glassy cockpit — panels are translucent with a faint indigo glowing edge over a subtle gradient backdrop; the **center Listener** pane stands out with a brighter accent ring/glow. Resizing still works. Switch to light appearance in Settings → panels stay legible (glass resolves to a light tint). Tune the `padding`/`radius`/opacity values in this task if the glow is too strong or too faint.

- [ ] **Step 7: Commit**

```bash
git add App/Theme.swift App/MeetingView.swift App/CommandCenterPanes.swift
git commit -m "feat(ui): Glass-HUD styling — glass panels, gradient backdrop, center accent ring"
```

---

### Task 5: Update docs and run the full check

Bring the manual smoke-test doc in line with the new cockpit layout and run the full automated check.

**Files:**
- Modify: `docs/manual-smoke-test.md` (layout description in steps 1, 3, 8–9)

**Interfaces:** none (docs + verification only).

- [ ] **Step 1: Update the smoke-test layout description**

In `docs/manual-smoke-test.md`, replace step 1 (currently: "the window opens with **four panes**: **Transcript** (left) and **Listener**, **Quick**, **Deep** (right).") with:

```markdown
1. `make run` — the window opens as a **cockpit**: **Transcript** (left), the live **Listener**
   (center, accent-ringed), **Quick** (right), and a full-width **Deep** strip along the bottom.
   The slim top bar shows **Listen**, the elapsed timer, the **preset** dropdown, and a ⚙
   **Configure** popover (language, per-pane models, proactive, references, calendar, identify
   speakers, session stats).
```

In step 3, replace the sentence about per-pane model dropdowns living "In each AI pane's header" — model pickers now live in the **Configure** popover. Update step 3's first sentence to:

```markdown
3. Open the ⚙ **Configure** popover and confirm each role's **model dropdown** (listener / quick /
   deep) is populated with your installed Ollama models. Set different models per role if you like
   (e.g. a fast model for **Quick**, a heavier one for **Deep**). The toolbar **↻** button re-scans
   models.
```

(Steps 8–9 still describe the Listener/Deep panes correctly — only confirm the pane positions read "center" / "bottom strip" if you reword; no functional change.)

- [ ] **Step 2: Run the full automated check**

Run: `make e2e`
Expected: passes (builds the app, resolves the app-bundle path, runs the `OllamaProvider` contract test). This is the same gate `make pre-push` uses.

- [ ] **Step 3: Commit**

```bash
git add docs/manual-smoke-test.md
git commit -m "docs: update smoke test for the cockpit layout"
```

---

## Self-Review

**Spec coverage (against the locked brainstorm decisions):**
- *Cockpit layout — controls top · transcript left · Listener center · quick right · deep bottom* → Task 3 (`body` VSplitView/HSplitView recompose; `listenerCenter`/`quickColumn`/`deepStrip`). ✓
- *Center = Situational awareness (the live Listener: rolling summary + open items)* → `listenerCenter` wraps the existing `listenerBox` bound to `session.listenerSummary`; given the accent ring as the focal instrument (Tasks 3–4). ✓
- *Style = Glass HUD (dark, glowing panels, accent ring around the live center)* → Task 1 (tokens + `.hudPanel`) and Task 4 (apply ring to center, glass panels, gradient backdrop). ✓
- *Top bar = Slim + single ⚙ Configure popover holding models/language/proactive/references/calendar/identify-speakers* → Task 2 (`slimTopBar` + `configurePopover`). ✓
- *Preset stays visible in the slim bar* → Task 2 Step 4 (inline preset Picker). ✓
- *Lose no existing functionality* → every icon action preserved in `slimTopBar`; rail controls relocated, not removed (Task 2). ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N" — every code step shows the literal edit. ✓

**Type/name consistency:** `Theme.glassPanelFill`/`glassStroke`/`glassStrokeStrong`/`windowGradient`, `HudPanel`, `.hudPanel(ring:padding:)` are defined in Tasks 1/4 and consumed by the same names in Tasks 2–4. `configurePopover(session:)`, `slimTopBar(session:showPermissions:)`, `showConfigure`, `listenerCenter`/`quickColumn`/`deepStrip` are defined and called with matching signatures. Helpers made non-private in Task 2 Step 1 are exactly those the popover/slim-bar call from other files (`railSection`, `railRoleName`, `speakersRailSection`, `languageBinding`, `presetBinding`, `youCount`/`othersCount`/`approxTokens`). ✓

**Known follow-ups (out of scope, fine to defer):** the brainstorm left "do panels collapse/resize?" open — this plan keeps them resizable (HSplitView/VSplitView) but not collapsible. The `CommandCenterFooter` keyboard hints and `RailRecStatus`/`RailLabel` monospaced styling are untouched (still fit the HUD); revisit only if a later polish pass wants them.
