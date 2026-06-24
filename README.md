# ListenToMe

A personal, on-device macOS meeting copilot: it listens to your mic and the other participants'
system audio, transcribes live, and gives real-time AI help. The window has **four panes**:
**Transcript** (live, source-labeled — no model), plus three AI panes that **each have their own
selectable model** — **Listener** (rolling summary + open questions/action items), **Quick** (fast
suggestions — ⌘⇧Space, buttons, or proactively when someone asks a question), and **Deep**
(on-demand detailed/long-reasoning answer). Inference runs through Ollama: **local models stay
on-device**; if you pick an Ollama **`:cloud`** model, the transcript/prompt is sent to that cloud
model.

## Requirements
- macOS 26+
- Xcode 26+, `brew install xcodegen` (and optionally `swiftlint`, `xcbeautify`)
- [Ollama](https://ollama.com) running locally — the app auto-picks an installed model on first launch

## Build & run
```bash
make test     # run the ListenToMeCore test suite (unit + integration)
make build    # generate the Xcode project and build the app
make run      # build and launch
make pre-push # lint + tests + build (the CI-equivalent gate)
```

Optional: copy `signing.local.mk.example` to `signing.local.mk` (gitignored) and set your
code-signing identity so granted macOS permissions (mic/screen/accessibility) persist across
rebuilds (otherwise each rebuild re-asks). Find it via `security find-identity -v -p codesigning`.

## Models
Each AI pane (**Listener**, **Quick**, **Deep**) has its **own model dropdown in its header** —
pick a different model per role (e.g. a fast model for Quick, a heavier reasoning model for Deep).
The dropdowns list chat-capable models discovered from your local Ollama server
(`http://localhost:11434` via `/api/tags` + `/api/show`), including local models and Ollama-cloud
models (e.g. `deepseek-v4-flash:cloud`, which runs via your Ollama cloud sign-in). Per-role choices
persist across launches; the toolbar **↻** button re-scans installed models (e.g. after you pull a
new one). On first launch, any role whose saved model isn't installed auto-switches to one that
works — no manual config needed. **Settings** (gear icon) holds the transcription engine
(SpeechAnalyzer / SpeechRecognizer) and an optional **Ollama API key**.

**Ollama Cloud:** paste your Ollama API key (from [ollama.com](https://ollama.com)) in **Settings**
to use cloud models (e.g. `deepseek-v4-flash`, `deepseek-v4-pro`, `qwen3-coder`). With a key set, the
app routes model discovery **and** inference to `https://ollama.com` with `Authorization: Bearer
<key>`; leave it blank to use your local Ollama at `http://localhost:11434`. The key is stored in
your macOS Keychain. (Note: cloud models send the transcript/prompt to Ollama Cloud.)

## CI
GitHub Actions (`.github/workflows/ci.yml`) gates every PR to `main` on a macOS runner:
SwiftLint, the full `ListenToMeCore` test suite (unit + headless integration/e2e), and a
**coverage floor of 95%** enforced by `scripts/check-coverage.sh`. Because the app target deploys
to macOS 26 and uses ScreenCaptureKit/Speech, the **app build and GUI/audio e2e cannot run on
hosted runners** — those are verified locally via `docs/manual-smoke-test.md`.

## Local e2e (pre-push)
`make e2e` runs the checks CI can't (it needs a real Mac + Ollama): it builds the **app target**,
verifies `make run`'s app-path resolution, and runs a **real LLM contract test** against your local
Ollama through the actual `OllamaProvider`. **Model auto-selection:** `make e2e` queries
`/api/tags` and picks an installed chat model automatically (preferring local non-`:cloud` models
over cloud ones, skipping embedding-only models) — no manual `ollama pull llama3.1` needed. Override
with `LTM_E2E_MODEL=deepseek-v4-flash:cloud` (or any pulled model) to exercise a specific model.
`make e2e` preflights that Ollama is running and the chosen model is available, failing with a clear
message if not. Requires Ollama running at `localhost:11434`. The gated test is skipped by normal
`swift test`/CI. **Not covered (still manual):** mic/system-audio capture and live speech-to-text,
which need a GUI session + Speech/Screen-Recording permission grants — see
`docs/manual-smoke-test.md`.

## Permissions
On first run, grant Microphone, Speech Recognition, Screen Recording (for system audio), and
Accessibility (for the global hotkey) in System Settings → Privacy & Security.
On launch the app shows a Permissions panel (also reachable from the toolbar 🛡️) to grant these up front.

## Architecture
- `ListenToMeCore` (Swift package): all testable logic — conversation state, VAD, question
  detection, prompt building, Ollama provider, model router, context engine, `MeetingSession`.
- `App/`: macOS glue — `DualChannelCapture`, `SpeechRecognizerTranscriber`, SwiftUI UI, hotkey.

See `docs/superpowers/specs/2026-06-18-listentome-design.md` for the full design and
`docs/superpowers/plans/2026-06-18-listentome-mvp.md` for the implementation plan.

## Known limitations (MVP)
- **Transcription engine (Settings):** the default **SpeechAnalyzer** (macOS 26) transcribes both
  channels concurrently. The legacy **SpeechRecognizer** option uses one `SFSpeechRecognizer` per
  source and may hit a process-global active-recognition limit (`kAFAssistantErrorDomain 1100`) on
  some systems. SpeechAnalyzer downloads its language model on first use. Both are on-device.
- **On-device `SFSpeechRecognizer`** is the MVP engine (behind a swappable `Transcribing` protocol);
  WhisperKit / SpeechAnalyzer are planned Phase-2 engines.
- A short utterance spoken entirely within the brief recognizer-finalization gap may merge into the
  next finalized segment.

## Roadmap (post-MVP)
- **Done:** Ollama provider for both local and cloud models (key in Keychain), with **per-pane
  model selection** (curated defaults: Quick = fast/`flash`, Deep = strong/`pro`), **transcription
  language** selection, **AI response-language** selection, **Listener→Quick/Deep context sharing**,
  and **Markdown session export** (toolbar ⬆️).
- **Ollama-only by design.** Cloud already exposes GPT/DeepSeek/Qwen/etc. through one key, so
  dedicated Claude/OpenAI providers are intentionally **not** planned.
- **WhisperKit engine (deferred):** SpeechAnalyzer (macOS 26) is the on-device default. WhisperKit
  would add an external dependency + model management; it's the likely path to true multilingual
  **code-switching** (e.g. Mandarin↔English mid-sentence), which Apple's on-device Speech can't do.
- **Cross-launch session history (deferred):** export covers sharing/review; a live copilot's
  sessions are otherwise ephemeral.
