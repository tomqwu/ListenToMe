# Handoff — 2026-10-24

A snapshot for an agent picking up ListenToMe cold. [AGENTS.md](../AGENTS.md) and
[CLAUDE.md](../CLAUDE.md) stay the rules; this note is only the state of things on the date above.
Re-check anything time-sensitive (`gh issue list --state open`, `git log`, tags) before acting on it.

## Product state

| Surface | Latest published | State of `main` |
| --- | --- | --- |
| iPhone/iPad (TestFlight) | **1.16.0 (33)**, published 2026-10-24, tag `ios-v1.16.0-build33` at `980c471` | This feature batch is published to Dev; Watch remains excluded. Physical-device acceptance is pending. |
| macOS | **1.4.4 (14)**, 2026-09-14, tag `v1.4.4` | **Releases paused on the maintainer's decision.** About 50 commits of Mac work are merged but unreleased; see [CHANGELOG → macOS (unreleased since 1.4.4)](../CHANGELOG.md#macos-unreleased-since-144). Do not start a macOS train yourself; the maintainer calls it. |
| Apple Watch | Not shipped | Built on `main` behind the `WATCH_EMBED` build flag (off; `scripts/ios-testflight.sh` refuses an archive that embeds it). Waits on the maintainer running `SPIKE.md` on a real watch (branch `spike/181-watch-audio`, [#181](https://github.com/tomqwu/ListenToMe/issues/181)), then the Task 20 physical-device acceptance from #193. Status table in the [watch plan](superpowers/plans/2026-10-22-apple-watch-recording.md). |

Recent iOS trains (full text in [CHANGELOG.md](../CHANGELOG.md)):

- **1.12.0 (29):** speaker names on by default; on-device Automatic language detection (the default).
- **1.13.0 (30):** returning voices, every on-device language, Acknowledgements, Save to folder,
  language re-checks, OpenAI-compatible servers.
- **1.14.0 (31):** Cloud AI presets — OpenAI, Claude (native Messages API), Gemini, DeepSeek,
  OpenRouter, Groq, Mistral, xAI.
- **1.15.0 (32):** Delete all conversations; better Quick grounding and the output-limit notice;
  auto-naming; suggested prompts; export formats with per-line language; the **Deep tab removed on
  iOS** (Quick Summary and Summary remain; saved Deep analyses stay readable as "Earlier deep
  analysis"); domain vocabularies and My terms; semantic search and Ask your history; opt-in saved
  audio; Summarize selection.

## 1.16.0 (33) release train

- Published to TestFlight from `980c47172f502109e8329e776aafc535d630235a`. Apple processing is `VALID`, internal state
  `IN_BETA_TESTING`, Dev includes build 33 and the intended tester is accepted. en-CA What to Test
  and beta description were read back successfully. Evidence: `dist/ios-1.16.0-build33-evidence/`.
  Major iOS releases include TestFlight. No physical installation is claimed.
- Sixteen fresh native screenshots cover iPhone 17 Pro/Pro Max and iPad mini/13-inch Pro. Originals,
  orientation-normalized copies, hashes and source manifest are in the release evidence. Listing
  upload remains pending: App Store 1.15.0 is waiting for review and this train did not alter it.
- Validation: 1,028 core tests (98.162% coverage), 364 iOS unit tests, release helpers, lint, app builds
  and real Ollama contracts completed. Two initial full UI failures were resolved by focused reruns;
  the original aggregate command was not a clean pass. Four final capture tests passed.

- #257: Context/Notes prompt editor with Ask once, saved summary instructions, and optional domain presets.

- #253: adaptive two-pane Live workspace on wide iPhone windows, with independent Transcript and
  Quick scrolling; narrow windows and accessibility text retain a stacked fallback.

- #238: all seven presets now select Simplified Chinese terms for `zh`/`zh-Hans` transcription;
  other languages keep English lists. Chinese suggestions work without spaces and use the local
  Chinese embedding when present. Device accuracy acceptance is still pending (#236).

## Next train: local Ollama context capacity

- #230 sizes local model context to the assembled prompt with a conservative UTF-8 budget and
  reserved output space. Oversized requests fail clearly before chat; cloud context stays unchanged.

## Merged for the next train

- #268: iPhone Duo remembers equal, transcript-first or Quick-first pane widths, with readable
  minimum widths. Secondary transcript actions share a compact menu; Expand remains directly
  reachable. Narrow and accessibility layouts retain their stacked fallback.

- #200: Watch imports in Automatic use only an already-downloaded language model, scan past leading
  silence, and pin the chosen locale in the ledger before transcription. Retries and later chunks
  keep it even after Settings changes. Missing or uncertain detection falls back without downloading.
  Watch remains excluded from distribution; Mandarin on an English iPhone still needs paired-device
  acceptance. This does not change the #181 embedding gate.

- #237: per-conversation vocabulary additions survive History reopen and relaunch, are deleted
  with the conversation, and reach Auto Quick as bounded domain/glossary guidance. Device defaults
  and My terms remain independent. JSON exports include vocabulary IDs and saved prompt instructions.

## Screenshot release requirement

Every train captures fresh source-matched screenshots for all supported device categories. Follow
[the screenshot checklist](IOS-RELEASING.md#screenshot-capture-and-app-store-handoff-255), preserve the
full-resolution assets and manifest, and verify uploaded listing sets before App Store submission.

## How work was done

- **One issue per PR**, branched from `main`. Never commit to `main`.
- **Integrate `main` by merge** — never rebase or force-push a pushed branch.
- **Every feature PR got an independent correctness review before merge** (a separate agent reading
  the diff against the issue). It caught real bugs in nearly every PR; keep doing it.
- **Required checks** are the three CI checks: `ListenToMeCore tests + coverage`, `macOS 26 app build`,
  `iOS 26 app build`. Local gates are in AGENTS.md (`make validate-local`, `make lint`, `make e2e`).
- **Mac Dev cleanup:** reuse the primary checkout's `signing.local.mk` before building in a worktree.
  After testing, preserve evidence, close inactive test apps, move verified `.dev` bundles to Trash,
  and reset only `com.tomwu.ListenToMe.dev` permissions. Defer cleanup for another active Dev session;
  preserve production, conversations and keys. See AGENTS.md and docs/RELEASING.md.
- **`make ios-test`** runs on a freshly erased, dedicated simulator (`IOS_DESTINATION=…`), created for
  the run and deleted afterwards, so state from other runs cannot leak in.
- **UI tests use launch fixtures**, never real model downloads: `LISTENTOME_SPEAKER_MODELS_FIXTURE`
  (speaker models) and `LISTENTOME_LANGUAGE_MODEL_FIXTURE` (language-detection model).
- **`iOS/MobileSession.swift` sits near SwiftLint's file/type length limits.** Put new logic in an
  extension file (`iOS/MobileSession+*.swift`) or in `Sources/ListenToMeCore`, not in that file.
- **Releases** follow AGENTS.md and [IOS-RELEASING.md](IOS-RELEASING.md): upload with
  `make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<commit>`, using the App
  Store Connect API key configured in `~/.config/listentome/testflight.json`. Evidence for each build
  lives in the gitignored `dist/ios-<ver>-build<n>-evidence/`, including `asc-verify-script.py` (the
  App Store Connect check — copy it forward to the next evidence folder). Each TestFlight build also
  gets a GitHub **pre-release** on its `ios-v…` tag (not Latest; notes from CHANGELOG, no binary);
  these exist for every iOS tag. From the next build on, each page must be complete: version/build,
  source commit, full notes, What to Test, privacy changes, and App Store "What's New" text since
  the last App Store production release (iOS 1.10.5).
- **Release archives** for recent builds are in the gitignored `dist/`:
  `ListenToMe-ios-1.13.0-build30.xcarchive`, `…-1.14.0-build31.xcarchive`,
  `…-1.15.0-build32.xcarchive`, and `ListenToMe-ios-1.16.0-build33.xcarchive`. Earlier archives were moved there from temporary worktrees after upload, so the
  `upload-accepted.json` receipts in the evidence folders still name the old scratch paths. That is
  expected; do not edit the receipts.

## Maintainer preferences

- Cares about **product output**, not PR mechanics. Report what users get and its status
  (merged / candidate / published), briefly.
- **Publish a TestFlight build once requested work is merged and verified** (candidate checks pass);
  don't wait to be asked again (AGENTS.md release trains).
- **iOS is the primary surface.**
- **Nothing leaves the device by default.** Cloud AI is opt-in, with clear "Sends your transcript to …"
  labels. **Never auto-assign a paid hosted model**; the user picks every model.

## Sequential implementation plan — October 24

The maintainer asked to finish issues one at a time, with Watch and Duo first. Each item gets its
own implementation, relevant local acceptance, independent review and merged PR before the next.

1. **#192 — Watch speaker labels:** bounded file windows, isolated from live microphone runs,
   already-loaded models only, labels saved before audio deletion. Merged in #270; not released.
2. **#225 — Watch audio sync and optional retention:** approved October 24: queue while disconnected,
   sync to the paired iPhone after reconnect, and retain playback audio only when Save audio recordings
   is on. Off keeps delete-after-transcription. Merged in #271 with retry, deletion, consent and
   playback coverage; not released. Watch distribution remains gated by #181.
3. **#216 — language re-check reliability:** implemented in #272; full `make validate-local` passed
   (1,050 Core tests, 98.10% coverage; 393 iOS unit and 65 UI tests, ten iOS skips, zero failures),
   including real Ollama contracts. Independent review and 20 fresh screenshots across two iPhone
   and two iPad sizes passed. Evidence: `dist/language-activity-216`; not released.
4. **#224 — re-transcribe saved audio:** finish existing PR #264; its live Mac audio gate is still pending.
5. **#176 — UI-test reliability:** remove remaining state/time assumptions in the full local gate.
6. Then iOS/provider improvements (#210, #209, #223, #164, #188, #167, #148, #149), followed by
   the Mac conversation tools (#131, #126, #127, #128, #129, #124, #68, #173, #56), then the remaining
   enhancements and review trackers (#58, #60, #62, #54, #134, #141, #98).

#181 distribution, #205 mixed-language accuracy and #236 vocabulary accuracy retain their hardware
acceptance gates. Simulator checks proceed without waiting for hardware; they do not close those gates.
Duo #253/#268 and Watch language #200 are already merged; newly demonstrated gaps get separate issues.
Release trains remain batched, with TestFlight for each major iOS release and fresh device screenshots.

## Mac Auto compatibility candidate — October 25

PR #275 implements #209 on `codex/209-mac-auto-compatibility`. At source
`1ddd0caeca4d5323e8be6ac1634d6002e62c919e`, four focused Core tests, lint and the signed
Mac build passed, followed by independent review. Installed-app acceptance against a local
synthetic server passed valid JSON, malformed prose, HTTP failure, cancellation, disabled checking
for unsaved endpoint edits, visible Auto pause reason, and a successful recheck. All five requests
contained only the synthetic exchange. Original settings were restored, the idle Dev app was closed
and moved to Trash, and the exact Dev bundle's permissions were reset successfully.

Native screenshots, signing provenance and results are preserved in `dist/mac-auto-209` and
`/Users/tomwu/Documents/Codex/2026-10-25/listentome-features/mac-auto-209`. Full
`make validate-local` and final hosted checks remain required before merge. This is not released.

## Open work, prioritized

All in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues); [#98](https://github.com/tomqwu/ListenToMe/issues/98)
is the tracking issue.

**iPhone — next candidates**

- [#224](https://github.com/tomqwu/ListenToMe/issues/224) Re-transcribe a conversation from its saved audio (P2)
- [#205](https://github.com/tomqwu/ListenToMe/issues/205) Opt-in multilingual Whisper transcription for mixed-language sentences (P3)
- [#236](https://github.com/tomqwu/ListenToMe/issues/236) Measure and strengthen vocabulary biasing for SpeechTranscriber (P2)
- [#54](https://github.com/tomqwu/ListenToMe/issues/54) Meeting auto-detection / auto-start (P2)

**Apple Watch — waiting on the maintainer's device spike**

[#181](https://github.com/tomqwu/ListenToMe/issues/181) (record from the watch),
[#192](https://github.com/tomqwu/ListenToMe/issues/192) (merged in #270; paired-device speaker acceptance pending),
[#200](https://github.com/tomqwu/ListenToMe/issues/200) (implemented; paired-device language acceptance pending),
[#225](https://github.com/tomqwu/ListenToMe/issues/225) (merged in #271; paired-device retention acceptance pending).

**macOS — P1/P2** (lands on `main`; ships when the maintainer resumes Mac releases)

- P1: [#68](https://github.com/tomqwu/ListenToMe/issues/68) transcript timestamps and follow-latest
- P2: [#131](https://github.com/tomqwu/ListenToMe/issues/131) per-conversation delete,
  [#126](https://github.com/tomqwu/ListenToMe/issues/126) select/copy/edit transcript lines,
  [#127](https://github.com/tomqwu/ListenToMe/issues/127) cancel a streaming response or import,
  [#124](https://github.com/tomqwu/ListenToMe/issues/124) global hotkey without Accessibility,
  [#128](https://github.com/tomqwu/ListenToMe/issues/128) import video files and choose a source,
  [#129](https://github.com/tomqwu/ListenToMe/issues/129) first-run Ollama guidance,
  [#56](https://github.com/tomqwu/ListenToMe/issues/56) live audio meter and per-role latency

**Technical follow-ups**

[#210](https://github.com/tomqwu/ListenToMe/issues/210),
[#176](https://github.com/tomqwu/ListenToMe/issues/176),
[#134](https://github.com/tomqwu/ListenToMe/issues/134) (P2, coverage scope),
[#141](https://github.com/tomqwu/ListenToMe/issues/141),
[#148](https://github.com/tomqwu/ListenToMe/issues/148),
[#149](https://github.com/tomqwu/ListenToMe/issues/149),
[#164](https://github.com/tomqwu/ListenToMe/issues/164),
[#167](https://github.com/tomqwu/ListenToMe/issues/167),
[#173](https://github.com/tomqwu/ListenToMe/issues/173),
[#188](https://github.com/tomqwu/ListenToMe/issues/188),
[#209](https://github.com/tomqwu/ListenToMe/issues/209),
[#216](https://github.com/tomqwu/ListenToMe/issues/216),
[#223](https://github.com/tomqwu/ListenToMe/issues/223),
[#58](https://github.com/tomqwu/ListenToMe/issues/58),
[#60](https://github.com/tomqwu/ListenToMe/issues/60),
[#62](https://github.com/tomqwu/ListenToMe/issues/62).

## Known flaky or order-dependent tests

- #241 is fixed: provider-default tests explicitly set/restore the cloud vendor and pass before UI tests on a fresh simulator.
- [#176](https://github.com/tomqwu/ListenToMe/issues/176): the iOS UI test bundle is flaky under
  machine load.
- `Tests/ListenToMeCoreTests/SharedQuickLoopTests.swift` has a timing flake; re-run before suspecting
  your change.

## Waiting on the maintainer

- **App Store listing URLs** (privacy policy and support) point at the `codex/app-store-release`
  branch and should be repointed to `main` in App Store Connect. Do not delete that branch until they
  are.
- **Physical-device checks pending for 1.16.0:** prompts, two-pane rotation, vocabulary accuracy, saved audio, Summarize
  selection and Ask your history. The beta train has no physical-device
  acceptance; do not call it production-ready.
- **Apple Watch spike** and acceptance, above.
