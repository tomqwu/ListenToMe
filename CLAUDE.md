# ListenToMe — Contributor & Agent Guide

macOS SwiftUI **meeting copilot**: fully on-device transcription (Apple SpeechAnalyzer / opt-in WhisperKit)
plus real-time AI via Ollama (local + cloud), with per-pane model selection and use-case presets.

- **Engine** logic lives in `Sources/ListenToMeCore` (SwiftPM library, **has tests** in `Tests/ListenToMeCoreTests`).
- **UI** lives in `App/` (SwiftUI; **no UI tests** — headless adapter tests run through `make mac-test`; verify UI changes with `make build` plus a manual `make run`).
- Build: `make build`. Run: `make run`. Full check (build + bundle path + `OllamaProvider` contract test): `make e2e`.
- Store sandbox acceptance: `make mac-sandbox-build` with stable Dev signing; follow
  [the local sandbox runbook](docs/RELEASING.md#local-sandbox-acceptance). This uses the existing
  `.dev` identity and requires normal Dev cleanup; it is not a Store installation/upload pass.

## Canonical release workflow

Read [AGENTS.md](AGENTS.md) first. It is the shared instruction source for all agents. A change is
done when it is merged to `main` with the three required checks green, relevant tests passing and
every affected doc updated — **publication is a separate, batched step**, governed by the release
trains in AGENTS.md: at most one macOS release and one TestFlight build per day for trains an agent
starts on its own, never one release per merged PR. A train the maintainer calls ("publish", "release
what's on `main`", "publish as always") goes out the same day even if one already departed, and work the
maintainer requested from tester feedback ships on a TestFlight train as soon as it is merged and its
candidate checks pass, without waiting a day or asking again. Merged-but-unpublished is the expected
state; do not call merged work released. When a train is due, AGENTS.md's ladder (candidate → verified → published) and its downloaded-asset
verification apply in full. The checklist below adds documentation and issue hygiene; it does not
replace that workflow. Documentation-only changes do not require an unrelated model request or
binary release.

After each confirmed PR merge, follow AGENTS.md's branch-cleanup rule: verify deletion of the
matching remote feature branch, delete its local branch when safe, and prune stale tracking
refs. Preserve unfinished changes, later commits, active checkouts, release tags and evidence;
record deferred cleanup instead of disrupting active work.

### TestFlight and official App Store review

[AGENTS.md](AGENTS.md#publishing-an-ios-release-train) owns TestFlight publication;
[official App Store review](AGENTS.md#official-app-store-review-and-public-release) is a separate
authorized workflow. For a due beta train, use the
[TestFlight skill](.agents/skills/listentome-testflight/SKILL.md) and
[iOS runbook](docs/IOS-RELEASING.md) through accepted upload, processing and existing tester-group
verification. Check the configured credentials before requesting sign-in; an unlocked Mac or
connected phone is not required for the CLI/API beta-upload route. Record missing physical acceptance.

The maintainer’s **2026-10-28 (Toronto)** standing instruction authorizes review submission whenever
an iOS (iPhone/iPad + embedded Watch) or macOS version is ready. Submit without renewed permission
after the canonical readiness gates pass. Complete production acceptance, **en-US** metadata
and localized-name readback, complete release notes, current reviewer/privacy details, selected-build
verification and fresh screenshot uploads before submitting. Cover iPhone/iPad, Duo and embedded
Watch, and Mac as a separate platform. Verify processed screenshot sets and downloaded images;
local captures do not update Apple's listing. Preserve the existing release mode, including leaving
manual-release versions pending after approval; submission authority is not a manual-release command. Reuse existing
authorization for the version/platform, and operate the submission instead of handing the clicks
back to the maintainer. Retain Apple's submission receipt and distinguish review submission,
approval, pending manual release and public availability. A TestFlight beta or Mac GitHub DMG is
not an official App Store submission. Documentation-only requests do not authorize distribution.

All behavior changes follow the repository-wide [BDD workflow](docs/BDD.md): scenario first,
failing native test, implementation, passing test, then refactor. Bind Given/When/Then scenarios in
`Behaviors/` to concrete test methods, run `make bdd-check`, and include scenario IDs plus actual
red/green evidence in the PR. This applies to app code and build/release automation alike; the
existing validation, independent review and publication gates remain required.

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
