# ListenToMe backlog

The active backlog lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues).
Use the existing P1/P2/P3 labels to distinguish priorities. An open enhancement is a proposal,
not a claim that the released app is broken. Do not duplicate the candidate list here.

## Product constraints

Transcription stays on-device. AI uses explicit Local only / Cloud / AI off modes; adding a key
must not silently change routing. The released backend is Ollama. Any proposed compatible-endpoint
support must preserve these guarantees, including local relays and redirects, before it can ship.

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

- Android/Windows products, and Mac↔iOS sync or companion features.
- Cloud accounts, team workspaces, and public sharing links.
- Per-vendor AI SDK integrations; the current backend is Ollama.

The standalone iPhone/iPad app is in scope at the maintainer's request. What it is for, and what it
deliberately leaves to macOS, is stated once in
[iOS → What this app is for](IOS.md#what-this-app-is-for) and
[iOS → Parity with macOS](IOS.md#parity-with-macos) — including the tier-3 list (system/call audio
capture, background recording, a local Ollama daemon, WhisperKit, Mac sync). Do not restate it here.

Exploratory work must preserve explicit consent, local storage and truthful privacy/accuracy claims.
