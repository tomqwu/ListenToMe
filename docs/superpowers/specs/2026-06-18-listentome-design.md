# ListenToMe — Design Spec

**Date:** 2026-06-18
**Status:** Approved-for-planning (pending final user review)

## 1. Summary

ListenToMe is a **native macOS app** (SwiftUI, macOS 26) for **personal use** that listens to a
meeting in real time — both your own voice (mic) and remote participants (system audio) — transcribes
it on-device, keeps a rolling summary, and produces useful responses on demand *and* proactively. Models
are user-configurable (Ollama, Claude, OpenAI, DeepSeek) via BYOK. Everything runs locally; nothing is
sent anywhere except the LLM provider you explicitly choose.

**Positioning:** the transparent, on-device, BYOK inverse of Cluely. Not covert, not cloud-hoarded,
not subscription-locked. Closest analog is the open-source `Natively` ($25/mo equivalent), which we
replace with a single-user local build costing only your own tokens (or $0 with Ollama).

## 2. Goals & Non-Goals

**Goals**
- Real-time transcription of mic + system audio with speaker labels ("You" / "Others").
- A 3-pane live GUI: Transcript, rolling Summary, live Response.
- On-demand responses (global hotkey) and proactive responses (auto-detected questions).
- Swappable transcription engine (Apple SpeechAnalyzer or WhisperKit) chosen in Settings.
- Swappable LLM provider (Ollama default; Claude, OpenAI, DeepSeek added) with keys in Keychain.
- Privacy-first: all audio/transcription local; only prompt text leaves the machine, only to the
  chosen provider.

**Non-Goals (YAGNI)**
- No App Store distribution (personal sideload via Xcode / Apple Developer cert).
- No cloud backend, accounts, billing, or multi-user.
- No iOS/iPad app (Mac only; revisit later if wanted).
- No covert/"stealth" mode — a visible recording indicator is always shown.
- No speaker diarization beyond source-based labeling (mic vs system) in v1.
- No meeting-platform bot integrations (Zoom/Teams APIs).

## 3. Architecture

Single-process SwiftUI app. Modules communicate through well-defined Swift protocols and an
`@Observable` shared state object. Audio and ASR run off the main actor; UI observes published state.

```
 ┌────────────┐   PCM   ┌─────────────┐ segments ┌──────────────────┐
 │AudioCapture│────────▶│ Transcriber │─────────▶│ ConversationStore │
 │ mic+system │         │ (protocol)  │          │ (rolling buffer)  │
 └────────────┘         └─────────────┘          └────────┬─────────┘
                                                          │ reads
                          ┌───────────────┐               │
                          │ ContextEngine │◀──────────────┤
                          │ (segment +    │               │
                          │  question     │               │
                          │  detection)   │               │
                          └──────┬────────┘               │
            on-demand hotkey ────┤                         │
            or proactive trigger │                         │
                                 ▼                         ▼
                        ┌────────────────┐        ┌──────────────┐
                        │ ResponseEngine │        │ SummaryEngine │
                        └───────┬────────┘        └──────┬───────┘
                                │  prompt                │ prompt
                                ▼                        ▼
                          ┌───────────────────────────────┐
                          │ ModelRouter (LLMProvider impls)│
                          │ Ollama | Claude | OpenAI | DS  │
                          └───────────────────────────────┘
                                          │ streamed tokens
                                          ▼
                            ┌──────────────────────────┐
                            │  SwiftUI 3-pane window    │
                            │ Transcript|Summary|Response│
                            └──────────────────────────┘
```

## 4. Components

Each component is one focused unit with a clear interface. Names below are the canonical symbols used
throughout the plan.

### 4.1 AudioCapture
- **Responsibility:** capture mic + system audio, tag each buffer with a `SpeakerSource` (`.you` /
  `.others`), deliver PCM buffers to the Transcriber.
- **Mic:** `AVAudioEngine` input node tap.
- **System audio:** `ScreenCaptureKit` `SCStream` audio capture (macOS 13+; available on macOS 26).
- **Interface:**
  ```swift
  enum SpeakerSource { case you, others }
  struct AudioChunk { let pcm: AVAudioPCMBuffer; let source: SpeakerSource; let timestamp: TimeInterval }
  protocol AudioCapturing {
      var chunks: AsyncStream<AudioChunk> { get }
      func start() async throws
      func stop()
  }
  ```
- **Depends on:** macOS audio entitlements (microphone usage + screen/system-audio recording consent).

### 4.2 Transcriber (protocol, two implementations)
- **Responsibility:** turn `AudioChunk`s into `TranscriptSegment`s (partial + finalized), preserving
  source label and timestamps.
- **Implementations:** `SpeechAnalyzerTranscriber` (Apple, macOS 26, on-device, no time limit) and
  `WhisperKitTranscriber` (Core ML model). Default chosen in Settings.
- **Interface:**
  ```swift
  struct TranscriptSegment {
      let id: UUID; let source: SpeakerSource
      let text: String; let isFinal: Bool
      let start: TimeInterval; let end: TimeInterval
  }
  protocol Transcribing {
      var segments: AsyncStream<TranscriptSegment> { get }
      func feed(_ chunk: AudioChunk) async
      func finish() async
  }
  ```

### 4.3 ConversationStore
- **Responsibility:** single source of truth — an ordered, finalized utterance log plus the current
  partial. `@Observable`; the UI and engines read from it.
- **Interface:**
  ```swift
  @Observable final class ConversationStore {
      private(set) var utterances: [TranscriptSegment]   // finalized only
      private(set) var partial: TranscriptSegment?
      func apply(_ segment: TranscriptSegment)
      func recentContext(maxTokensApprox: Int) -> [TranscriptSegment]
  }
  ```

### 4.4 ContextEngine
- **Responsibility:** (a) assemble the prompt context window from recent utterances; (b) detect when
  remote speech contains a question / request for input, to fire proactive responses.
- **Question detection (v1):** lightweight heuristic — finalized `.others` utterance ending in `?`,
  or matching interrogative/imperative cue patterns ("what do you think", "can you", "any thoughts").
  Debounced so it fires at most once per N seconds. Kept deliberately simple; swappable later.
- **Interface:**
  ```swift
  struct PromptContext { let messages: [TranscriptSegment]; let rollingSummary: String? }
  protocol ContextProviding {
      func buildContext(from store: ConversationStore) -> PromptContext
      var proactiveTriggers: AsyncStream<PromptContext> { get }  // emits when input likely wanted
  }
  ```

### 4.5 ModelRouter & LLMProvider
- **Responsibility:** one streaming interface over all providers; route to the user-selected provider;
  read keys from Keychain.
- **Default:** `OllamaProvider` (`http://localhost:11434`, no key). Phase 2 adds `ClaudeProvider`,
  `OpenAIProvider`, `DeepSeekProvider`.
- **Interface:**
  ```swift
  struct LLMRequest { let system: String; let context: PromptContext; let userPrompt: String? }
  protocol LLMProvider {
      var id: String { get }
      func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>  // token deltas
  }
  final class ModelRouter {
      func setActive(_ providerID: String)
      func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
  }
  ```
- **Keys:** `KeychainStore` wrapper (`set/get/delete` by provider id). Ollama needs none.

### 4.6 ResponseEngine
- **Responsibility:** turn a trigger (hotkey or proactive) into a streamed response in the Response pane.
- **System prompt:** "You are a real-time meeting assistant. Given the transcript so far, provide a
  concise, useful response the listener can act on. If a question was asked, answer it directly."
- **Interface:**
  ```swift
  @Observable final class ResponseEngine {
      private(set) var currentResponse: String
      private(set) var isStreaming: Bool
      func respondOnDemand() async        // hotkey
      func respondTo(_ context: PromptContext) async  // proactive
  }
  ```

### 4.7 SummaryEngine
- **Responsibility:** maintain a rolling summary, refreshed every N finalized utterances or T seconds,
  via the same ModelRouter.
- **Interface:**
  ```swift
  @Observable final class SummaryEngine {
      private(set) var summary: String
      func refreshIfNeeded(from store: ConversationStore) async
  }
  ```

### 4.8 UI (SwiftUI)
- **MainWindow:** 3 panes — `TranscriptPane` (live, source-colored), `SummaryPane`, `ResponsePane`
  (streaming) — in a resizable `HSplitView`.
- **Controls:** Start/Stop with a prominent **recording indicator**; global **hotkey** ("answer now");
  provider/engine pickers in the toolbar.
- **SettingsWindow:** transcription engine selector, model provider + model name, API keys (Keychain),
  audio source toggles (mic / system / both), proactive on/off + sensitivity.

## 5. Data Flow

1. `AudioCapture` emits `AudioChunk`s (mic = `.you`, system = `.others`).
2. `Transcriber` streams `TranscriptSegment`s; `ConversationStore.apply` updates partial/finalized.
3. UI observes `ConversationStore` → Transcript pane updates live.
4. On each finalized utterance: `SummaryEngine.refreshIfNeeded` and `ContextEngine` question-check run.
5. Trigger (hotkey → `respondOnDemand`, or proactive `PromptContext`) → `ModelRouter.stream` → tokens
   appended to `ResponseEngine.currentResponse` → Response pane updates live.

## 6. Error Handling

- **No mic / system-audio permission:** show a clear banner with a button to open System Settings;
  never crash; allow running with whichever source is granted.
- **Transcriber failure:** surface a non-blocking error in the Transcript pane header; keep audio
  capture alive; allow engine switch in Settings.
- **Provider unreachable (Ollama down / bad key / network):** Response pane shows the error inline with
  a retry affordance; does not interrupt transcription or summary.
- **Streaming interruption:** partial response is kept and marked incomplete; retry re-streams.
- **Backpressure:** if ASR lags, audio chunks are dropped oldest-first with a visible "dropping audio"
  indicator rather than unbounded memory growth.

## 7. Testing Strategy

- **Unit (TDD, no real audio/network):**
  - `ConversationStore`: apply partial then final; `recentContext` token budgeting.
  - `ContextEngine` question detection: positive/negative cue cases; debounce.
  - `ModelRouter`: routing + SSE/stream parsing against a `MockLLMProvider` and recorded fixtures.
  - `KeychainStore`: set/get/delete round-trip.
  - Each `LLMProvider`: request encoding + delta parsing against recorded fixtures (no live calls).
- **Integration:** feed a canned `AsyncStream<AudioChunk>` of fixture PCM/text through
  Transcriber→Store→ContextEngine and assert transcript + trigger behavior.
- **Manual/UI:** scripted run-through (start capture, speak, ask a question, hit hotkey) documented in
  a test-plan checklist; screenshots for UI changes.
- All real-audio and real-provider paths are isolated behind protocols so the core logic is fully
  testable without hardware or network.

## 8. Phasing

- **Phase 1 — MVP (end-to-end usable):** AudioCapture (mic + system, "both"), one default Transcriber
  wired (SpeechAnalyzer) but behind the swappable protocol, ConversationStore, Transcript pane, Ollama
  provider, on-demand hotkey response, basic rolling summary.
- **Phase 2 — Config & providers:** Settings UI; WhisperKit engine; Claude/OpenAI/DeepSeek providers;
  Keychain; engine/provider switching; audio-source toggles.
- **Phase 3 — Proactive & persistence:** ContextEngine proactive triggers + sensitivity control;
  session save/load; transcript export.

(User selected "both audio sources" and "both triggers" as equal priorities; both are in scope. Phasing
sequences delivery so a working tool exists after Phase 1, with proactive triggers landing in Phase 3.)

## 9. Tech Stack & Dev Practices

- **Language/UI:** Swift 6, SwiftUI, Swift Concurrency (actors/`AsyncStream`), `@Observable`.
- **Frameworks:** AVFoundation, ScreenCaptureKit, Speech (SpeechAnalyzer), WhisperKit (SPM), Security
  (Keychain).
- **Build/test:** Swift Package Manager + Xcode project; `swift test` for logic packages; SwiftLint
  for lint/format.
- **Dev practices (adapted from `aml_open_framework` CLAUDE.md):**
  - TDD: failing test → minimal impl → green → commit, in small steps.
  - Surgical changes; match existing patterns; every line traces to the task.
  - A `make pre-push` umbrella (lint + unit tests + build) as the CI-equivalent gate.
  - **Codex review before every commit** (`/codex:review --base main`); do not commit while Codex
    reports blocking issues.
  - Docs updated alongside features (README + this spec + any how-to).
- **Distribution:** local Xcode build / sideload; optional $99/yr Apple Developer cert for year-long
  signing. No App Store.

## 10. Lessons Applied from Natively (open-source Cluely alternative)

Adopted into this design:
- **VAD-based segmentation:** utterance boundaries and question detection use an RMS-threshold + voice
  activity detector, not a naive punctuation check. (Refines ContextEngine §4.4.)
- **Contextual action buttons:** in addition to the `⌘K` hotkey, the UI exposes *"What should I
  answer?"*, *"Recap so far"*, *"Suggest a follow-up"*. (Refines ResponseEngine §4.6 / UI §4.8.)
- **Anti-chatbot system prompt:** concise, conversational, no robotic preambles or lectures — their
  highest-leverage quality lever. (Refines ResponseEngine system prompt §4.6.)
- **Free-form notes/context injection:** a small notes field whose text is injected into every prompt.
- **Rolling context window + separate dual-channel streams:** already in the design.

Deliberately NOT adopted for the MVP: local RAG/SQLite-vec memory, screenshot/slide OCR, multiple
persona modes, stealth/process-masquerading, multi-key API pools, calendar/task sync.

## 11. Focused MVP Scope ("listen to meetings, get real-time suggestions")

The first deliverable is intentionally narrow. **In scope:**
1. Dual-channel `AudioCapture` (mic = `You`, system = `Others`).
2. VAD utterance segmentation feeding the default on-device `Transcriber` (SpeechAnalyzer), behind the
   swappable protocol.
3. `ConversationStore` + live **Transcript pane** (source-labeled, partial + final).
4. **Suggestion pane** streaming from `ModelRouter` → `OllamaProvider` (default, local, no key).
5. Triggers — **both**:
   - On-demand: global hotkey `⌘K` and three action buttons (*What should I answer?*, *Recap so far*,
     *Suggest a follow-up*).
   - Proactive: `ContextEngine` fires when an `Others` utterance is detected as a question (VAD +
     heuristic), debounced, with an on/off toggle.
6. Concise anti-preamble system prompt + optional free-form notes injected into prompts.
7. Visible recording indicator (transparent, never stealth).

**Out of MVP scope (later phases):** WhisperKit engine; Claude/OpenAI/DeepSeek providers; Settings
window beyond a minimal toggle bar; session persistence/export; rolling auto-summary as a constant pane
(replaced by the on-demand *Recap* action for the MVP); everything listed as not-adopted in §10.

## 12. Open Risks

- **System-audio capture UX:** ScreenCaptureKit audio requires screen-recording consent; verify the
  one-time grant flow is acceptable. Fallback: virtual audio device (BlackHole) if needed.
- **Proactive precision:** heuristic question-detection will have false positives/negatives; mitigated
  by debounce + on/off toggle + sensitivity, and by deferring to Phase 3.
- **Local-model latency:** Ollama response speed depends on the Mac and model size; acceptable for
  personal use, and Claude/OpenAI remain available for speed.
