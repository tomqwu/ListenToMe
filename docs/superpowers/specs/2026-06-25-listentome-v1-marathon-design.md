# ListenToMe v1.0 Marathon — Design

**Goal:** Take ListenToMe from a working personal tool to a polished, publicly-released v1.0:
finish the feature backlog, add use-case preset contexts, give it a real visual identity, research
the competition, overhaul the docs, and ship a signed + notarized GitHub release.

**Audience decision:** **Public, open-source, notarized.** The app will be distributed as a
signed + notarized `.dmg` on GitHub Releases so anyone on macOS 26 can download and open it without
Gatekeeper friction. Notarization runs with the maintainer's Apple Developer credentials.

**Tech stack (unchanged):** Swift 6 / SwiftUI / `@Observable`, `ListenToMeCore` SwiftPM package
(pure, 95%-covered logic) + `App/` (macOS glue), XcodeGen, SwiftLint, Codex review before every
commit, GitHub Actions CI (lint + tests + 95% coverage gate).

**Execution model:** Each phase gets its own implementation plan (writing-plans) and is executed via
subagent-driven-development — one PR per task, Codex-reviewed before commit, CI-gated. Pure logic
lives in `ListenToMeCore` with tests; `App/`-only changes are verified by build + lint + manual notes.

---

## Architecture additions

Two new core concepts, both pure and testable, plus app-layer glue:

- **`PresetCatalog` / `Preset` (Core):** a static catalog of use-case presets. Each `Preset` has an
  `id`, display `name`, `notesTemplate` (seed text for Context notes), `personaGuidance` (a short
  instruction injected into the AI panes' system prompts to set role/tone/focus), and optional
  `modelHints` (preferred capability per role, advisory). Selecting a preset fills the notes field
  and sets `MeetingSession.personaGuidance`.
- **`PromptContext.personaGuidance` (Core):** a new optional field, appended to the Quick/Deep/
  Listener system prompts (like `responseLanguage`) so answers adopt the preset's role/focus.
- **Onboarding + visual identity (App):** a first-run flow and a small design-token layer
  (accent color, spacing, typography) applied across the panes.

These follow the existing `notes` / `summary` / `responseLanguage` / `references` pattern threaded
through `ContextEngine.buildContext` → `PromptBuilder`, so they are unit-testable end to end.

---

## Phase 0 — Competition research

**Deliverable:** `docs/competition-analysis.md`.

- Survey on-device/cloud meeting copilots and adjacent tools: Granola, Otter.ai, Fireflies,
  Fathom, Fellow, tl;dv, Cluely / interview-assist tools, Natively, Superpowered, MacWhisper.
- For each: platform, on-device vs cloud, privacy posture, transcription engine, AI features,
  multi-model support, pricing, and use-case focus.
- Output a comparison table and a positioning statement for ListenToMe: **on-device & private,
  bring-your-own-model (Ollama local + cloud), multi-pane multi-model, multi-purpose via presets,
  free & open-source.**
- Findings feed the Phase 1 preset list and the Phase 4 README positioning.

**Acceptance:** doc committed with ≥8 competitors, a comparison table, and a positioning section.

---

## Phase 1 — Preset context system

**Files:** Create `Sources/ListenToMeCore/PresetCatalog.swift`; modify `Prompt.swift`,
`ContextEngine.swift`, `MeetingSession.swift`; `App/` UI (preset picker in the transcript header);
tests `Tests/ListenToMeCoreTests/PresetCatalogTests.swift` + prompt-injection tests.

**Presets (initial set):** General meeting · 1:1 · Standup · Sales call · Job interview
(candidate) · Job interview (interviewer) · Technical / coding interview · Lecture / study ·
Customer support · Medical consult · Legal consult · Brainstorm. Plus a **None** default.

**Behavior:** A preset picker sets the Context-notes template (editable afterward) and applies
`personaGuidance` to the AI panes. Example — *Job interview (candidate)*: notes template prompts for
role/company/JD; persona guidance tells Quick to suggest concise spoken answers in first person and
Deep to give structured STAR-method answers. Persona guidance is injected into Quick/Deep/Listener
system prompts. `modelHints` are advisory only (shown, not auto-applied, to respect pinning).

**Acceptance:** picker switches notes + guidance live; guidance reaches Quick/Deep/Listener prompts
(tested); "None" clears guidance; Core coverage stays ≥95%.

---

## Phase 2 — Feature backlog

**2a. Configurable reference budget.** Expose the `ReferenceBuilder` char budget as a Settings
value (default 16k); thread into `loadReferences`. Test the builder honors the budget.

**2b. Polish bugs.** Address any small issues surfaced during the marathon (tracked as they arise).

**2c. WhisperKit engine (the big one).** Add WhisperKit as a third `Transcribing` engine
(`App/WhisperKitTranscriber.swift`) behind the existing protocol, selectable in Settings alongside
SpeechAnalyzer / SpeechRecognizer. Enables stronger multilingual + Mandarin↔English code-switching.
Adds the WhisperKit SwiftPM dependency and on-first-use model download (surface a downloading
state). Engine selection already flows through `makeTranscriber`; this is additive.

**Acceptance:** reference budget configurable + tested; WhisperKit selectable and transcribes a
sample; existing engines unchanged; CI green. WhisperKit is additive and must not regress the
default SpeechAnalyzer path.

---

## Phase 3 — App beautification (fuller redesign)

**Files:** `App/` (design tokens, onboarding sheet, pane restyle), app icon asset
(`App/Assets.xcassets/AppIcon.appiconset` generated from a 1024px master), `project.yml`
(icon/asset catalog wiring).

- **App icon:** a stylized **ear + soundwave** mark on a rounded-square gradient, generated
  programmatically (Core Graphics/SwiftUI render script under `scripts/`) into the full iconset.
- **Visual identity:** an accent color, consistent spacing/typography tokens, card-style panes with
  clear headers, refined recording/streaming/empty states, and the model/preset/language controls
  visually grouped.
- **First-run onboarding:** a sheet on first launch — welcome → permissions (mic/speech/screen) →
  Ollama key (optional) → engine + language — replacing the bare permissions panel as the entry
  point (the 🛡️ panel remains reachable later).

**Acceptance:** icon shows in Dock/Finder; onboarding appears on first run only (persisted flag);
panes restyled cohesively; no functional regressions; build + lint clean.

---

## Phase 4 — Docs / screenshots / badges

**Files:** `README.md` (overhaul), `LICENSE` (**MIT**), `docs/` tidy, screenshots/GIF under
`docs/images/`.

- **LICENSE:** add MIT (maintainer: Tom Wu / tomqwu), referenced from README.
- **README overhaul:** hero (name + one-liner + screenshot), positioning + **comparison table**
  (from Phase 0), feature highlights with **screenshots** and a short **GIF** of a live session,
  install (download notarized .dmg + build-from-source), models/presets/languages, privacy
  statement, contributing, license.
- **Badges:** CI status, coverage, macOS 26, Swift 6, license (MIT), latest release.
- Screenshots/GIF are captured from the **beautified** app (after Phase 3).

**Acceptance:** README renders with badges + images + comparison table; LICENSE present; links valid.

---

## Phase 5 — Proper release (signed + notarized)

**Files:** `scripts/release.sh`, `Makefile` (`make release`), `project.yml` (release config),
optional `.github/workflows/release.yml`; version bump in `project.yml` (`MARKETING_VERSION` 1.0.0).

- Bump to **v1.0.0**.
- **Packaging:** archive/export a Developer ID-signed `.app`, build a `.dmg` (hdiutil or
  create-dmg), submit to Apple **notarytool**, staple the ticket.
- **Release flow:** `make release` builds → signs → notarizes → staples → produces
  `ListenToMe-1.0.0.dmg`; a `gh release create v1.0.0` step attaches it with generated notes.
- **Credentials:** notarization requires the maintainer's Apple Developer **Team ID** + an
  **app-specific password or App Store Connect API key**, supplied via environment/Keychain at
  release time (never committed). The tooling is built and documented; the actual notarize+publish
  step is run by the maintainer with their secrets.

**Acceptance:** `make release` produces a signed .dmg locally; notarization step documented and
runnable with credentials; GitHub Release v1.0.0 created with the .dmg and notes. (Notarized
artifact depends on maintainer credentials at run time.)

---

## Testing strategy

- All new **pure logic** (PresetCatalog, persona-guidance prompt injection, reference budget) lives
  in `ListenToMeCore` with unit tests; the **95% coverage gate** is held.
- `App/`-only changes (UI, onboarding, icon, WhisperKit glue, release tooling) are verified by
  build + SwiftLint + manual smoke notes (`docs/manual-smoke-test.md` updated).
- Every task: Codex review before commit, CI (lint + tests + coverage) before merge.

## Risks & dependencies

- **Notarization** needs the maintainer's Apple Developer Program membership + credentials at
  release time; Phase 5 builds the tooling but the final publish is maintainer-run.
- **WhisperKit** adds an external dependency and model downloads; it must remain additive and not
  regress the default engine. If it proves too heavy, it can ship in a v1.1 point release — but the
  current decision is to include it in v1.0.
- **Screenshots/GIF** depend on Phase 3 being complete (sequencing enforced).

## Out of scope (v1.0)

- iOS/iPad app; Windows/Linux; cloud sync/accounts; team features; dedicated Claude/OpenAI
  providers (Ollama-only by design); cross-launch session history (export covers review/share).
