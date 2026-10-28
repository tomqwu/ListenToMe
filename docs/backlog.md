# ListenToMe backlog

The active backlog lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues).
Use the existing P1/P2/P3 labels to distinguish priorities. An open enhancement is a proposal,
not a claim that the released app is broken. Do not duplicate the candidate list here.

## Product constraints

[Device compatibility](device-compatibility.md) is a BDD contract across Mac, iPhone/iPad and Watch:
unavailable features need proactive gating, a visible reason and applicable explicit alternatives.

Transcription stays on-device. AI uses explicit Local only / Apple Intelligence / Cloud /
Cloud AI service / OpenAI-compatible / AI off modes; adding a key must not silently change routing.
OpenAI-compatible servers (#52) are never treated as local — a loopback or LAN address is "your server",
anything else "may leave this device" — redirects are never followed, and a key is bound to the server
it was saved for. Cloud AI presets (#214: OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter,
Groq, Mistral, xAI) are opt-in, nothing is selected by default, each is labelled "Sends your transcript
to <vendor>", each vendor keeps its own Keychain key bound to its own origin, and no model is ever
picked for the user.

## Shipped so far

What each release contains is in [CHANGELOG.md](../CHANGELOG.md); this is only the outline.

- **macOS 1.4.4** (latest release, 2026-09-14): presets, reference files and budgets, audio import,
  optional WhisperKit, calendar context, keyword History search, Markdown/recap/PDF export,
  resizable panes, experimental on-device speaker identification/naming, atomic conversation saves
  with Save/New controls, explicit AI routing, Apple Intelligence for manual summaries, and the
  opt-in Auto Quick Summary scheduler shared with iPhone. macOS releases are paused; work merged
  since 1.4.4 (Cloud AI service and OpenAI-compatible modes, semantic History search and Ask your
  history, more export formats, Save to folder, saved audio, vocabularies, automatic titles,
  suggested prompts) is **unreleased** — see "macOS (unreleased since 1.4.4)" in the changelog.
- **iPhone/iPad 1.17.0 (34)** (TestFlight, 2026-10-25): the earlier capture/recall features below plus
  conversation prompts, iPhone Duo pane balance, persisted conversation vocabularies and improved
  language/speaker lifecycle checks. The 1.17.1 compatibility feedback candidate is not yet published.
  Previously shipped: on-device recording and transcription with
  Automatic language, speaker labels, Apple Intelligence by default or Ollama, an OpenAI-compatible
  server or an opt-in Cloud AI service, Quick Summary and Summary (Deep is macOS-only), Save to
  folder, export formats, semantic History search and Ask your history, vocabularies, opt-in saved
  audio and Summarize selection.
- **Apple Watch** is included in TestFlight **1.20.2 (42)** and public iOS **1.19.1 (39)** ([#181](https://github.com/tomqwu/ListenToMe/issues/181)). The [current beta receipt](releases/ios-1.20.2-build42.json), [public release receipt](releases/ios-1.19.1-build39-public.json) and [Watch guide](watch-beta.md) record distribution separately from physical microphone, paired-transfer, wrist-down and production acceptance, which remain pending.

The earlier cockpit redesign PR #51 is superseded by the shipped save/new/history layout and the
[September design direction](reviews/2026-09-10/production-roadmap.md). It is not in progress.

See [the September triage](reviews/2026-09-10/backlog-triage.md) for the disposition of older PRs.

## Intentionally out of scope

- Android/Windows products, and Mac↔iOS sync or companion features. "Companion" here means a Mac↔iOS
  link only. An Apple Watch companion to the iPhone app is **in scope**
  ([#181](https://github.com/tomqwu/ListenToMe/issues/181); design and decisions in
  [the Apple Watch recording spec](superpowers/specs/2026-10-22-apple-watch-recording-design.md)).
- Cloud accounts, team workspaces, and public sharing links.
- Vendor AI SDKs. No vendor SDK is linked: Ollama, the generic OpenAI-compatible
  `/v1/chat/completions` protocol and Anthropic's Messages API are called over plain HTTP, and Apple
  Intelligence through Apple's on-device framework. Per-vendor *presets* over HTTP (#214: a fixed
  address, key page and privacy link per vendor, and a native Messages API client for Claude) are
  **in scope** at the maintainer's request (2026-10-23) and shipped in iPhone 1.14.0 (31); on macOS
  they are merged but unreleased.

The standalone iPhone/iPad app is in scope at the maintainer's request. What it is for, and what it
deliberately leaves to macOS, is stated once in
[iOS → What this app is for](IOS.md#what-this-app-is-for) and
[iOS → Parity with macOS](IOS.md#parity-with-macos) — including the tier-3 list (system/call audio
capture, background recording, a local Ollama daemon, WhisperKit transcription — iOS links WhisperKit
only to detect the spoken language — and Mac sync). Do not restate it here.

Exploratory work must preserve explicit consent, local storage and truthful privacy/accuracy claims.

## Translation implementation

[Issue #330](https://github.com/tomqwu/ListenToMe/issues/330) implements opt-in live translation and a
Translate option on the existing Summary page. [The feature guide](translation.md) records scope
and verification boundaries; translation is in TestFlight 1.20.2 (42), remains unreleased on Mac, and does not add summary length/format controls. [Issue #343](https://github.com/tomqwu/ListenToMe/issues/343) has its fix merged and published in TestFlight 1.20.2 (42); [publication receipt](releases/ios-1.20.2-build42.json) and [recovery evidence](translation-recovery.md) keep physical acceptance separate.
