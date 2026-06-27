# Speaker Diarization (experimental first cut) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add an opt-in, on-device "Speaker breakdown" — detect how many distinct people spoke in the "Others" channel and their talk-time share — using FluidAudio (native Swift + CoreML Pyannote models).

**Architecture:** Keep `ListenToMeCore` pure (no FluidAudio dependency). An App-owned thread-safe `SpeakerAudioBuffer` accumulates the `.others` channel resampled to 16 kHz mono as it is captured; `DualChannelCapture` appends into it. On demand, an App `SpeakerDiarizer` runs FluidAudio's `OfflineDiarizerManager` over the buffer, maps its segments to Core's pure `DiarizedSegment` values, and Core's pure `SpeakerStats.summarize(_:)` aggregates per-speaker talk time. The result shows in a sheet. Default OFF, flagged experimental; quality is user-validated (cannot be validated headlessly).

**Tech Stack:** Swift 6 / SwiftUI, FluidAudio (SPM, CoreML), AVAudioConverter (resample), XcodeGen, SwiftLint (160-char lines, 350-line type_body_length).

---

### Task 1: Core pure diarization summary (TDD)

**Files:**
- Create: `Sources/ListenToMeCore/SpeakerStats.swift`
- Test: `Tests/ListenToMeCoreTests/SpeakerStatsTests.swift`

- [ ] **Step 1: Write failing tests.** `DiarizedSegment(speakerId: String, start: TimeInterval, duration: TimeInterval)`; `SpeakerStats.summarize([DiarizedSegment]) -> SpeakerSummary` where `SpeakerSummary` has `speakerCount: Int`, `totalSpeech: TimeInterval`, and `speakers: [SpeakerTalkTime]` (each `id: String`, `total: TimeInterval`, `fraction: Double`), sorted by `total` descending. Cover: empty → count 0; merges multiple segments per speaker; fractions sum to ~1.0; zero-duration segments ignored.
- [ ] **Step 2:** Run `swift test --filter SpeakerStatsTests` — expect FAIL (types undefined).
- [ ] **Step 3:** Implement the pure structs + `summarize`. No I/O, no FluidAudio. All `public`, `Sendable`, `Equatable`.
- [ ] **Step 4:** `swift test` passes; keep Core ≥95% coverage (`scripts/check-coverage.sh`).
- [ ] **Step 5:** Commit (after Codex review — see controller note).

### Task 2: App audio sink

**Files:**
- Create: `App/SpeakerAudioBuffer.swift`

- [ ] Thread-safe `final class SpeakerAudioBuffer: @unchecked Sendable` with `NSLock`. `func append(samples: [Float], sampleRate: Double)` resamples to 16 kHz mono via a cached `AVAudioConverter` and accumulates; `func reset()`; `func snapshot() -> [Float]`. Cap accumulation at ~2 hours of 16 kHz audio (115_200_000 samples); when full, stop appending and set a `truncated` flag (exposed) — never grow unbounded.

### Task 3: Wire the sink into capture

**Files:**
- Modify: `App/DualChannelCapture.swift`, `App/MeetingView.swift:75-111`

- [ ] `DualChannelCapture.init(othersSink: SpeakerAudioBuffer? = nil)`; in `emit(buffer:source:)` for `.others`, append the mono samples to the sink (sink handles resample). Default `nil` preserves existing callers/tests.
- [ ] In `MeetingView.init`, create `let othersSink = SpeakerAudioBuffer()`, store as `@State private var othersAudioSink`, and set `makeCapture: { othersSink.reset(); return DualChannelCapture(othersSink: othersSink) }` so each session starts fresh.

### Task 4: SpeakerDiarizer (FluidAudio) + dependency

**Files:**
- Modify: `project.yml` (add SPM package `https://github.com/FluidInference/FluidAudio.git` from 0.12.4, product `FluidAudio` on the App target)
- Create: `App/SpeakerDiarizer.swift`

- [ ] `actor SpeakerDiarizer` lazily creates `OfflineDiarizerManager`, calls `prepareModels()` once (models auto-download on first use), then `process(audio: [Float])` (16 kHz mono). Map each FluidAudio segment → Core `DiarizedSegment(speakerId:start:duration:)` (derive duration from start/end fields — confirm exact field names against the resolved package), return `SpeakerStats.summarize(...)`. Throw a friendly error if the buffer is shorter than ~3 s.

### Task 5: UI — experimental toggle + breakdown sheet

**Files:**
- Modify: `App/SettingsView.swift` (ProviderSettings `speakerDiarizationEnabled` Bool default false; an Appearance-style toggle "Speaker diarization (experimental)")
- Modify: `App/CommandCenterPanes.swift` (rail: when enabled, a "Speakers" section with an "Identify speakers" button)
- Create: `App/SpeakerBreakdownView.swift` (sheet: "N speakers detected", per-speaker bars with talk-time % ; loading + error + "needs more audio" states; honest "experimental · on-device" caption)

- [ ] Button runs the diarizer over `othersAudioSink.snapshot()` in a `Task`, presents the sheet. Disable while a session is running if the buffer is empty. Show a spinner during first-run model download. Keep `MeetingView` struct body ≤350 lines (put new helpers in the extension file).

### Task 6: Build + docs

- [ ] `make build` succeeds (FluidAudio resolves; first build downloads the package). CI builds Core only, unaffected.
- [ ] Mark backlog item #1 "Speaker diarization" as shipped-experimental in `docs/backlog.md`.

---

**Controller note (overrides skill default):** Per the user's standing rule, **Codex review runs before each commit**. Implementer implements + builds + runs Core tests but the controller runs `codex review --base main --scope branch`, addresses findings, then commits/pushes/opens the PR. This lands in a future tag, not the already-shipped v1.1.0. Honest framing throughout: experimental, on-device, user-validated quality.
