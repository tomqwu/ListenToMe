# ListenToMe — Contributor & Agent Guide

macOS SwiftUI **meeting copilot**: fully on-device transcription (Apple SpeechAnalyzer / opt-in WhisperKit)
plus real-time AI via Ollama (local + cloud), with per-pane model selection and use-case presets.

- **Engine** logic lives in `Sources/ListenToMeCore` (SwiftPM library, **has tests** in `Tests/ListenToMeCoreTests`).
- **UI** lives in `App/` (SwiftUI; **no UI tests** — verify UI changes with `make build` plus a manual `make run`).
- Build: `make build`. Run: `make run`. Full check (build + bundle path + `OllamaProvider` contract test): `make e2e`.

## Definition of Done

A change is **not done** until ALL of the following are true. Treat this as a checklist on every task.

1. **Code builds and checks pass** — `make build` is clean and `make e2e` passes.
2. **Every relevant doc is updated to match — not just the obvious one.** Sweep the whole doc set and
   update anything the change affects: `README.md`, `docs/backlog.md`, `docs/competition-analysis.md`,
   `docs/manual-smoke-test.md`, `docs/RELEASING.md`, and any plan/spec under `docs/superpowers/`. Stale
   docs are a Definition-of-Done failure, not a follow-up.
3. **The backlog lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues), not docs.** If the
   change implements a known gap, **link and close the matching issue in the same PR**. New ideas become
   issues (`enhancement` + `priority: P1/P2/P3`), never bullets in a markdown backlog.
4. **The PR description states what was verified** (commands run + outcomes).

## Product principles (do not violate)

On-device · private · bring-your-own-model · free & open-source. Anything that would send data off-device
**by default** is out of scope (see `docs/backlog.md` → "Intentionally out of scope").
