# ListenToMe

A personal, on-device macOS meeting copilot: it listens to your mic and the other participants'
system audio, transcribes live, and gives real-time suggestions — on demand (⌘⇧Space or the
buttons) and proactively when someone asks a question. Models are configurable; the MVP defaults to
a local Ollama model, so nothing leaves your machine.

## Requirements
- macOS 26+
- Xcode 26+, `brew install xcodegen` (and optionally `swiftlint`, `xcbeautify`)
- [Ollama](https://ollama.com) with a model pulled: `ollama pull llama3.1`

## Build & run
```bash
make test     # run the ListenToMeCore test suite (65: unit + integration)
make build    # generate the Xcode project and build the app
make run      # build and launch
make pre-push # lint + tests + build (the CI-equivalent gate)
```

## Models
Pick the model in the in-app **Settings** (gear icon): **Ollama** (local, default) or **DeepSeek**
(`deepseek-v4-flash` / `deepseek-v4-pro`). The DeepSeek API key is entered in Settings and stored in
your macOS Keychain; the selection persists across launches. Adding Claude/OpenAI is the same pattern
(a new `LLMProvider`). Settings also lets you choose the transcription engine (SpeechAnalyzer / SpeechRecognizer).

## CI
GitHub Actions (`.github/workflows/ci.yml`) gates every PR to `main` on a macOS runner:
SwiftLint, the full `ListenToMeCore` test suite (unit + headless integration/e2e), and a
**coverage floor of 95%** enforced by `scripts/check-coverage.sh`. Because the app target deploys
to macOS 26 and uses ScreenCaptureKit/Speech, the **app build and GUI/audio e2e cannot run on
hosted runners** — those are verified locally via `docs/manual-smoke-test.md`.

## Local e2e (pre-push)
`make e2e` runs the checks CI can't (it needs a real Mac + Ollama): it builds the **app target**,
verifies `make run`'s app-path resolution, and runs a **real LLM contract test** against your local
Ollama through the actual `OllamaProvider` — model defaults to **`llama3.1`** (pull it with
`ollama pull llama3.1`), or set `LTM_E2E_MODEL=deepseek-v4-flash:cloud` (or any pulled model) to
exercise the cloud thinking-model path. `make e2e` preflights that the model is available and fails
with a clear message if not. Requires Ollama running at `localhost:11434`. The gated test is skipped
by normal `swift test`/CI. **Not covered (still manual):** mic/system-audio capture and live
speech-to-text, which need a GUI session + Speech/Screen-Recording permission grants — see
`docs/manual-smoke-test.md`.

## Permissions
On first run, grant Microphone, Speech Recognition, Screen Recording (for system audio), and
Accessibility (for the global hotkey) in System Settings → Privacy & Security.

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
- **Done:** DeepSeek provider (`deepseek-v4-flash` / `deepseek-v4-pro`) + Ollama, selectable in Settings, key in Keychain.
- Claude / OpenAI providers (same `LLMProvider` pattern, Keychain-stored keys)
- WhisperKit / SpeechAnalyzer transcription engines (Settings-switchable)
- Session persistence and export
