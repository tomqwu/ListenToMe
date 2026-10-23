# ListenToMe backlog

The active backlog lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues).
Use the existing P1/P2/P3 labels to distinguish priorities. An open enhancement is a proposal,
not a claim that the released app is broken. Do not duplicate the candidate list here.

## Product constraints

Transcription stays on-device. AI uses explicit Local only / Apple Intelligence / Cloud /
Cloud AI service / OpenAI-compatible / AI off modes; adding a key must not silently change routing.
OpenAI-compatible servers (#52) are never treated as local — a loopback or LAN address is "your server",
anything else "may leave this device" — redirects are never followed, and a key is bound to the server
it was saved for. Cloud AI presets (#214: OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter,
Groq, Mistral, xAI) are opt-in, nothing is selected by default, each is labelled "Sends your transcript
to <vendor>", each vendor keeps its own Keychain key bound to its own origin, and no model is ever
picked for the user.

## Shipped through 1.3.2

Presets, reference files and budgets, audio import, optional WhisperKit, calendar context,
keyword History search, Markdown/recap/PDF export, resizable panes, and experimental on-device
speaker identification/naming are available. Production hardening added atomic conversation saves,
full History details, Save/New controls, explicit AI routing, and surfaced runtime failures.
1.3.2 fixed repeated/inconclusive permission UI and documented verified production capture recovery.

The earlier cockpit redesign PR #51 is superseded by the shipped save/new/history layout and the
[September design direction](reviews/2026-09-10/production-roadmap.md). It is not in progress.

See [the September triage](reviews/2026-09-10/backlog-triage.md) for the disposition of older PRs.

## Intentionally out of scope

- Android/Windows products, and Mac↔iOS sync or companion features. "Companion" here means a Mac↔iOS
  link only. An Apple Watch companion to the iPhone app is **in scope**
  ([#181](https://github.com/tomqwu/ListenToMe/issues/181); design and decisions in
  [the Apple Watch recording spec](superpowers/specs/2026-10-22-apple-watch-recording-design.md)).
- Cloud accounts, team workspaces, and public sharing links.
- Vendor AI SDKs. No vendor SDK is linked: backends are Ollama, Apple Intelligence, the generic
  OpenAI-compatible `/v1/chat/completions` protocol and Anthropic's Messages API, all over plain HTTP.
  Per-vendor *presets* over HTTP (#214: a fixed address, key page and privacy link per vendor, and a
  native Messages API client for Claude) are **in scope** at the maintainer's request (2026-10-23).

The standalone iPhone/iPad app is in scope at the maintainer's request. What it is for, and what it
deliberately leaves to macOS, is stated once in
[iOS → What this app is for](IOS.md#what-this-app-is-for) and
[iOS → Parity with macOS](IOS.md#parity-with-macos) — including the tier-3 list (system/call audio
capture, background recording, a local Ollama daemon, WhisperKit transcription, Mac sync). Do not restate it here.

Exploratory work must preserve explicit consent, local storage and truthful privacy/accuracy claims.
