# ListenToMe — Contributor & Agent Guide

macOS SwiftUI **meeting copilot**: fully on-device transcription (Apple SpeechAnalyzer / opt-in WhisperKit)
plus real-time AI via Ollama (local + cloud), with per-pane model selection and use-case presets.

- **Engine** logic lives in `Sources/ListenToMeCore` (SwiftPM library, **has tests** in `Tests/ListenToMeCoreTests`).
- **UI** lives in `App/` (SwiftUI; **no UI tests** — verify UI changes with `make build` plus a manual `make run`).
- Build: `make build`. Run: `make run`. Full check (build + bundle path + `OllamaProvider` contract test): `make e2e`.

## Canonical release workflow

Read [AGENTS.md](AGENTS.md) first. It is the shared instruction source for all agents. A change is
done when it is merged to `main` with the three required checks green, relevant tests passing and
every affected doc updated — **publication is a separate, batched step**, governed by the release
trains in AGENTS.md: at most one macOS release and one TestFlight build per day, never one release
per merged PR. Merged-but-unpublished is the expected state; do not call merged work released. When
a train is due, AGENTS.md's ladder (candidate → verified → published) and its downloaded-asset
verification apply in full. The checklist below adds documentation and issue hygiene; it does not
replace that workflow. Documentation-only changes do not require an unrelated model request or
binary release.

## Definition of Done

A change is **not done** until ALL of the following are true. Treat this as a checklist on every task.

1. **Relevant checks pass** — code changes require build/tests; run `make e2e` for affected model/capture paths and the pre-merge gates in AGENTS.md. Documentation-only changes require link/content checks and hosted CI.
2. **Every relevant doc is updated to match — not just the obvious one.** Sweep the whole doc set and
   update anything the change affects: `README.md`, `docs/backlog.md`, `docs/competition-analysis.md`,
   `docs/manual-smoke-test.md`, `docs/RELEASING.md`, `docs/IOS-RELEASING.md`, `CHANGELOG.md`, and any
   plan/spec under `docs/superpowers/`. A change to release policy also means `AGENTS.md`. Stale
   docs are a Definition-of-Done failure, not a follow-up.
3. **The backlog lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues), not docs.** If the
   change fully implements a known gap, **link and close the matching issue in the same PR**. Keep valid
   unimplemented enhancements open; close duplicates with a link and obsolete items with a reason. New ideas become
   issues (`enhancement` + `priority: P1/P2/P3`), never bullets in a markdown backlog.
4. **The PR description states what was verified** (commands run + outcomes).

## Product principles (do not violate)

On-device · private · bring-your-own-model · free & open-source. Anything that would send data off-device
**by default** is out of scope (see `docs/backlog.md` → "Intentionally out of scope").
