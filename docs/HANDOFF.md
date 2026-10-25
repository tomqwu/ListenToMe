# Handoff — 2026-10-25

A snapshot for an agent picking up ListenToMe cold. [AGENTS.md](../AGENTS.md) and
[CLAUDE.md](../CLAUDE.md) stay the rules; this note is only the state of things on the date above.
Re-check anything time-sensitive (`gh issue list --state open`, `git log`, tags) before acting on it.

## Compatibility feedback candidate — October 25

Current branch `codex/306-ipad-start` combines #306 and #307 with the maintainer's cross-platform
compatibility request. It is not merged or published yet. iOS metadata is prepared for **1.17.1 (35)**;
latest accepted TestFlight remains **1.17.0 (34)**. Do not upload 34 again. The configured ASC API key
worked at preflight; production reported 1.15.0 READY_FOR_SALE and build 35 was unused. Recheck before upload.

The connected iPad Pro 12.9-inch (4th generation), iPadOS 27.0.1, reproduced the old failure. Its native
capability probe reported SpeechTranscriber unavailable, DictationTranscriber English supported and
Apple Intelligence device-not-eligible. The local fallback candidate then passed actual new microphone
speech, Stop and retained Play/Pause UI on that iPad. At `e0e5062`, both that iPad and the iPhone 12 Pro
Max passed actual new speech, Stop and retained Play/Pause UI using the default Automatic language.
The iPad also passed the native unavailable-Apple-provider settings check. Later changes shorten the
Summary header and refresh cached AI eligibility; final frozen-source validation remains required.
Existing iPad data/preferences were backed up and preserved. Synthetic sound is gated on confirmed
Listening, never played while Start is failing. Native `devicectl device capture screenshot` is available.

Implementation: advanced/dictation module fallback and lazy result delivery; shared language catalog;
proactive iOS capture gates; explicit unavailable Apple choices; Watch local/remote readiness; Mac
AI/engine/permission gates. Foreground and Start-token fences prevent delayed imports/capture/errors
after cancellation. [Compatibility](device-compatibility.md) is mandatory BDD across all platforms.
Watch remains excluded; Mac releases remain paused.

Focused evidence in the external October 25 `listentome-features/ipad-start-306` folder:
`compatibility-final-focused-green` passed 40 native iOS unit tests plus five UI tests, with only the
intentional physical-only capability report skipped. Inputs stayed unchanged and the dedicated simulator
was deleted. Its five screenshots were inspected. The subsequent `compatibility-core-permission-green.log`
passed all 17 focused Core readiness/cancellation tests, after the late permission-denial regression
failed in `late-permission-error-red.log`. Independent review cleared the two lifecycle blockers and the
final permission callback fix. Earlier actual red/green and physical evidence is preserved in the same
folder; do not invent red outcomes for baseline tests. The `e0e5062` signed Mac Dev app passed actual
system-audio transcription labeled OTHERS and native settings inspection. Its original settings were
restored and verified, both owned Dev bundles moved to Trash, and only `com.tomwu.ListenToMe.dev`
permissions reset. Watch simulator inspection passed offline remote gating and denied-microphone
recovery; its dedicated simulator was deleted. This does not establish paired physical Watch behavior.

The initial full run passed 1,085 Core tests (seven skips, 98.1239% coverage), then reproduced a
large-text landscape reachability regression and was intentionally stopped; it is not a full pass.
CAPTURE-009 failed before shortening the Summary-only compatibility reason, then its two focused UI
tests and the long release-history accessibility test passed. Older unit fixtures now explicitly
refresh language readiness and choose their fake HTTP provider; all 431 unit tests then passed (seven
intentional skips). CAPABILITY-003's new Check again example reproduced a stale Apple readiness cache
and passed after refreshing it. The final ten AI/recording readiness tests also passed, with real
language-change invalidation assertions. Source hashes and simulator cleanup are recorded for each run.
Full frozen-source validation, final release screenshots, CI/merge and accepted beta upload remain
pending at this snapshot. Physical capture screenshots now use the full display to avoid XCTest's
landscape app-coordinate crop; a direct native iPad screenshot confirmed the actual layout is intact.

No new speculative PRs: the live queue remains 17 existing drafts. Finish this feedback change before
resuming the sequential backlog; the old #60 validation queue ended with two failures, so triage its
preserved result rather than restarting it blindly. The new `__pycache__/` ignore/test prevents generated
Python caches from falsely dirtying candidate provenance; all 18 BDD gate regressions pass.

## Repository-wide BDD adoption (October 25)

All behavior changes, including older branches when integrated, now follow [BDD](BDD.md): write
Given/When/Then scenarios in `Behaviors/`, reproduce with a failing native test, implement, then
refactor under passing tests. `make bdd-check` and the required core CI job enforce scenario/test
traceability for app and delivery changes. Use the PR template for actual red/green evidence.
The initial catalog adopts representative existing tests; it does not claim exhaustive legacy
coverage or historical red runs. Existing full validation, rendered UI/audio acceptance, independent
review and release gates remain required. This workflow change alone calls for no binary release.

The BDD workflow's full local run at `9ceee7a` passed: 1,068 Core tests (seven skips, 98.1107%
coverage), 471 iOS tests (461 passed, ten intentional skips, zero failures), release helpers, lint,
signed Mac build and real Ollama/OpenAI contracts. The log confirms every bound iOS unit/UI method
passed. Integration keeps product sources identical to the validated `dbd1cc7` release candidate
and retains that validated workflow, with a subsequently reproduced CI base-selection fix: PRs
fetch their current target branch instead of using the stale base SHA saved when the PR opened.
The new DEV-005 regression runs the actual CI shell against an advancing local Git remote; it
failed on already-merged behavior before the fix and passed afterward, retaining push/unbound-change
and failed-fetch checks. All 17 gate regressions pass. PR #305 records final review/CI/merge evidence.
Main's strict up-to-date branch requirement is enabled and read back, retaining the three checks.

The maintainer requires finishing work before opening more feature PRs. Six redundant #134 drafts
(#297–#302) were closed as superseded by #303 after verifying their heads are ancestors of it. All
branches/commits and evidence remain preserved; acceptance of the consolidated code is still required.

## October 25 validation follow-up

The #127 full run at `0464e9d` exposed a shared iOS test synchronization race: the automatic-review coordinator sets its active mode before the fake provider receives the request. The test now waits for the provider-held continuation before editing Notes and releasing the response. Its cancellation, completed-output and no-repeat assertions remain intact. The focused regression passed 20 consecutive iterations on the 1.17.0 candidate source with this fix; independent review found no blockers. This is test-only. The integrated `dbd1cc7` candidate subsequently passed full validation and four device capture tests (details below); the original failed run is preserved externally. The 1.17.0 train subsequently published as recorded below.

## Product state

| Surface | Latest published | State of `main` |
| --- | --- | --- |
| iPhone/iPad (TestFlight) | **1.17.0 (34)**, published 2026-10-25, tag `ios-v1.17.0-build34` at `cbd2e45` | This feature batch is published to Dev; Watch remains excluded. Physical-device acceptance is pending. |
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
  upload remains pending: 1.15.0 was waiting for review at capture time and this train did not alter it.
  The October 25 Apple API preflight now reports 1.15.0 READY_FOR_SALE.
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
   and two iPad sizes passed. Evidence: `dist/language-activity-216`; included in TestFlight 1.17.0 (34).
4. **#224 — re-transcribe saved audio:** finish existing PR #264; its live Mac audio gate is still pending.
5. **#176 — UI-test reliability:** merged in #273 at `991128b`. Full local validation passed: 1,050 Core tests at 98.10% coverage; 393 iOS unit and 65 UI tests, ten iOS skips, zero failures; real Ollama contracts passed. Seventy-five native screenshots and the xcresult are preserved in `dist/ui-reliability-176` and the October 25 external evidence folder. Test-only; no binary release needed.
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
- #176 is fixed in #273: serial simulator execution and condition-based permission/correction/summary waits passed the full local gate on a dedicated simulator, including overlapping Mac build and acceptance work.
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

## Context capacity merged (#210) — October 25

PR #274 adds optional per-server limits with reserved answer space and a no-send oversized-prompt error. Full `make validate-local` passed on `a6ec6b8`: 1,056 Core tests (seven skips, 98.1079% coverage), 394 iOS unit tests and 65 UI tests (459 total, ten skips, zero failures), release helpers, lint, signed Mac build and real Ollama/OpenAI-compatible contracts. Mac settings acceptance and independent review passed. A Pro Max screenshot run exposed a caret-position assumption in the URL-editing test; selecting all and asserting the exact replacement value fixed it, and the focused rerun passed. Only test/documentation changes followed the full gate. All 20 native screenshots across four device categories were inspected and passed. PR #274 merged as `98a8f646637f7766480cb2fab3de8761e86ffe3b` with all three required CI checks green. Evidence is preserved in `dist/context-budget-210` and the October 25 external evidence folder. The iOS behavior is published in TestFlight 1.17.0 (34); macOS publication remains paused.

## In progress: History index reuse (#223)

PR #277 implements per-passage vector reuse and fixes a Mac shared-search reader lifetime bug found during installed-app acceptance. Full `make validate-local` passed on `bacbb7d`: 1,060 Core tests (seven skips, 98.1048% line coverage), 459 iOS tests (449 passed, ten skipped, zero failures), release helpers, lint, signed Mac build and both real server contracts. All three required CI checks passed. Installed Mac History search/vector reuse/removal and independent review passed; screenshots and cleanup evidence are preserved. The per-passage iOS behavior is included in TestFlight 1.17.0 (34); Mac publication remains paused. Broader semantic language support remains open: contextual mean pooling and tested normalizations did not meet paraphrase/negative-query quality acceptance. No additional models are downloaded or enabled.

## Per-conversation Mac deletion candidate (#131) — October 25

`codex/131-delete-conversation` adds confirmed deletion in History row menus and detail views.
Archive deletion precedes registered data-owner cleanup; other records stay intact. The open
conversation is excluded from future saves after deletion. Tests cover real archive/audio files,
archive failure and partial owner failure. Focused storage tests passed (22), full Core coverage
passed (98.1087%), both iOS simulator architectures compiled, and lint, signed Mac build and
independent review passed. Full `make validate-local` passed at `b11a101`, including simulator
unit/UI tests, Core coverage, release helpers and real provider contracts. The #223 records snapshot
is published after deletion. Current-main integration lint, Core tests, signed Mac build and independent
review passed at `f3dd237`. All three hosted checks passed at `5f42af9`. Installed-Mac acceptance passed at that source using disposable records and generated audio: Cancel retains audio/playback; row/detail deletion removes the chosen record; neighboring records and exports remain; deleting the open conversation prevents re-saving; New saves normally; locked archive and audio fixtures produce the expected retained-record and partial-erasure warnings. Original archive hashes were unchanged and Dev cleanup succeeded. Evidence is preserved in the October 25 external `history-delete-131/native` folder. Latest-main integration at `41d33cf` passed 1,068 Core tests (seven skips, zero failures; 98.1107% coverage), lint, the stable development-signed Mac build and independent review. The deletion implementation is unchanged from native acceptance. All three final-head checks passed; PR #284 merged at `5eb674f`, closing #131. Mac publication remains paused.
## Ollama endpoint candidate (#149) — October 25

`codex/149-ollama-endpoint` shares the OpenAI-compatible local-network HTTP rule, reports omitted
URL components without echoing credentials or query values, and uses Ollama Cloud in destination
prose. The existing automatic-catalog guard already requires the Ollama provider plus a saved key
or custom endpoint; the removed workspace prose now uses the shared endpoint label. The provider
default's recomputation until an explicit choice is now documented. Full `make validate-local` passed
at `a756271`, including simulator unit/UI tests, Core coverage, helpers, lint, signed Mac build and
real provider contracts. Signed focused checks also passed after repairing IPv6 normalization. Both
Settings notice/recovery screenshots were inspected. Current-main integration at `5a1ddd8` passed
all 403 iOS unit tests (397 passed, six skipped), 1,061 Core tests (seven skipped, 98.1056% coverage),
lint and the signed Mac build. Independent integration review found no blockers. Hosted checks for
the final documentation commit subsequently passed and the integration merged. iOS changes are published in TestFlight 1.17.0 (34); physical-device acceptance remains pending and Mac publication remains paused.


## In progress: speaker lifecycle follow-ups (#188)

Branch `codex/188-speaker-lifecycle` cancels final labeling on background, clears the run buffer and
binds queued passes to their original recording token. Tests now drive the actual periodic loop,
bound Stop/background return while a model is held, and cover a cancellation-ignoring final pass,
queued old work followed by restart, and actual default-model-directory backup exclusion. Existing
Watch prompt mapping tests already cover the issue's device-label item. Speaker privacy/support
wording now distinguishes clearing the run buffer from an in-flight model operation finishing.
Full `make validate-local` passed on `f1bd693`: Core coverage above 98%, 462 simulator tests
(452 passed, ten skipped), release helpers, lint, signed Mac build and real provider contracts.
Independent review cleared the queued-old-run race and same-file backup-policy extraction. Native-resolution
Watch speaker transcript/Notes simulator screenshots were preserved and visually reviewed. This is
simulator acceptance, not physical-device acceptance. Current-main integration passed at `ac20342`: all
46 focused iOS lifecycle/backup/preparation/Watch checks, Core tests (1,060, seven skips, 98.1048%), lint,
signed Mac build and all three hosted checks. Evidence: `dist/speaker-lifecycle-188` and external release evidence. The merged iOS behavior is included in TestFlight 1.17.0 (34); physical-device acceptance remains pending. Watch is still excluded from distribution.

## In progress: iOS live snapshot and provisional prompts (#164)

Branch `codex/164-ios-live-snapshot` implements memoized live summary inputs and provisional
floor/tag/notice handling for manual Summary, Quick and Ask. The shared excerpt shortener preserves
the marker and minimum evidence. Twenty-one Core grounding tests pass; iOS app and all test targets
compile for both simulator architectures, lint passes, and independent logic review found no blockers.
Full `make validate-local` passed at `2d1b2cd`, including the new iOS runtime regressions, Core
coverage above 98%, release helpers, signed Mac build and real provider contracts. A dedicated manual
Summary simulator journey now verifies provisional request tagging and removal after final recognition;
all five focused checks passed at `00cc28f`, and both native-resolution screenshots were inspected.
Current-main integration lint/Core (1,061 tests, seven skips, 98.1056%) and all three hosted checks passed.
Included in TestFlight 1.17.0 (34). Physical-device acceptance remains pending. Evidence: `dist/live-snapshot-164`.

## iOS 1.17.0 (34) TestFlight publication — October 25

`codex/ios-1.17.0-build34` integrates merged `5eb674f`. The batch contains only merged iOS work:
Duo width choices, conversation vocabularies, language activity checks, speaker lifecycle fixes,
live-summary/provisional handling, History index reuse and deletion privacy, provider context limits and Ollama endpoint
feedback. Watch remains excluded. No draft backlog PR is included. The preflight identified 1.15.0
as READY_FOR_SALE, so the prepared App Store What's New covers everything after 1.15.0.

Integrated candidate `dbd1cc7` passed full `make validate-local`: 1,068 Core tests (seven intentional
skips, 98.1107% coverage), 471 iOS tests (461 passed, ten intentional skips, zero failures), lint,
release helpers, the signed Mac build and real Ollama/OpenAI-compatible contracts. All four device
capture tests passed. The 24 final native-resolution images (six per iPhone 17 Pro/Pro Max and iPad
mini/13-inch Pro) were inspected and accepted; both phone sets were retaken on the same source after
rejecting a system-notification overlay in the first captures. Originals, normalized images, native
sizes, hashes, device/runtime/source provenance and review results are preserved externally and in
`dist/ios-1.17.0-build34-evidence/`. README images now use the accepted 1.17.0 set.

The earlier `e176222` run (470 iOS tests) is preserved as superseded evidence. The integrated
candidate includes #131 on iOS. Final docs/media source `cbd2e45` passed all three required checks
and PR #304 merged at `166b380`. The signed archive/export and distribution package checks passed;
the helper's accepted-upload receipt records 2026-10-25 16:27:39 UTC. Apple processing is VALID,
internal state IN_BETA_TESTING, Dev includes build 34 with both existing testers enrolled, and en-CA
What to Test/beta description readback matches. Enrollment state is not evidence of a new install.

The remote `ios-v1.17.0-build34` tag peels to exact archive source `cbd2e45`. The complete
[GitHub pre-release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.17.0-build34) was read
back with no binary asset; macOS v1.4.4 stays Latest. Receipt, source/signing/package checks,
metadata, tag/release readback and the matching validated IPA are preserved externally in the
October 25 `ios-next-train` evidence. Physical-device acceptance and App Store screenshot listing
upload remain pending. No production App Store submission was made.

## Mac Auto compatibility acceptance (#209) — October 25

The final installed-Mac settings interaction passed at `c3746b5`: saved 4K persists, an oversized probe sends nothing, an unsaved 8K edit disables probing, Cancel restores 4K, and a valid synthetic response succeeds with server-managed context. Original provider/model settings were restored. Screenshots, the one synthetic request, source/signing provenance and successful Dev-only cleanup are preserved in the October 25 external `auto-compatibility-209/native-final` evidence. Current-main integration includes only the already-merged iOS endpoint validation and documentation; Mac application source is unchanged from this acceptance. Final integration at `8e9e612` passed 1,065 Core tests (seven skips, 98.1098% coverage), lint, the signed Mac build and all 403 iOS unit tests (397 passed, six skipped). Independent integration review found no blockers. All three final-head checks passed and PR #275 merged at `3d32345`; #209 is closed. Mac publication remains paused.

## iPad tester feedback: startup diagnostics (#306) and AI eligibility (#307)

The tester reports Start listening staying/returning to idle after microphone approval. Model,
iPadOS and installed build are not yet known, so no physical cause or recording fix is claimed.
The local #306 change adds a prominent full-error alert and recording-settings recovery. The initial
iPad simulator UI regression failed before implementation and passed afterwards; four model-level
checks cover retry, cancellation and recording without summary AI. Independent review cleared startup and cancellation changes. Full validation,
CI and merge remain required. #307 tracks unavailable Apple Intelligence
selection and explicit alternate-provider setup; it is not implemented by the startup alert.

The connected iPhone 12 Pro Max on iOS 27.0 completed an attended physical test with the real
microphone and synthetic speech: Listening, current transcript, Stop and retained audio Play/Pause
controls passed (one test, zero failures/skips). Native-resolution screenshots were inspected and
source/signing evidence preserved. This was a development build with Auto/correction off and saved
audio enabled for the test launch; it is not a new TestFlight release. Audible playback and network
traffic were not measured. The reporter's iPad still needs its own acceptance. The physical test
was then hardened to require an empty new conversation before phrase matching; that test-only
change needs its next native run.
