# Unreleased local History Refresh — October 30, 2026

Explicit **Refresh search** rebuilds derived local Apple search data without changing conversations
or downloading assets. Focused evidence: three Core methods green; sixteen Mac methods green,
including current-archive races and actual native controls; three phone methods green, including
no-results and empty History. Recovery-caption contrast went from 3.949:1 red to 14.938:1 green.
[Scoped evidence and pending gates](history-local-refresh.md) ·
[Fresh README previews and provenance](images/history/unreleased-2026-10-30/manifest.json).

This follow-up is **not included in accepted TestFlight 1.20.3 (43)**. Full validation passed on
`c8fdcd29`: Core 1,294 tests/seven skips/98.0768% coverage; iOS 605 tests/twelve skips; Mac 118 and
Watch 34, zero failures. All 1,071 frozen inputs and all required BDD bindings matched. Actual signed
Debug Dev History Refresh, repeat, new-row reload and Quit/relaunch passed with two synthetic records;
fresh installed Mac images were inspected. [Aggregate/installed receipt](evaluations/history-local-refresh-validation-2026-10-30.json).
`13573f90` adds only landscape test/catalog coverage to the unchanged app: two native cases passed
on phone/iPad, zero failures/skips, all 1,074 inputs unchanged. Fresh unqueried landscape/iPad and
installed Mac gallery images were inspected; phone additional actions retain normal scrolling.
Current exact-head CI, hosted final-gallery review and merge remain pending. Detailed preservation
and prior capture-harness limits are in the linked evidence. Additional-language quality remains
open under #223; negative experiments remain failed.

## TestFlight 1.20.3 (43) published — October 30, 2026

Apple accepted **1.20.3 (43)** through the official TestFlight helper at
**2026-10-30T17:10:34.841880+00:00** from `97ef2461b86869405c1d0f4221816b790f0216fd`.
Apple build `fe7d15fb-c6f2-487b-89b6-6f9d26985ccc` is **VALID / IN_BETA_TESTING**.
Readback completed at **2026-10-30T17:16:53.246500+00:00** confirms **en-US**,
**Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for
both existing Dev-group members. Access does not establish physical installation of build 43.

[Publication receipt](releases/ios-1.20.3-build43.json) · [Composite validation](releases/ios-1.20.3-build43-validation.json) · [Release notes and What to Test](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.3-build43).

The exact transported IPA was preserved and its SHA-256, transport MD5 and byte count matched.
Phone, Share and embedded Watch distribution signatures/profiles, versions, disabled debugging and
fixture-payload checks passed. The GitHub pre-release targets exact source `97ef2461`, has no attached
assets and is not Latest. PR [#349](https://github.com/tomqwu/ListenToMe/pull/349) merged as `3106bcd`;
all three required checks passed on release source `97ef2461` in
[run 41092176457](https://github.com/tomqwu/ListenToMe/actions/runs/41092176457).

Validation is explicitly composite. Full `make validate-local` passed on functional baseline
`5f1e909`, tree-identical to merged PR #318 (`388a5c7`): Core **1,291 tests / seven optional skips /
zero failures / 98.0766% coverage**; iOS **590 passes / 12 skips**; Mac **109 passes**; Watch **34 passes**;
236 BDD scenarios and four real-server contracts. The release-only version/notes delta then passed
**seven native tests, zero failures/skips**, after a genuine two-assertion red. Candidate `8dc8dd3`
keeps those app/config/test inputs; only documentation and gallery files changed before release
source `97ef2461`. This does not claim a new full build-43 aggregate run.

Fresh captures at `8dc8dd3` passed **17 native tests, zero failures/skips**, across seven profiles.
All **57 native originals** were inspected; seven suitable originals refresh the
[README gallery](../README.md#screenshots). [The manifest](images/ios/release-1.20.3/manifest.json)
preserves native checksums, provenance and QA-only exclusions. Hosted gallery inspection passed at
1280-pixel desktop and 390-pixel mobile widths on `97ef2461`. None of these 57 images was uploaded to
Apple's listing. Original failed validation/preview attempts and the pre-extraction verifier field
error remain preserved separately; the repaired verifier did not repeat the upload.

PR [#318](https://github.com/tomqwu/ListenToMe/pull/318) closed **#333, #335, #337, #346, #347 and #348**.
Six remain open: **#181, #205, #223, #236, #334 and #336**. Optional MPNet delivery remains excluded,
with its source and negative results preserved. #334 still needs installed Mac rename Save/relaunch;
#336 retains its near-end/overlap/routes matrix. These limits do not reopen completed fixes.

Physical phone/iPad translation, screen-lock, multilingual and Watch acceptance remains pending.
Public production remains **1.19.1 (39)**; this beta made no public review submission or listing-media
upload. Mac changes remain unreleased, and **v1.4.4** remains GitHub Latest.

Release evidence is retained under `2026-10-30/listentome-ios1203-train/`; the sanitized receipts above
bind the helper acceptance, Apple/GitHub readbacks, full baseline, focused checks and uploaded bytes.

Completed Dev sessions were closed after process-absence checks. Three exact `.dev` bundles were
preserved and moved to Trash; two owned synthetic QA records were preserved before removal. Only
`com.tomwu.ListenToMe.dev` permissions were reset, exit 0. Production permissions, existing user
conversations/settings, credentials and evidence were preserved. The original disabled vault URL
was not retained; the selected QA folder remains disabled as the documented restoration exception.
Cleanup receipt: `2026-10-30/listentome-backlog318-completion/dev-cleanup/receipt.json`.
Older checkpoints below retain their then-current source/status and are not current release claims.

# Compact Duo layout recovery — October 30, 2026

Full `make validate-local` on `95ac6387c112d82a083170caa95d6d88a3a893ed` failed the clean Duo
preview on the shorter **iPhone 17 Pro / iOS 26.5 simulator**: transcript and Quick text crossed
their reader viewports. The owned run was interrupted after genuine assertions and ended exit 2,
reaped. Its iOS bundle has **50 passed, five skipped, one genuinely failed and one canceled** test;
the canceled test is not a second product failure, and the aggregate did not pass.

The same strengthened `READMEPREVIEW-001` test reproduced two clipping assertions in the focused
red run (exit 65). A minimal production spacing fix then passed the unchanged test: **one case,
zero failures, exit 0, reaped**, with recorded inputs unchanged. The native image was inspected:
both authored transcript lines and all three Quick lines are visible. Content and 44-point controls
are preserved; accessibility scrolling remains. The earlier README preview changed only fixture data
at that checkpoint; this follow-up changes compact-landscape production spacing.

On committed `cb4cd313f8f85ae9d1214f0a2ecf2194de255c1a`, follow-up native UI passed **six tests,
zero failures/skips**: five on iPhone 17 Pro (portrait/rotation, compact controls, accessibility
scrolling, synthetic recording/Stop and clean Duo), plus clean Duo on Pro Max, both iOS 26.5.
Both runs ended exit 0/reaped with all **1,043 frozen inputs unchanged**. The unchanged native Pro
image refreshes the local README preview; the older Max image remains labelled historical.
[Current image and both run receipts](images/ios/candidate-2026-10-30/manifest.json).

Evidence: `2026-10-30/listentome-backlog318-completion/full-validation/`, `duo-compact-red/`,
`duo-compact-green/` and `duo-focused-preparation/`. [Behavior and limits](IOS.md#unreleased-compact-landscape-duo-spacing).
Fresh full validation, exact-head CI, hosted README rendering and affected installed acceptance
remain pending. PR #318 remains unmerged; no release, review submission or Store-media upload is claimed.

# Backlog completion scope — October 30, 2026

PR #318 is being narrowed to its completed fixes and independently tested Apple History/indexing
repairs. The optional MPNet installer, runtime and Settings controls are withdrawn from this
candidate because their unchanged language-quality gate failed. Their complete source/tests remain
preserved in `08521d5f2bf7d5e20410359e6560bd2d5c066eb6`; external native results and independent
reviews remain intact. Issue #223 stays open. This is not a model-quality pass or a waiver.

The candidate retains #333–#337 and #346–#348, correction-export provenance, screen-lock Settings
copy, current README policy/gallery and the Apple vocabulary/query, indexing and generic-query
repairs. Fresh local validation, independent review, hosted CI and affected installed acceptance
are required before merge. No merge or release is yet claimed. Release-monitor automation remains
paused while the explicitly resumed backlog work proceeds.

The older checkpoints below describe their recorded sources. Their optional-runtime controls and
quality-gate failures are historical for this narrowed candidate, not statements that those
controls will be shipped. [Scope and preserved evidence](history-search-implementation.md).

# Generic History queries — October 29, 2026

The current PR #318 follow-up fixes reproduced German/Spanish generic-query false matches.
`GENERICQUERY-001`–`008` cover actual Related/Ask paths, word/sentence and optional adapters,
literal search, real topics, compounds and uncertainty. Native red: four methods/36 assertions;
Core red: one method/seven assertions, expanded to ten before implementation. Review caught an
introduced single-word ambiguity regression (one native/four Core assertions); that is repaired.
The final native run passes **38 functional methods** while the same four optional-model quality
methods still fail **12 assertions**. All 16 stored passage files are byte-for-byte unchanged.
Core passes **1,300 tests / seven optional skips / zero failures / 97.9288% coverage**.
Nine iPhone simulator runtime methods pass with no skips; build/runtime preserve all 1,048 inputs.
All 263 Core BDD bindings, 264 structural scenarios, lint and diff checks pass. These simulator
checks do not establish physical-device or additional-language quality acceptance.

Queries now use whole-token equivalents of the existing English policies. Passage recipes,
signatures, ranking cutoffs, literal History search and unsupported-language behavior stay intact.
Ask keeps its narrower stopword policy; ambiguous account/story/painting terms remain searchable.
This is not acceptance of additional-language quality. No visible UI changed; README retains its
source-labelled gallery. Remaining validation, current CI, affected acceptance and merge are open.
[Evidence and limits](history-search-implementation.md#generic-query-parity--october-29-follow-up).

The preceding query-revision fix `34267ca` passed all three required checks in
[run 40962403033](https://github.com/tomqwu/ListenToMe/actions/runs/40962403033).
No version, upload, review submission or release is claimed.

# Stored Apple query compatibility — October 29, 2026

The current PR #318 follow-up preserves saved sentence-model History entries when word assets
become available for the same language. Queries now respect each stored type and exact revision;
passage recipes, stored bytes, minima and relevance cutoffs stay unchanged. `APPLEQUERY-001`–`003`
include a real persisted-vector regression, mixed representations, malformed tags and unsupported
revisions. Two methods/five assertions failed before repair; all three now pass. The wider run
passes **32 functional methods** but still fails the same four MPNet quality methods/12 assertions.
Core passes 1,298 tests with seven optional skips and 97.6489% coverage; all 261 Core BDD bindings
and 256 structural scenarios pass. Nine iPhone simulator runtime methods pass without skips; lint
and diff checks pass. Full validation, hosted CI, affected acceptance and merge remain open.
No visible UI changed; the README gallery keeps its source-labelled captures.
[Evidence and limits](history-search-implementation.md#stored-apple-query-representations--october-29-follow-up).

The preceding `f82c60f` passed all three hosted checks in
[run 40958000664](https://github.com/tomqwu/ListenToMe/actions/runs/40958000664).
No merge, version bump, upload or review submission is claimed.

# Apple word lookup and installed Copy acceptance — October 29, 2026

The current PR #318 follow-up fixes a reproduced Apple History vocabulary defect. German models
loaded successfully but lowercasing removed all five in-vocabulary nouns from the unchanged travel
sample. The adapter now preserves non-English spelling with lowercase fallback and rebuilds stale
empty caches. `APPLEWORD-001`–`005`: two methods/six assertions red, five methods green; **29 Mac
functional methods pass**, while the four MPNet quality methods still fail 12 assertions. The
separate Apple German baseline now has real vectors but remains **4/8** with one negative-query
error. No quality criterion was relaxed. [Evidence and limits](history-search-implementation.md#case-sensitive-apple-vocabulary-regression--october-29-follow-up).

All three hosted checks passed on the preceding `b8ebe86` in
[run 40953710186](https://github.com/tomqwu/ListenToMe/actions/runs/40953710186). This new source needs
its own CI. Core passes 1,298 tests (seven optional skips, zero failures), 97.6925% coverage;
all 261 Core BDD bindings pass. Nine iPhone simulator runtime methods pass with no skips.
All 253 BDD scenarios and lint pass. Full validation, affected acceptance, merge and release remain open.
No visible UI changed; the README gallery keeps its existing source-labelled captures.

Fresh signed sandbox source `b8ebe86` also passed installed transcript pointer selection, keyboard
selection, Command-C and Edit-menu Copy with exact paste readback, accessibility Edit line and
Cancel preserving the original rows. The existing synthetic conversation was used; no capture or
provider request ran. Inline screenshots were inspected, but the native screenshot shortcut saved
no Desktop image, so there is no saved-image claim. Actual VoiceOver and live-audio acceptance are
separate. Source/signature and all 32 payload files verified; the completed Dev app was moved to
Trash and only its app-scoped permissions reset. Independent review cleared the bounded receipt in
`2026-10-29/listentome-mac337-copy-acceptance/`. No production permissions or data were changed.

# Preserve Apple History routing — October 29, 2026

Draft PR #318 preserves installed Apple embeddings when optional History languages are enabled and
rebuilds stale derived vectors without altering conversations. Two new native regressions failed ten
assertions before repair. All three hosted checks passed on application commit `f5edcc5` in
[run 40951031804](https://github.com/tomqwu/ListenToMe/actions/runs/40951031804).

A later official Apple asset request made German lexical tags and sentence embeddings available;
Japanese timed out and Korean was not requested. This exposed an insufficient-content smoke sample,
which was corrected without changing production code or the quality corpus. The final focused runs
pass **24 Mac functional methods and nine iPhone simulator runtime methods**, no skips. Actual model
quality still fails four methods / **12 assertions**, with unchanged DE 2/8, ES 1/8, JA 4/8, KO 2/8
retrieval. The earlier 15-assertion outcome belongs to the prior asset state. This fixture/docs
follow-up needs its own CI. Full validation, installed/physical acceptance and merge remain open.
[Evidence and limits](history-search-implementation.md#preserve-installed-apple-languages--october-29-follow-up).

No visible UI changed; the README screenshots remain accurate for their explicitly labelled sources.
No new PR, version, upload, review submission or release was created.

# README Duo preview and bounded installed Mac checks — October 29, 2026

`f3b35f430b9182c5df62f6cf2f420a2753d08351` adds a capture-only short example in the existing
DEBUG/simulator design fixture; production layouts and default fixtures are unchanged.
`READMEPREVIEW-001` failed two genuine clipped-text assertions, then the same native test passed
with both authored transcript lines and the complete Quick answer visible. The original six-screen
capture journey also passed. All 1,039 inputs stayed unchanged in each run; independent code/pixel
review cleared the result. The README now includes the native candidate image with full-size link
and [source/binary/image provenance](images/ios/candidate-2026-10-29/manifest.json). It is not a new
TestFlight build or Store upload. BDD now contains 245 scenarios. The owned simulator was deleted
after all 138 retained evidence files were verified; other simulators were preserved.

Signed sandbox Mac source `0f94823` also passed two bounded installed checks: History now renders
the $120 → $125 edit as **Manual correction**, and a picker-selected external reference folder
survives full process exit/relaunch with actual file content read by an existing local Ollama model.
Opening another History conversation clears references by design and was recorded separately.
No capture ran. Original provider/models were restored, references cleared, the exact Dev app moved
to Trash and only its app-scoped permissions reset. The source/signature/payload and independent
audit receipts are under `2026-10-29/listentome-mac318-gallery-acceptance/` in retained local evidence.
Vault write/relaunch, identified-speaker interaction, real OTHERS audio and physical acceptance
remain incomplete; these two checks do not establish full sandbox or production acceptance.

All three hosted checks passed on `ece5593` and documentation head `0f94823`
([40934516059](https://github.com/tomqwu/ListenToMe/actions/runs/40934516059),
[40938355944](https://github.com/tomqwu/ListenToMe/actions/runs/40938355944)). This new follow-up
still needs its own hosted CI. Full current validation remains blocked by the four real-model
History quality failures below; supplying assets runs those required tests, while skipping them
cannot satisfy BDD. No merge, version bump, upload or review submission is claimed.

# Current follow-up: export provenance and History ranking — October 29, 2026

The working follow-up to `bb50e673cf7892d64872c8e8ac4645b29214d6da` fixes two reproduced
regressions in the existing draft PR #318. It is not merged or ready for distribution.

- Markdown exports now distinguish manual edits from known AI corrections and legacy corrections
  with unknown provenance. The first recognized wording remains intact. The exporter regression
  failed two methods / 14 assertions before repair; all 20 exporter and golden tests then passed.
- Independent History models no longer change each other's relevance mean or top-score cutoff.
  Existing single-population behavior remains; independent admitted results combine by rank.
  Five Core group contracts include a genuine tie-order regression. All 55 focused Core History
  tests pass. The actual native composite reproduced five failures before its grouping override.
  Strengthened persisted-vector checks pass in all seven runtime methods on both Mac and an
  isolated iPhone simulator; simulator evidence does not establish physical acceptance.
- Full current Core: **1,298 tests / seven optional skips / zero failures / 97.6913% coverage**, including
  all **261 required Core BDD selectors**. All **244** scenarios pass structural checks; repository
  `make lint` passes. Full combined validation,
  installed/physical acceptance and exact follow-up CI remain outstanding. The three required
  checks passed on the preceding `bb50e67` in
  [run 40928129148](https://github.com/tomqwu/ListenToMe/actions/runs/40928129148).
- The optional model's quality gate still fails: DE 2/8, ES 1/8, JA 4/8, KO 2/8. A separately frozen
  sentence-window diagnostic reached 4/8, 3/8, 4/8, 3/8 respectively, below six-of-eight in every
  language, with remaining negative/filler errors. That experiment is not integrated into the app.

[History implementation and evidence](history-search-implementation.md). Correction evidence is
retained under `/Users/tomwu/Documents/Codex/2026-10-29/listentome-manual-correction-export/`.
No version bump, upload, review submission or new publication was performed.

# In progress: History implementation and regression fixes — October 29, 2026

This checkpoint adds actual #223 application/Core code on top of `57ac48f`; it is unmerged and
**not ready for distribution**. Existing PR #318 remains the single draft. The earlier complete
validation and installed acceptance below apply to their recorded sources, not this new work.

- Added an asynchronous optional local model runtime, explicit verified asset installation and
  Settings download/Cancel/opt-in/Remove controls for Mac and iPhone/iPad. Apple remains default;
  no conversation/query upload or additional model download occurred during development.
- Reproduced and fixed stale search results after saving, an older queued save restoring derived
  data after Clear, failed model-switch recovery, legacy-cache reuse and short-query misrouting.
  The real iOS Form also exposed an adjacent destructive-action tap hazard; separate rows repair it.
  Settings now accurately describes screen-lock recording and paused optional AI work.
- Current Core after test placement repair: **1,290 tests / seven optional skips / zero failures / 97.7364% coverage**.
  Mac: **17 functional methods pass**; all **six actual-model runtime methods pass on iOS simulator**.
  Three Settings journeys pass on iPhone and together on iPad; fresh QA screenshots are preserved
  and inspected. **235 BDD scenarios** pass structural/change coverage against the actual PR base.
  The first hosted Core check lacked Spanish lexical assets; all original assertions now remain
  required in the appropriate Core/native suite. Local Core BDD passes all 253 selectors, and the
  four moved native eligibility methods pass without skips. No runtime or quality rule changed.
- The separate real-model quality gate remains failed: DE **2/8**, ES **1/8**, JA **4/8**, KO **2/8**
  paraphrases versus the unchanged six-of-eight requirement, with remaining filler/negative errors.
  No threshold or corpus label was loosened. Additional language coverage is not established.
- Full combined validation, exact-head CI, merge and affected installed/physical acceptance remain
  open. No release version, TestFlight upload, App Store submission or listing-media upload was made.
  Do not infer current production readiness from earlier source passes or this focused runtime work.

[Implementation, BDD evidence and remaining limits](history-search-implementation.md).

# Backlog evidence checkpoint — October 29, 2026

The combined application/test source remains `02205d278197d67c0cb29606e3fa63b2c6547c00`.
Its documentation follow-up `a30aa535dcb809219eabd4fa89a67f03f17798a5` passed all three required
checks in [CI run 40824605186](https://github.com/tomqwu/ListenToMe/actions/runs/40824605186).
PR #318 remains draft and unmerged: installed Mac audio/interaction and the other acceptance gates
below are incomplete. This later documentation-only checkpoint needs its own review/CI; it does
not change application behavior, call a release or waive those gates.

- **#236:** The unchanged after-assets Mac retry completed all 22 observations, five native tests
  and the independently recounted scorer. All 16 target-presence comparisons showed zero gains or
  losses. Retain the bounded decision against custom Dictation integration; actual-app physical
  read-aloud/Add/language/personal-name acceptance remains incomplete. No further model search is
  needed for that negative decision. [Updated evidence](vocabulary-biasing-evaluation.md).
- **#223:** The actual Core export passed native noninterference tests. Fixed topical diagnostics
  then found English and Spanish vectors on this Mac, while German/Japanese/Korean lacked stored
  vectors. English and Spanish each returned 7 of 16 intended topical memberships, with nine
  omissions and no extra eligible Related results. Prepared Ask requests are separate from answers;
  no provider ran. No new language support or ranking change is implemented.
  [Native baseline and limits](semantic-search-evaluation.md).
- **#205:** The isolated benchmark now signs with existing local credentials and packages all 73
  asset files exactly. It installed on the iPhone 17 Pro Max, but Xcode reported a locked-device
  launch refusal before any observed test/model case. The owned attempt was stopped, all 539 frozen
  inputs remained unchanged, and the temporary app was uninstalled with absence verified. The signed
  candidate and raw diagnostics are preserved; no permission/account/TestFlight changes or repeated
  participant request were made. Physical compatibility and the required mixed-language accuracy,
  speed, battery and go/no-go decision remain outstanding. [Evidence and next steps](IOS.md#mixed-language-whisper-evaluation-205--october-29-2026).

The two owned recovery-validation simulators were also deleted after all 1,882 retained native
result files were rechecked. Other simulators, application data and worktrees were preserved.

# Combined PR #318: full automated validation passed on 02205d2 — October 29, 2026

Exact combined source `02205d278197d67c0cb29606e3fa63b2c6547c00` completed
`make validate-local` with **exit 0 / child reaped** at **2026-10-29 04:46:15 UTC**.
Independent terminal audit found no issues and matched all **1,004** frozen inputs. Core:
**1,266 tests / 7 optional skips / 98.2004% coverage**; iOS: **509 unit + 90 UI tests**, with
**587 passes / 12 optional skips**; Mac: **84 passed**; Watch: **29 unit + 5 UI passed**.
All suites had zero failures. All **185** BDD scenarios were structurally valid and all **511**
required Core/native selectors passed; six helper suites, the hotkey regression and four real-server
contracts passed. [Sanitized source-bound receipt](releases/combined-02205d2-validation.json).
All three raw native bundles were retained externally and **1,882 files** byte-verified. The owned
validation jobs ended. The native Mac synthetic Chinese translation branch passed; it is not
physical-phone or installed-app GUI/audio acceptance. The earlier `dafe4fa` aggregate remains failed.

The existing draft PR #318 now carries this combined source. Exact-head hosted checks in
[run 40820211886](https://github.com/tomqwu/ListenToMe/actions/runs/40820211886) were still running
when this documentation checkpoint was prepared; no hosted pass is inferred. This docs-only
follow-up needs separate review/CI. No merge, version bump, binary publication or Store submission
is claimed.

Installed/physical gates remain open: the latest resumed signed Dev session was unlocked, with
microphone active but ScreenCaptureKit **-3801**, zero transcript lines and no acceptance fixture
played; OS authentication blocked recovery. Final-source OTHERS/near-end/overlap/repeated speech,
headphones/routes, Stop recovery/delayed playback, sandbox vault/reference relaunch, speaker
process-relaunch/VoiceOver, physical phone/Watch and Apple-distributed Mac installation remain
pending. Mac increased-contrast propagation is unverified. After automated testing, three exact
`com.tomwu.ListenToMe.dev` bundles were moved to Trash with inventory checks and no active
Dev session; the app-scoped permission reset returned 0. Production permissions, data, settings and
credentials were untouched. This cleanup does not supply installed acceptance.

# Historical combined validation recovery — October 28, 2026

The clean `dafe4fa` combined full run failed one largest-text speaker UI method before its editor
opened; Core and iOS units passed, while Mac/Watch/server stages were not reached. Raw results and
the exact source audit are preserved. An unchanged focused pass exposed flaky implicit scrolling.
The corrected test reveals the same original speaker before pressing it and keeps all assertions.

Rendered inspection also found a real saved-audio header layout defect at AX5. After six native
layout failures, the iOS accessibility player now stacks its labels and keeps time on a separate
line; standard iOS/Mac layouts and audio behavior are unchanged. Final three-method focused runs
passed on both iPhone and iPad; harness/metric failures remain separately recorded.
[Evidence and limits](saved-audio-accessibility.md). The later full pass is recorded above; exact-head
CI, installed acceptance and merge remain separate. No version bump or publication is claimed.

# Translation caption legibility #346 — local implementation, October 28, 2026

Essential translation guidance/status now uses native primary foreground without changing copy,
layout, providers or state. The same two iOS contrast methods passed after genuine rendered red;
the supported Mac supplement passed one method/four renders. Initial UI scroll-owner and Mac
high-contrast propagation failures remain distinct and preserved. Five existing iPhone UI methods and three selected iPad methods passed with unchanged 1,002-file
inputs, including wide/Duo and largest-text controls. [Evidence and scope](translation-legibility.md).
The combined full pass on `02205d2` is recorded above; required CI, final review and merge remain
pending.
No version bump, binary publication, physical-device or VoiceOver acceptance is claimed.

# Speaker rename integration with audio-feed #348 — October 28, 2026

This local integration merges PR #318 candidate `78b4fda2dbfaf65a1b36259eaaac6d13c2cd4dd7`
into the preserved speaker-rename branch at `5074d0c4d1e9e3769a3ddf622d9a8cd364732e9c`.
The #334 and #348 unreleased notes and both source-specific evidence histories are retained.
Only CHANGELOG and this handoff required conflict resolution; application/test auto-merges are
unchanged. No new combined validation, hosted CI, installed acceptance, PR or publication is claimed.
Fresh combined checks and the pending installed Mac/VoiceOver/relaunch/audio gates still apply.

# Mac PR #318: full automated validation passed on 78b4fda — October 28, 2026

The full `make validate-local` run on exact source
`78b4fda2dbfaf65a1b36259eaaac6d13c2cd4dd7` passed with exit 0 and its owned child reaped at
**2026-10-29 02:15:40 UTC** (October 28 Toronto time). Independent audit matched all **984** frozen
inputs, reconciled the three native result summaries, and observed all **497** required Core/native
BDD bindings passing across **178** structurally valid scenarios.
[Exact source-bound validation receipt](releases/mac-candidate-78b4fda-validation.json).

Core: **1,266 tests / 7 optional skips / zero failures / 98.2004% line coverage**. iOS: **508 unit +
83 UI tests**, with **579 passes / 12 optional skips / zero failures**. Mac: **78 passed**. Watch:
**29 unit + 5 UI passed**, no skips. The six helper suites, hotkey regression and four real-server
contracts passed. All three required hosted checks passed on the same source in
[CI run 40800868710](https://github.com/tomqwu/ListenToMe/actions/runs/40800868710).
The native Mac synthetic Chinese-translation branch also passed; this is not physical-phone or
installed-app GUI/audio acceptance. Raw iOS/Mac/Watch result bundles were preserved externally and
all **1,768 files** byte-verified. The owned build/test jobs ended; no simulator was deleted by the audit.

Installed acceptance remains incomplete. The last resumed `b0b27c0` signed Dev session had an active
microphone but system audio unavailable with ScreenCaptureKit **-3801**, zero transcript lines and
no acceptance fixture played. Recovery required Touch ID/password and was cancelled before app
selection; settings were restored and exact Dev-only cleanup completed. That is an OS-authentication
blocker, not a current locked-Mac diagnosis. Actual OTHERS/near-end/overlap/repeated speech, route/
headphone/recovery/playback and affected #348 installed file-import/re-transcription checks remain
pending, along with physical phone/Watch and Apple-distributed Mac installation acceptance.

The maintainer's standing authorization now directs App Store review submission whenever each iOS
or macOS version meets production readiness; [the canonical gates](../AGENTS.md#official-app-store-review-and-public-release)
still apply. No submission, manual public release or release-mode change follows from this docs-only
update. Documentation head `c347066` also passed all three required checks in
[CI run 40806385369](https://github.com/tomqwu/ListenToMe/actions/runs/40806385369). PR #318 remains
unmerged and unpublished. Its source does not include the local #346 implementation recorded above.

# Historical Mac PR #318: audio-feed #348 candidate — October 28, 2026

That candidate includes an unreleased shared saved-audio EOF fix. A faithful Int16-on-disk
fixture reproduced 804 missing frames with one native method failing 65 assertions; the exact
four-method Mac suite passed after the fix. Supplemental Int16 timeline/Stop and Float32 bypass
coverage passed all four methods on Mac and all four on iOS simulator. The earlier Float32-only
four-method pass is a baseline, not a red. [Scope and evidence](audio-file-feed-tail.md).
At this focused checkpoint, full validation and exact-source CI were pending; the later `78b4fda`
result is recorded above. The earlier `b0b27c0` pass remains separate historical source evidence.

Resumed installed `b0b27c0` Dev acceptance remains incomplete: microphone active, system audio
unavailable with ScreenCaptureKit -3801, zero transcript lines and no acceptance fixture played.
System Settings required Touch ID/password before app selection; that attempt was cancelled
without changing its toggles. Stop returned both channels stopped. The exact Dev bundle was moved
to Trash and only its Dev TCC permissions reset; saved settings were restored and production
permissions/data were untouched. The Mac is unlocked; OS authentication and actual OTHERS/route/audio
acceptance gates remain open; do not request repeat acceptance or infer it from automated tests.
No merge, new archive/upload, release or production-ready claim is made here.

# Historical Mac PR #318 automated recovery on b0b27c0 — October 28, 2026

Fresh `make validate-local` on exact source `b0b27c0b5cc49fb63f7d808b02c0e36bea1acd34` completed
with exit 0 and its owned child reaped at **2026-10-29 00:14:17 UTC** (October 28 local time).
The independent terminal audit checked all 975 pinned inputs with no hash mismatches and reconciled
the logs with all three native result summaries. [Exact audit receipt](releases/mac-candidate-b0b27c0-validation.json).
Core: 1,266 tests / 7 skips / zero failures / **98.2003739482705%** line coverage. iOS: 504 unit +
83 UI tests, **575 passed / 12 optional skips / zero failures**. Mac: 74 passed. Watch: 29 unit +
5 UI passed, no skips. All 174 BDD scenarios were structurally valid and every required Core/native binding was observed
passing; six helper suites, the hotkey regression and four real-server contracts passed. All three required hosted
checks passed on the same source ([run 40788007120](https://github.com/tomqwu/ListenToMe/actions/runs/40788007120)).

The native Mac suite also observed the real installed English-to-Simplified-Chinese model branch;
that synthetic inference result is not physical-phone or installed-app GUI acceptance. The earlier
`02528bf` aggregate remains **failed**, with its receipt and raw evidence preserved; this is a new
full pass, not a relabeling of that run. [Recovery details](validation-pipeline-recovery.md).

At that automated-recovery checkpoint, the Mac was locked. Prior signed Dev-sandbox GUI evidence remains scoped to `02528bf` and
its recorded binary/signature. Independent near-end/overlap/repeated speech, routes/headphones,
Stop recovery and delayed-line audio playback remain pending. Apple-distributed Mac Store installation
and physical phone/Watch acceptance are unverified. Automated source validation does not make a
Store artifact production-ready. PR #318 is not merged or published by this update; these docs-only
changes still need review and hosted CI. No new archive, upload or release is claimed.

# Historical first Mac PR #318 integration attempt — October 28, 2026

The existing draft integrates `main` at `6362853` in `02528bf`, preserving published iOS 1.20.2 (42)
translation recovery/recording continuity with the Mac sandbox/audio/transcript fixes. All three
hosted checks passed on that source. Its full local run **failed**: one iOS Save-to-folder UI method
had three assertions; the outer wrapper rejected the run even though GNU make 3.81 incorrectly
returned zero after the piped native failure. All 970 frozen inputs match the source. The
[independent failure receipt](releases/mac-candidate-02528bf-failed-validation.json) records each
component result separately, including the later passing Mac, Watch and real-server stages.

The subsequent correction fixes make's failure propagation (#347) and the native Settings test's
visibility/query defects. Genuine red/green evidence and independent review are retained; the fresh
full run on `b0b27c0` passed as recorded above. [Recovery evidence](validation-pipeline-recovery.md).
No earlier passing run is promoted to acceptance for this source.

Installed signed Dev-sandbox checks on `02528bf` now cover #337's double-click, Copy, accessibility/
context editing, Save/Cancel and narrow/wide reflow, plus real English-to-Simplified-Chinese Summary
translation. [Bounded receipt](releases/mac-candidate-02528bf-installed.json). Independent near-end,
overlap/repeated speech, physical routes/headphones, Stop during recovery and delayed-line audio
playback remain incomplete for #336. The completed Dev session was archived, stopped and cleaned
with only the exact Dev permission scope. No merge, new Mac upload or publication is claimed.

The preserved #334 branch is integrated with this source; independent review found its Watch-speaker
fixture missing scene lifecycle and a rotation test that did not establish real Duo. Observable
regressions were prepared; native red and the fixture correction were then pending behind #318.
The later source-specific speaker results below record their completion without claiming a combined full pass.
The requested Impeccable audit also recorded a scoped light-mode translation-caption legibility
finding as #346, with native resolved-color acceptance still required before a fix is claimed.

# Historical speaker rename focused integration evidence — October 28, 2026

At this focused checkpoint, the preserved `codex/speaker-rename-gestures` branch integrated local PR #318 candidate `02528bf`
at base `6705543054c481d556b4c3faadb25d2e0601a4c1`. The new focused results are **base plus the
three retained dirty fixture/test/scenario hashes**, not clean `6705543` acceptance.
[Source-bound receipt](releases/speaker-rename-6705543-readiness.json).

Two native UI methods reproduced four assertions: cold speaker readiness stayed stale and the
rotation journey did not establish actual Duo. Attaching the existing production lifecycle bridge
to the DEBUG simulator fixture fixed those outcomes; the same two tests and scenario then passed
unchanged. Only the fixture changed between the red and green runs. Independent review inspected
the failure and all three green originals: ready portrait, actual side-by-side Duo and renamed Sam.
These are synthetic QA captures, not listing or physical/model-quality acceptance.

A subsequent related run passed all **six methods**, zero skips/failures (including the same two,
not six additional tests). It covers largest-text actions, Save/Cancel and identity isolation,
speaker opt-out/re-enable, Watch-labelled Notes and saved-audio Play/Pause/Share controls. Those
controls do not prove audible playback quality or paired Watch transfer. Each run retained 978 input
hashes with no run-time mismatches. The prior structural checkpoint passed 174 BDD scenarios and
lint/content checks; no new full-validation result is claimed for this dirty source.

Rename release notes remain under Unreleased. This is a fixture lifecycle repair, not a new public
feature or release. PR #318 keeps priority; no #334 PR, commit/push, merge or publication is claimed
by this evidence update. Final integration/full validation, current-source CI, installed Mac
sheet/gesture acceptance, VoiceOver and disk persistence across relaunch remain pending.
Earlier source-specific results remain below.

# Historical speaker and transcript gesture integration — October 28, 2026

At this earlier checkpoint, the speaker-rename branch integrated PR #318's validated transcript candidate
`a1eb0fb` (app/test source `d525760`). Both unreleased feature histories are retained. Native
integration checks distinguish a speaker-label double-click from a transcript-word double-click:
only the intended name sheet or line editor opens, and Escape cancels naming without changing
name or text. All nine focused Mac tests pass (exit 0); BDD151 and lint pass. These are additional
integration checks, not invented historical reds. The first invocation used an invalid test-target
selector; a second assumed SwiftUI's Cancel was an NSButton. Both harness failures are preserved.

Evidence is under `2026-10-28/listentome-speaker334-edit337`. Native sheet bitmap capture omits button
labels and is diagnostic only; it does not prove installed UI presentation. Fresh full combined
validation, installed gesture/Copy/name-sheet acceptance and CI remain. Do not open the #334 PR
before #318 completes its remaining installed audio/interaction gates. No feature release is claimed.

# Published translation-recovery beta — 1.20.2 (42)

Apple accepted **1.20.2 (42)** through the official TestFlight helper at **2026-10-28T21:11:37.664213+00:00** from `a6b90e83f775cc9dc88df3c2805ecacedca044af`. Apple build `8967f095-470f-40c0-aba0-b1188bbb699c` is **VALID / IN_BETA_TESTING**. Readback at 2026-10-28T21:15:33.796221+00:00 confirms **en-US**, **Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for the existing two-member Dev group. Access does not establish physical installation of build 42.

[Publication receipt](releases/ios-1.20.2-build42.json) · [Release notes and native previews](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.2-build42).

Physical phone translation/lock-screen/multilingual and Watch acceptance remain pending. Public production remains **1.19.1 (39)**; this beta made no new public submission or listing-media upload. Mac changes remain unreleased and keep separate installed-app acceptance gates.

# Historical candidate verification before publication — #343, 1.20.2 (42)

The tester-reported Summary translation stall is being addressed on `codex/translation-stall-recovery`.
The candidate adds native cancellation ownership, bounded readiness/inference deadlines, disabled
busy/draining controls, Cancel translation, late-result/timer fencing and real installed-pair Mac
acceptance. [Evidence and limits](translation-recovery.md). The exact underlying iPhone framework
stall is not yet identified; physical phone and installed Mac GUI acceptance remain unverified.

Focused Core/native/UI red→green evidence is retained; full local validation now passed on unchanged `abe5218f61c193421178a2debab16ea2c2b1b2dc`. [Validation receipt](releases/ios-1.20.2-build42-validation.json) and [fresh screenshots](images/ios/release-1.20.2-en-US.json) cover seven profiles. Hosted CI, merge and the tester-feedback TestFlight train remain separate gates. All three iOS bundles and in-app notes
are prepared for 1.20.2 (42), with en-US metadata. Apple's preflight at 19:54 UTC found no build42;
public iOS remains1.19.1 (39) and latest accepted beta remains1.20.1 (41). No upload or public
submission is claimed by this candidate. Preserve the unrelated unfinished Mac318/speaker334 work.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-28/listentome-translation-recovery/`.

# Published recording-continuity beta — 1.20.1 (41)

Apple accepted **1.20.1 (41)** through the official TestFlight helper (receipt recorded 2026-10-28T19:02:09.198475+00:00) from `dc6b2e39a99568fb4931e937c555fa0de0f2ff18`. Apple build `5c2339eb-5e17-4bd6-8eb1-ec1d212ef49f` is **VALID / IN_BETA_TESTING**. Existing Dev group access was verified at 2026-10-28T19:05:58.417288+00:00; its two accepted memberships are unchanged. Primary locale and metadata are **en-US**, with localized name **Listen To Me - Real Time AI**; beta description and What to Test match the intended copy. Group access does not establish physical installation of build 41.

The beta includes established microphone capture through screen lock, replay recovery and foreground
readiness fixes. Full local validation used `9b14ff2ea58919c1bf42a3482794ccd4877dbf1a`;
the merged artifact/tag source is `dc6b2e39a99568fb4931e937c555fa0de0f2ff18`. All three required checks
passed on that exact merged source ([run 40748287376](https://github.com/tomqwu/ListenToMe/actions/runs/40748287376)).
The actual transported IPA, all three distribution bundles and remote tag were verified. The GitHub
pre-release leaves the Mac release Latest; all six preview downloads match their uploaded originals.
[Publication receipt](releases/ios-1.20.1-build41.json), [validation receipt](releases/ios-1.20.1-build41-validation.json)
and [75 reviewed captures](images/ios/release-1.20.1-en-US.json).

Physical screen-lock capture, multilingual/translation quality and Watch acceptance remain pending.
Public iOS remains 1.19.1 (39); no new public submission or listing upload was performed.
The Mac release and remaining backlog keep their separate acceptance gates.

# Historical candidate verification before publication — 1.20.1 (41)

The recording/language follow-up implements continued user-started capture through backgrounding,
replay progress/recovery, immediate cancellation of optional work and refreshed foreground controls.
Full `make validate-local` passed on exact source `9b14ff2ea58919c1bf42a3482794ccd4877dbf1a` with all 921 tracked
inputs unchanged. Core: 1254 tests, 7 optional skips,
zero failures and 98.17549956559513% line coverage. iOS UI 82 tests / 5 skips / 0 failures; iOS unit 499 tests / 7 skips / 0 failures; Mac native 43 tests / 0 skips / 0 failures; Watch unit 29 tests / 0 skips / 0 failures; Watch UI 5 tests / 0 skips / 0 failures.
All 153 BDD scenarios were structurally valid; every bound native selector was
observed passing. Four helper suites and 4 real-server contracts passed.
These are local automated results, separate from installed/physical acceptance.

Fresh candidate media is preserved across 7 profiles and 75 native-resolution images, with source/binary/payload hashes and explicit reviewed listing/QA classifications. Saved media does not update Apple's listing. [Capture catalog](images/ios/release-1.20.1-en-US.json).

[Validation receipt](releases/ios-1.20.1-build41-validation.json). All three hosted checks passed on the
validated application source ([run 40737628646](https://github.com/tomqwu/ListenToMe/actions/runs/40737628646));
this final evidence-only commit still requires its own checks before merge. The 75 images include
two supplemental Duo captures from an unchanged existing layout test; 30 are suitable compositions
and 45 are QA-only. Watch previews remain scoped to GitHub, not App Store approval.

Earlier failed aggregates, unchanged-source reproductions, superseded privacy expectations and the
corrected title-query failure remain preserved. The focused 14-method UI attempt passed 13 methods
and failed the new title query; only that selector changed before its isolated passing retry. The
final aggregate above reran the complete final source. [Recording evidence](recording-continuity.md)
and [language evidence](language-replay-progress.md) retain the earlier red/green boundaries.

All phone/Share/Watch targets and bundled notes identify **1.20.1 (41)**. Physical screen-lock audio,
native multilingual accuracy and Watch acceptance remain pending; this candidate is not a production
acceptance claim. Build 41 upload, tester availability and GitHub release status require separate
accepted receipts; no upload or public App Store submission is asserted by this validation snapshot.
Hosted checks, merge and authorized distribution are recorded separately by the release owner.

Release evidence: `/Users/tomwu/Documents/Codex/2026-10-28/listentome-ios1201-continuity`.
The other preserved Mac/Watch/research backlog remains independently gated.

# Published translation beta — 1.20.0 (40)

Apple accepted **1.20.0 (40)** through the official TestFlight helper (receipt recorded 2026-10-28T13:56:43.061187+00:00) from `4a72489120fda713c6d117c3d6c3dc661cf1dd9e`. Apple build `93926f6c-0137-49fe-bc06-f73f04f831f5` is **VALID / IN_BETA_TESTING**, with existing Dev group access verified at 2026-10-28T14:06:21.847671+00:00. English (US) localized name, beta description and What to Test match the intended metadata. Group membership does not establish physical installation of build 40.

Physical phone/Watch acceptance and installed real-language-pair translation quality remain pending. The Mac translation feature remains unreleased. Public production remains 1.19.1 (39); this beta did not submit a new public version or upload listing screenshots. QA-only captures are not approved store assets.

Full local validation ran on unchanged `e43a7b5c241e4a58d806f42651dc760d996951be`; the merged artifact source is `4a72489120fda713c6d117c3d6c3dc661cf1dd9e`. [Publication receipt](releases/ios-1.20.0-build40.json), [validation receipt](releases/ios-1.20.0-build40-validation.json) and [reviewed capture catalog](images/ios/release-1.20.0-en-US.json). The preparation checkpoint below is historical, not current pending upload work.

# Historical iOS translation train preparation — October 28, 2026

The next-day authorized TestFlight train is being prepared from merged `main` (`6ecf9cb`), separately
from unfinished Mac #318 and speaker rename #334. Apple readback confirms latest accepted build39,
public iOS1.19.1, primary locale en-US, and no build40 among all35 returned builds. The planned beta
is **1.20.0 (40)**, with matching phone/Share/Watch versions, bundled translation What's New and
complete US tester/release copy. No new public App Store version or review submission is authorized.

`RELEASE-004` first failed the native UI version/title expectations against build39 (two assertions,
exit65). Version and bundled notes now match40; all six focused release-notes/translation UI tests passed
(exit0), including largest-text history and translation controls. BDD139 and lint also pass.
The release branch also adopts the already reviewed large-text translation scrolling-test correction
from `a1eb0fb`, without unmerged Mac behavior or speaker-renaming changes. That earlier regression
and its evidence remain documented separately; no new historical red is invented for the backport.

Full `make validate-local` passed on unchanged `e43a7b5`: Core1,254 (7 optional skips,
98.221766% coverage), iOS79 UI (5 skips) +460 unit (7 skips), Mac43, Watch29 unit +5 UI,
139 BDD scenarios, all required native bindings observed passing, and four real-server contracts. All three hosted checks passed.
[Validation receipt](releases/ios-1.20.0-build40-validation.json) and
[55 reviewed captures](images/ios/release-1.20.0-en-US.json) preserve seven device profiles.
Two Watch42 setup failures remain preserved; the unchanged prebooted run passed.
Poorly scrolled captures are QA-only; no listing upload or physical acceptance is claimed.
Merge, exact-source archive/export verification, helper upload and Apple tester readback remain. Existing manual export settings use
`destination=upload`; local package verification must use a separate private `destination=export`
copy. Evidence: `2026-10-28/listentome-ios120-train/`. Physical translation quality and Watch/phone
acceptance remain unverified; this preparation does not publish a build or waive Mac acceptance.

# Historical Mac transcript candidate validation — October 28, 2026, 05:08 UTC

PR #318 source `d525760` passed the complete `make validate-local` command: exit 0, reaped,
2,851.15 seconds and all 934 tracked input hashes unchanged. All three required hosted checks
passed on that source. Independent review verified Core 1,262 tests/7 skips/98.2376439% coverage;
iOS 79 UI/5 skips and 461 unit/7 skips; Mac 69; Watch 29 unit/5 UI; all native bindings and four
real-server contracts. Xcode's Watch diagnostic collection delayed completion but returned normally.
[Audited receipt](releases/mac-candidate-d525760-validation.json). Installed #337 interaction and
remaining #336 real-audio acceptance still prevent merge. No new release is claimed.

A separate read-only Apple check confirms that public iOS 1.19.1 (39) retains all 60 processed
screenshots in 10 sets with matching IDs, order and checksums, including US Watch and Duo images.
[Media readback](releases/ios-1.19.1-build39-media-readback.json). This verifies App Store Connect
association; downloaded image identity comes from the earlier upload receipt, and fresh public
storefront rendering was not inspected. No upload or review mutation occurred.

# Transcript editing regression — October 28, 2026

Installed #336 acceptance exposed [#337](https://github.com/tomqwu/ListenToMe/issues/337):
double-clicking selectable transcript text selected a word instead of opening the editor. The
candidate now gives selection and editing to one native text control. Four production-row tests
pass, including actual glyph clicks, partial refusal, Copy/accessibility and multiline/CJK resize
with selection preservation. Independent review cleared the code and inspected both captures.
BDD149, lint and a strictly signed sandbox build passed; full validation and CI subsequently passed
on `d525760`, as recorded above.
Native automation reported the Mac locked before installed candidate acceptance. No recording,
permission changes, new installed pass, merge or release is claimed. Preserve the candidate and
continue PR #318 before opening #334. [Evidence and remaining gates](transcript-interaction.md).

# Full validation completed — October 28, 2026, 02:35 UTC

PR #318 app/test source `95aaeaf` passed the complete `make validate-local` command: exit 0,
child reaped, 2,237.75 seconds and all 929 tracked input hashes unchanged. Independent outcome
review verified Core 1,262 tests/7 skips/98.2376439% coverage; iOS 79 UI/5 skips and 461 unit/7 skips;
Mac 65; Watch 29 unit plus 5 UI; all native BDD bindings, helper checks and four real-server contracts.
There were no failures. All three hosted checks passed on `95aaeaf`; documentation follow-ups do
not change those tested application inputs. [Audited receipt](releases/mac-candidate-95aaeaf-validation.json).

Remaining #336 installed near-end/overlap/repeated-speech/headphone/route and rendered edit/playback
acceptance still prevents merge; the playback-only pass is insufficient. A later startup attempt
had idle channels, no playback and working Stop; its permission readback and Dev cleanup exception
are preserved in [the audio evidence](dual-channel-capture.md). No new release is claimed.

The queued #223 8B reference screen then stopped before model inference because the slow tokenizer
omitted the published fast tokenizer's terminal end-of-text token. Preserve its failed logs and
frozen protocol; no language-quality result exists. Diagnose and review a separate corrected
protocol before retrying. The #334 branch now includes `95aaeaf` at `e85733b`, with four focused
native integration methods, BDD150 and lint passing plus independent review; fresh full integration
validation and installed rename acceptance remain. No #334 PR is opened ahead of #318.

# Validation follow-up — October 28, 2026

The `086d89e` full validation ended with make exit 2 and unchanged input hashes: Core passed,
iOS unit tests passed (461 with seven skips), but one of 79 iOS UI tests failed after its blind
swipes overscrolled the Translate button at the largest accessibility text size. Mac, Watch and
real-server stages were not reached. A stronger whole-button visibility assertion reproduced the
harness defect; bounded direction-aware scrolling now passes all four translation UI methods and
the largest-text journey on both iPhone and iPad. Screenshots were inspected. This changes tests,
not translation behavior; [the evidence record](translation-validation.md) preserves both failures.
Fresh full validation and exact-source CI remain required. Mac #336 still needs its independent
near-end/overlap/headphone/route and rendered delayed-line edit/playback acceptance before merge.
The separate #223 model scheduler correctly refused to start after the failed aggregate; no
inference or added-language support is claimed. Continue PR #318 before opening #334.

# Public iOS availability — October 28, 2026, 01:12 UTC

Apple's live version readback and independent US public lookup now confirm **iOS 1.19.1 (39)** is
publicly available, released at **2026-10-28T00:12:55Z**, with primary locale **en-US**. This is the
previously accepted Watch-enabled build 39 from `f1728150e3e66664e36d2506022c2918fa60a53c`.
The exact Apple build ID and peeled tag match the upload receipt. See the
[public observation](releases/ios-1.19.1-build39-public.json). No new upload, submission or release
operation was performed for this readback. Physical Watch/phone acceptance remains unverified;
public availability does not retroactively establish it. Mac 1.5.0 remains an unsubmitted draft
with no selected build. Older draft and beta checkpoints below are historical.

# Mac dual-channel regression — October 27, 2026

[#336](https://github.com/tomqwu/ListenToMe/issues/336) reproduced duplicate YOU/OTHERS playback and
out-of-order timestamps during PR #318 acceptance. The current candidate adds chronological
presentation with persistent run identity and native microphone echo control. Focused red/green
coverage and independent review are recorded in [the evidence note](dual-channel-capture.md).
A signed Studio Display playback check now yields all five Orion sentences as OTHERS with zero
YOU finals and working Stop. Independent near-end/overlap/headphone/route-change acceptance,
rendered delayed-line edit/playback and fresh full validation/CI/merge remain. This does not close
#336 or establish a production-ready Mac build. Keep working in PR #318 before opening #334.
The completed Dev sessions were archived and moved to Trash, only `.dev` permissions reset, and
prior provider/engine/speaker/saving preferences restored. User history and API keys remain intact.

# Mac import finalization regression — October 27, 2026

Installed sandbox acceptance on validated source `44d8765` passed native export and Calendar lookup,
and actual French live translation retained the English original. Import exposed [#335](https://github.com/tomqwu/ListenToMe/issues/335):
unused prepared SpeechAnalyzer channels left Finalizing/Stopping active. The native BDD regression
reproduces the timeout, and the corrected lifecycle passes real first/final words, source/time and
zero-input/cancellation cases. See [native speech lifecycle evidence](speech-input-timing.md).
A success-status assertion also passed before the defensive cancellation-error suppression; it is
additional coverage, not a fabricated red. Required review, fresh full validation and corrected
installed control/audio acceptance remain; no new merge/upload/publication is claimed.

Speaker rename [#334](https://github.com/tomqwu/ListenToMe/issues/334) is preserved on
`codex/speaker-rename-gestures` at `df2b24f`, app/test source `8d335e4`. Its complete local validation
passed (1,254 Core tests, 542 iOS tests including 12 skips, 47 Mac tests, 34 Watch tests and four
real-server contracts). Installed Mac editor/accessibility acceptance, CI/merge and release remain.
Finish current PR #318 before opening that feature PR; do not rebuild the feature from scratch.

# Mac SpeechAnalyzer regression during acceptance — October 27, 2026

Installed SandboxAcceptance source `7f8e00f` opened with the existing stable Dev signature and
verified sandbox entitlements. Real external folder selection plus a local-model request read its
unique synthetic token; a recreated vault writer updated the same note after app relaunch, with no
duplicate. No complete sandbox acceptance is claimed: recording exposed
[#333](https://github.com/tomqwu/ListenToMe/issues/333), a native SpeechAnalyzer timestamp-overlap
failure while both channels were active. Stop worked; no audio fixture had been played.

The [timing correction](speech-input-timing.md) now uses separate raw and exact converted clocks,
with bound native conversion/frame/gap/cancellation tests. The valid native regression produced
eleven failures; tiny valid input separately reproduced conversionFailed; a separate replay of the earlier cancelled-converter guard produced two. Harness
format/isolation/pointer-lifetime failures remain separately preserved. The `7f8e00f` aggregate was
stopped/reaped before the necessary source fix, unchanged/clean with all 917 file hashes matching;
it remains incomplete. Fresh corrected-source full validation and installed audio acceptance are
still required. PR #318 remains the single feature draft; #333 will close through that PR only
when its gates pass. No new upload/review, production-ready claim or permission reset.

# Mac Store sandbox acceptance — October 27, 2026

Existing draft [PR #318](https://github.com/tomqwu/ListenToMe/pull/318) now integrates current main,
including translation and the canonical distribution instructions. Source `8067048` archived and
exported a universal, strictly signed 1.5.0 (15) Store package; profile, entitlements and en-US
checks passed. Direct local launch failed with taskgated/amfid **No matching profile found**.
That is a preserved provisioning failure, not a permission failure or an installed acceptance pass.

A separate `SandboxAcceptance` configuration retains release optimization and the Store's public
sandbox entitlements under the existing `.dev` identity. `RELEASE-014` reproduced missing settings/
build guidance before implementation; generated settings and the no-signing early-exit tests now
pass. Native Mac UI is accessible again, but actual sandbox picker/relaunch/audio acceptance is
still pending. The first new aggregate was deliberately stopped/reaped on unchanged `8067048`
before this necessary configuration change; it remains incomplete, not a pass.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-27/listentome-mac318-acceptance/`. A fresh full
validation, installed Dev sandbox checks, required CI and merge remain. Rebuild the distribution
artifact from the exact final merged source before upload. No new Mac upload/review submission,
production-ready claim or permission reset occurred. See [local sandbox acceptance](RELEASING.md#local-sandbox-acceptance).

# Translation #330 implementation — October 27, 2026

[PR #331](https://github.com/tomqwu/ListenToMe/pull/331) adds opt-in on-device live translation and
an explicit **Translate summary** option on the existing Summary page, with independent targets and
originals retained. No summary-generation language override, version bump, upload or production
submission. The feature is absent from published TestFlight 1.19.1 (39).

[Validation evidence](translation-validation.md) records the frozen source, complete passing local
component matrix and three green hosted checks. The aggregate command exited at a torn Mac log
record; a complete Mac rerun and the remaining stages passed without source changes. Installed Mac
interaction, physical acceptance and real installed-pair translation quality remain unverified.
The [feature guide](translation.md) covers usage, privacy and compatibility. The dated release
snapshot below still identifies published builds; see the PR for current merge status.

# Handoff — 2026-10-27

A snapshot for an agent picking up ListenToMe cold. [AGENTS.md](../AGENTS.md) and
[CLAUDE.md](../CLAUDE.md) stay the rules; this note is only the state of things on the date above.
Re-check anything time-sensitive (`gh issue list --state open`, `git log`, tags) before acting on it.

## Watch and Duo listing media correction — October 27

The [1.19.1 App Store draft media receipt](releases/ios-1.19.1-build39-media.json) records **60 COMPLETE screenshots**: 30 each in en-US and the preserved en-CA localization. Each locale has seven fresh images for each of four iPhone/iPad display sizes, including both iPhone landscape two-pane Duo views and iPad wide views, plus two consistent 422 × 514 Watch Ultra home/recording images. Apple source checksums, native dimensions, exact set membership/order and downloaded RGB identity all match. Old inherited draft copies were backed up and removed only after ownership/disjointness checks; public 1.18.1 screenshot sets remain unchanged.

Draft **1.19.1** selects accepted build **39** and remains **PREPARE_FOR_SUBMISSION** with manual release. Description and What's New were read back in both English locales; the draft now describes its embedded Watch companion. No review submission occurred. Physical Watch/phone acceptance remains pending. Six native Watch/Duo/iPad previews are also visible on the [TestFlight GitHub release page](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.1-build39); all six uploaded PNGs were downloaded again and SHA-256 matched. App source and accepted beta build are unchanged.

## Published Watch regression beta — 1.19.1 (39), October 27

Apple accepted **1.19.1 (39)** from `f1728150e3e66664e36d2506022c2918fa60a53c`: Xcode upload success at **2026-10-27 15:39:29.401 UTC**, Apple uploaded date **2026-10-27 15:40:24 UTC**. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing internal Dev group includes build 39 with two existing active/installed tester members. This does not prove physical installation of build 39. Primary locale, localized name, beta description and What to Test were read back in **en-US**, with name **Listen To Me - Real Time AI**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.1-build39).

Full local validation and independent review passed on unchanged app/test inputs: 125 BDD scenarios; Core 1,239 tests (7 optional skips, 98.249328% coverage); iOS 531 (519 passes, 12 skips); Mac 39; Watch 34; 29 helper tests and four real-server contracts, zero failures. All three required checks passed on exact merged source before upload. The exact transferred IPA was recovered, its full-file transport MD5 matched, its preserved copy SHA-256 matched, and all three distribution signatures/profiles, versions, disabled debugging and no-test-payload checks passed. Complete physical phone/Watch acceptance remains unverified; this is an authorized beta, not a production-ready claim.

**Distribution procedure correction:** an existing private plist with `destination=upload` was passed to direct Xcode export, which uploaded this build. Actual upload was **not** performed by the helper; the later helper dry run is not upload evidence. No duplicate upload was sent. Package verification was completed after acceptance, and the receipt preserves that order. Future local export must use a private copy with `destination=export`; use the official make target for actual upload.

[Receipt](releases/ios-1.19.1-build39.json), [49-image catalog](images/ios/release-1.19.1-en-US.json), and four [approved Watch previews](images/watch/1.19.1/README.md). All active images were inspected, with 32 approved and 17 Watch QA-only; a banner-obscured ProMax menu original was rejected, retained and replaced by a clean same-source retake. The beta upload did not update listing screenshots; the subsequent draft-media correction is recorded above. No production submission occurred. Public iOS remains 1.18.1; Mac draft #318 is separate.

PR #327 merged and #326 closed. Physical Watch wrist-down/paired transfer/battery/storage acceptance remains #181. The first corrected phone run no longer crashed and six tests passed, but a short speaker fixture assertion failed; the corrected full physical repeat was not completed. Simulator 26.5 and phone 27.0.1 differ in runtime and device. Original reports, all failed/interrupted attempts, all three raw native results, exact IPA and logs are preserved externally in `listentome-watch-recording-regressions/`.

Cleanup is complete: exact inactive `.dev` bundle archived/hash-verified then moved to Trash; only `.dev` TCC reset. Isolated iPhone probe uninstalled; seven owned simulators removed, 38 other IDs preserved. Production apps, conversations/settings/keys and login keychain were untouched.

## Historical candidate — 1.19.1 (39) candidate, October 27

PR #327 fixes #326 on reviewed source `0020345752a1ace9c28647bf9d45da310f862b18`. Three actual build-38 reports from the connected iPhone 17 Pro Max/iOS 27.0.1 and a matching archived dSYM identify `WatchLanguageAudio.samples`/`ChunkFeed`. An isolated signed host reproduced Speech's signed-16-bit precondition with stock AAC. Optional language/speaker analysis now receives PCM directly; only negotiated transcription constructs Speech inputs. No production app was replaced and no private audio was copied.

`WATCH-015`/`WATCH-016` and `RELEASE-004` preserve real red/green evidence, source preservation/cancellation, exactly-once Stop, actual system Close/elapsed progression and current notes. Full `make validate-local` passed on this exact source: 125 BDD scenarios, Core 1,239 tests (7 skips, 98.249328% coverage), iOS 531 (519 passes, 12 skips), Mac 39, Watch 34, 29 helper tests and four real-server contracts, zero failures. Independent source/outcome review cleared and all three required CI checks passed ([run40522116583](https://github.com/tomqwu/ListenToMe/actions/runs/40522116583)). Earlier Busy, interrupted, selector and short-fixture attempts remain failed/incomplete.

[Fresh en-US catalog](images/ios/release-1.19.1-en-US.json): 49 inspected active images across four iPhone/iPad and three Watch categories, with source/native resolution/hash provenance. Four [Watch previews](images/watch/1.19.1/README.md) are approved candidates; 17 Watch diagnostics are QA-only. A banner-obscured Pro Max menu image was rejected and replaced by a clean same-source retake; the original remains preserved. No new listing upload occurred.

The first corrected physical run no longer crashed and six tests, including real Speech transcription, passed; one new AAC assertion used a clip shorter than speaker analysis permits. The fixture was corrected, but subsequent physical reruns waited on device lock and were stopped: no complete physical green is claimed. Simulator 26.5 versus phone 27.0.1 differs in both runtime and device; do not generalize this as universally physical-only. Physical Watch wrist-down/paired transfer/battery/storage acceptance remains separate in #181. Existing safety limits remain.

CI for the documentation/media follow-up, merge and accepted TestFlight distribution are pending. Current published beta remains 1.19.0 (38). Mac draft #318 stays separate. Complete raw native results, reports, screenshots, source/signing inputs and review evidence are preserved under external `listentome-watch-recording-regressions/`.

## Latest Watch-enabled TestFlight — October 27, 08:43 UTC

Apple accepted **1.19.0 (38)** at **2026-10-27T08:31:46.551678+00:00**, from `e43244f752712ac80e179e35c893e967aea38753`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing Dev group includes this build with two accepted testers. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.0-build38).

The exact uploaded IPA checksum matches ContentDelivery’s file checksum. Its phone, Share and Watch signatures/profiles, versions and debug flags passed verification; Apple’s processed nested entitlements independently confirm the Watch executable and distribution identity. The public buildBundles API lists one APP container and nests the Watch evidence inside it, rather than returning a separate WATCH_APP resource.

App source/tag: `e43244f752712ac80e179e35c893e967aea38753`, `ios-v1.19.0-build38`. The manual-signing helper merged separately as `ea2c05febf858065efd611db32dc57d81d523d10` (#324, closes #323); its tree matches validated head `a6bb34c`. All three required checks passed on both exact merged sources. Full local validation passed twice: 122 app-candidate / 123 helper BDD scenarios, 1,239 Core tests (7 optional skips, 98.2493% coverage), iOS 529 total (517 passed, 12 optional skips), 39 Mac tests, 33 Watch tests and four real-server contracts, with no failures. The helper has 29 offline tests. The original archive was reused unchanged; no binary was rebuilt to fix signing.

[Publication receipt](releases/ios-1.19.0-build38.json) and [43-image capture catalog](images/ios/release-1.19.0-en-US.json) preserve source/status/hash evidence. Four approved native [Watch previews](images/watch/1.19.0/README.md) are committed; compact/consent/recovery/offline images remain QA only. Use one accepted Watch size consistently for a future authorized listing. All originals and raw native results remain under the external Watch181 beta directory.

Known working upload route: configured API key plus explicit `IOS_EXPORT_OPTIONS` using `~/.config/listentome/manual-testflight-export.plist` (private local copy of the accepted settings). All three Store profiles are manually managed and use the existing distribution certificate; credentials, keychain and OS permissions were not reset. [Runbook](IOS-RELEASING.md#local-manual-signing-when-automatic-export-cannot-select-profiles).

Physical Watch installation, microphone capture, paired transfer, wrist-down and battery/storage acceptance remain unverified. This is an authorized beta, not a production-ready claim. Public iOS remains 1.18.1; no new public App Store submission or screenshot listing upload was performed by this train. Mac Store draft #318 stays separate.

Completed test-session cleanup: no inactive owned `.dev` bundles remained to move; app-scoped Dev permissions reset successfully after confirming no active Dev session/build. Seven owned simulators were deleted and verified absent, with every other simulator ID preserved. Raw results, all original captures, captured runtime/source inputs and the exact uploaded IPA remain preserved; conversation data, settings and keys were retained.

## Mac Store draft validation — October 27, 13:06 UTC

The existing [PR #318](https://github.com/tomqwu/ListenToMe/pull/318) integrated main
`67ec009a064e5868225a4491f7a684ee54d48872` as **`f8e8b723b2e851b9b480dcccbe0bf6e0e17636f4`**.
It preserves permanent Watch embedding, manual beta-signing safeguards and published en-US evidence,
while adding the separate sandboxed Mac configuration and scoped vault/reference persistence.
Mac scenarios are **RELEASE-010–RELEASE-013**, preserving main's RELEASE-006–RELEASE-009.
Original draft red/green evidence retains its former IDs with the explicit mapping in [BDD.md](BDD.md);
integration/renumbering is not a new regression reproduction.

Fresh **`make validate-local` exited 0** on clean, unchanged `f8e8b723`: **127 BDD contracts**,
Core **1,241 tests / 7 optional skips / 98.2504679% coverage**, iOS **529 total / 517 passes / 12
optional skips**, Mac **42 passes**, Watch **33 passes**, 29 TestFlight-helper and four Mac Store
configuration tests, plus four real Ollama/OpenAI-compatible contracts. Independent review matched
every required native binding to passing records; none was satisfied by a skip. All three required
checks passed on that exact source ([CI](https://github.com/tomqwu/ListenToMe/actions/runs/40502834155)).
This documentation checkpoint changes no application/test input; its own hosted checks remain required.

The current AppStore configuration also compiled for **Intel and Apple silicon**, with actual-product
identity `com.tomwu.ListenToMe.ios`, **1.5.0 (15)** and **en-US** verified. This artifact is unsigned
for distribution (automatic linker ad-hoc signature only), not distribution-signing or installed-app
acceptance. Both compiled architectures, executable hash, unchanged project/dependency lock and
terminal/reaped receipts were independently checked. Full logs, all three hash-verified raw native
result bundles/screenshots, binary/source/runtime provenance and reviews remain under
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-mac318-main-integration/`.

Completed session cleanup: no active Dev app/build was running; the exact `.dev` bundle and signing
provenance were preserved, then that inactive bundle was moved to Trash. Only
`com.tomwu.ListenToMe.dev` permissions were reset, with exit 0. Both owned simulators were deleted and
verified absent, every other simulator ID remained present, and production/Store permissions,
conversation data, settings and keys were preserved. The initial cleanup-helper syntax error ran no
actions and remains external harness evidence; it does not change the successful aggregate result.

The earlier universal signed **1.5.0 (15)** candidate from `c05c6335c182cdff3ec8e6ca6f5bb8829f35a1be`
and package SHA-256 `b16b66ab4c7ca370fd867e98f180d3ad2969d86e4345511d59d4c06cc88b7f47`
remain historical signing/Apple-validation evidence, not an upload receipt or eligible current-source
package. Preserve its original failed aggregate and successful focused resumptions in
`listentome-appstore-publication/locale-mac-correction/`; rebuild from the exact merged source.

**Still pending:** installed sandbox microphone/actual OTHERS capture, external vault/reference
picker grants across quit/relaunch, provider/Calendar/import/export acceptance, fresh Mac screenshots,
source-matched distribution archive and Apple upload/review. Native automation again reports the Mac
locked; no new unlock or permission-repair request was made. Read-only Apple verification at
**13:06 UTC** confirms Mac **1.5.0 PREPARE_FOR_SUBMISSION**, no selected build, iOS **1.18.1 (36)
READY_FOR_SALE**, and primary **en-US**. This draft is not merged or published; Watch-enabled beta
1.19.0 (38) remains separately published. No new public submission or binary release occurred.

## Historical signing recovery — October 27, 07:35 UTC

PR #322 merged at `e43244f752712ac80e179e35c893e967aea38753`, with all three required checks green on the exact merged source. The 1.19.0 (38) archive succeeded. Automatic export failed on the missing Watch Store profile and cloud-signing access; a mixed manual/Xcode-managed export also failed. Separate manually managed Store profiles for all three exact bundle IDs use the existing local Apple Distribution certificate; no certificate rotation, revocation or account/keychain/OS permission change occurred. Manual export of the same archive then succeeded, and all three bundle signatures/profiles, versions, debug flags, phone/Share App Group, Watch embedding and no-test-payload checks passed.

Upload is still pending: the configured helper hardcoded automatic signing. Issue #323 and branch `codex/testflight-manual-signing` add a narrow validated local options input with BDD regression coverage, retaining the automatic default and existing upload safeguards. The archive source stays `e43244f`; later delivery-only helper source and checks are recorded separately. No Watch publication, Apple processing or tester availability is claimed yet. Evidence remains under the Watch181 beta directory and `dist/ios-1.19.0-build38-evidence/`.

## Historical Watch implementation checkpoint — October 27

Branch `codex/watch-beta-distribution` implements explicit Watch beta safeguards and default companion embedding, plus native cancellation/readiness, durable AAC handoff/recovery, end markers, Continue boundaries and pending Delete protection. Focused native Watch tests pass (33 tests, no failures/skips), including the corrected lifecycle review cases with isolated audio/WatchConnectivity adapters and real AAC filesystem operations; helper/generated-project checks pass. Reproduced failures and review-driven fixes are retained externally in `/Users/tomwu/Documents/Codex/2026-10-26/listentome-watch181-beta/`. Independent review found view-owned preparation and pre-execution cancellation gaps after the initial helper/outbox pass. Their genuine native failures and fixes are retained; the final corrected 33-case Watch run passed and the reviewer cleared this delta for commit/full validation.

The first aggregate attempt on `b1f35b4` failed in the native BDD log verifier after 529 iOS tests
(517 passed, 12 optional skips) and all 39 Mac tests passed. A framework stderr message joined one
XCTest pass line, so the old line-start parser missed the selector. `DEV-008` retains the reproducing
failure and exact-selector fix; the original failed run, raw result bundles and no-capture outcome
are preserved under `validation-attempt1/`. All three hosted checks passed on that earlier head;
the corrected-source pass is recorded below. Watch/e2e were not reached by that first aggregate run.

The next source candidate is **1.19.0 (38)**. Its release UI reproduced old 1.18.2 metadata, then passed after the version/notes update. Full `make validate-local` passed on frozen source `016d61c`: 122 BDD scenarios, 1,239 core tests (7 optional skips, 98.2493% coverage), 529 iOS tests (517 passed, 12 optional skips), 39 Mac tests, 33 Watch tests and four real Ollama/OpenAI-compatible contracts; no failures. All three required hosted checks passed on that source. A documentation/media-only follow-up preserves every application and test input; its final CI and merged-source CI remain required.

[Fresh en-US capture catalog](images/ios/release-1.19.0-en-US.json) contains 43 individually inspected native-resolution images: 28 across four iPhone/iPad categories and 15 across Watch Series 12 42/46 mm and Ultra 4 49 mm. Original checksums, RGB equivalence, simulator/test identities and binary/source provenance are preserved externally. Only the approved 46 mm or Ultra Home/Recording images are Watch listing candidates; use one accepted size consistently across locales. The compact 42 mm set and all consent/recovery/offline images are QA only. Offline captures show clock/text overlap and are excluded from listing use. Simulator fixtures do not establish physical microphone or paired transfer acceptance. Store screenshot uploads are pending a separately authorized production submission.

Final documentation review, required CI/merge, distribution signing/export verification and upload/tester receipt remain pending. No Watch beta is published yet. Current TestFlight remains 1.18.2 (37); public iOS remains 1.18.1. [Watch preparation and production gates](watch-beta.md) records physical microphone, paired transfer, wrist-down and battery/storage acceptance as pending. Mac draft #318 stays separate.

## Previous beta — 1.18.2 (37), October 27

Apple accepted **1.18.2 (37)** at **2026-10-27T03:39:12.147449+00:00**, from `9494d024b9eee577b40695292aaf5e7dab9434eb`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and both existing Dev testers have accepted group access. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.2-build37).

Issue #319 is closed by merged PR #320: Full summary now renders the existing Summary icon. Native `IOS-008` retains its zero-pixel failure and passing light/dark runs; opening/dismissing the sheet still does not start recording.

Full local validation passed: 108 BDD scenarios, 1,239 core tests with 98.2493% coverage, 75 iOS UI tests, 454 iOS unit tests, 39 native Mac tests, four Watch tests and four real Ollama/OpenAI-compatible contract tests. Existing optional skips remain documented; all required selectors passed. All three hosted checks passed on the exact merged source ([CI](https://github.com/tomqwu/ListenToMe/actions/runs/40444715802)). The tested source `9425611` and release source `9494d02` have identical trees.

The first aggregate attempt failed in the existing Settings journey and was stopped; it remains a failed/incomplete run. Its unchanged isolated baseline later passed. The reviewed form-margin drag helper preserves all selection/persistence assertions, and the complete fresh retry passed. No deterministic product-regression red is invented.

[Fresh capture catalog](images/ios/release-1.18.2-en-US.json): 28 inspected native en-US images across four iPhone/iPad categories, including four fixed-menu captures. Originals, hashes and source/binary provenance are preserved. These are synthetic simulator captures; 1.18.2 App Store listing uploads remain pending.

Physical-device acceptance was not performed for this beta; it is not a production-ready claim. Public iOS 1.18.1 remains READY_FOR_SALE; 1.18.2 has not been submitted to the public App Store. Watch is excluded and the separate Mac Store draft #318 remains unsubmitted.

Release evidence: `dist/ios-1.18.2-build37-evidence/`, backed up under `/Users/tomwu/Documents/Codex/2026-10-26/listentome-summary-menu-icon/`. The exact-source tag is `ios-v1.18.2-build37`; GitHub pre-release is non-Latest with no binary. The completed Dev-app session was cleaned up: exact `.dev` bundle moved to Trash, only `.dev` permissions reset, conversation data/settings/keys preserved; five owned simulators deleted.

## Earlier US screenshot refresh and App Review — October 26, 21:13 UTC

Apple accepted the refreshed **English (US), en-US** submission at
**2026-10-26T21:13:50.231393+00:00**. Current review
`4e63cda8-70db-4d67-9928-63409df4dbda` and version `c60352d3-eb78-479b-970c-d6ed6faa3242` read back
**WAITING_FOR_REVIEW**, with AFTER_APPROVAL release. This is submission acceptance, not Apple
approval or public availability. The accepted binary remains **1.18.1 (36)**, Apple build
`2fd8477d-504e-44d2-ac7f-6c7e9236d01f`, exact artifact source
`7643b204def6acea0b616a2c2de2bade2fc4c7c9`; no binary was re-uploaded. The US localized name is
**Listen To Me - Real Time AI**. Actual app-wide primary locale remains **en-CA**: Apple again
returned HTTP 409 `MISSING_SCREENSHOTS_PRIMARY_LOCALE` after all fresh US images became COMPLETE.
The en-US localization is submitted; the primary-locale change is not complete.

All **24 fresh US-region screenshots** were explicitly re-uploaded and are COMPLETE: six each on
iPhone 17 Pro, iPhone 17 Pro Max, iPad mini (A17 Pro), and 13-inch iPad Pro (M5). Each native capture
test passed (1 pass, 0 failures, 0 skips per device), every final image was visually inspected, and
processed downloads match the source RGB pixels, native dimensions, MD5s and display order. App/test
binaries were freshly built from the exact artifact source; archived source, generated project and
product hashes were verified before/after every device. The [capture/upload catalog](images/ios/release-1.18.1-en-US-refresh.json)
records every current Apple asset/set ID and receipt. Canadian draft and production assets remain
unchanged; production remains 1.15.0 (32).

The maintainer chose **“Resubmit 1.18.1; save Watch previews separately.”** Prior US review
`89b4c261-b37d-4b24-aaee-20f8238d1663` was canceled and reached COMPLETE before the guarded image
replacement. Every replaced image had hash-verified, decoded/pixel-matched backups; the deletion
allowlist was frozen and disjoint from Canadian/production assets. One fresh image took longer to
process and eventually completed normally. An unused retry reservation was removed after a
fail-closed upload-instruction check; no retry image entered the submitted set. Offline fault
injection verified recovery after deletion/write failure and idempotent completion, with the other
23 rows preserved, plus correct use of reservation-only upload instructions.

[Watch previews](images/watch/1.18.1-preview/README.md) are saved at native resolution for Series 11
46 mm and Ultra 3 49 mm, with source/dimensions/hashes. The installed watchOS 26.5 runtime refused
Series 12/Ultra 4 as incompatible; no model names were substituted. Existing denied-microphone/offline
native UI tests passed on both simulators. Home captures use the normal app, without microphone
recording or physical transfer. **Build 36 excludes Watch**; these are prospective maintainer-review
images, not Watch customer-listing uploads or physical Watch acceptance.

Canonical current evidence is
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-appstore-publication/refresh-us/`:
`app-review-accepted.json`, review/version/name readbacks, all-image pixel/order proofs, primary-locale
rejection, and the combined review ZIP. Use only `screenshots-final/` and
`workspace-build-provenance.json` for the fresh images. Earlier capture attempts are superseded and
retained; no permission changes were made. All dedicated simulators were deleted; no macOS Dev app
session or Dev permission reset applies. PR #315 merged as `597d70a` after its three checks passed
at `49572b1`. Do not resume any canceled earlier review or duplicate-upload build 36.

## Earlier US App Review submission — replaced October 26

Apple accepted the corrected **English (US), `en-US`** submission at
**2026-10-26T20:07:35.298432+00:00**. The US localized name is the maintainer-selected
**Listen To Me - Real Time AI**. Submission `89b4c261-b37d-4b24-aaee-20f8238d1663` and iOS version
`c60352d3-eb78-479b-970c-d6ed6faa3242` read back **WAITING_FOR_REVIEW**, with **AFTER_APPROVAL** release.
This is submission acceptance, not Apple approval or public availability. The build remains
**1.18.1 (36)**, Apple build `2fd8477d-504e-44d2-ac7f-6c7e9236d01f`, artifact source
`7643b204def6acea0b616a2c2de2bade2fc4c7c9`; no binary was re-uploaded.

The earlier Canadian submission `25ae4878-c462-4528-a48e-01b12b028f39` was canceled and is COMPLETE.
Apple rejected both **Listen To Me** and **ListenToMe** in the US locale as names used by another
account. The maintainer supplied the new name; its US app-info record and the US version metadata
were saved and read back. All **24 explicit US screenshot uploads** in four device categories are
COMPLETE, with source checksums, native dimensions, order and downloaded RGB pixels verified.
They reuse identical English UI captures from source `7643b20`; the original capture locale remains
`en-CA`, not a claim of a fresh US-region capture. Canadian and existing production assets were
read back unchanged. No further local device/UI tests were run.

**Primary-locale limitation:** Apple still returns HTTP 409
`MISSING_SCREENSHOTS_PRIMARY_LOCALE` when changing the app-wide primary locale to `en-US`, including
a retry after all US images became COMPLETE. The actual primary remains **en-CA** and that fallback
is retained. The **en-US localization is submitted**; do not equate that with changing the primary
locale. Preserve the rejection and revisit only after Apple's eligibility state changes.

For future releases, use `metadata/ios/en-US/` and verify actual locale/name IDs rather than copying
historical Canadian selectors. The maintainer reports working TestFlight testing and has requested
that local testing and participant requests stop; do not restart them for this submission. Human
voice accuracy and battery remain unquantified by the agent. Watch is excluded; macOS distribution
is unchanged. Production remains 1.15.0 (32) while Apple reviews the update.

Historical US submission evidence is
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-appstore-publication/locale-us/`:
`app-review-accepted.json`, matching review/version/name readbacks, US screenshot proofs and both
primary-locale errors. Parent-directory Canadian receipts are historical and canceled. Read the
old submission only as historical evidence; it was canceled for the fresh US refresh above. Never duplicate-upload build 36 or report approval without Apple readback.

## Historical Canadian submission — withdrawn October 26

**Apple accepted the public App Review submission at 2026-10-26T19:45:08.361828+00:00.** Review
submission `25ae4878-c462-4528-a48e-01b12b028f39` and iOS version
`c60352d3-eb78-479b-970c-d6ed6faa3242` both read back **WAITING_FOR_REVIEW**. Accepted build **36**
(`2fd8477d-504e-44d2-ac7f-6c7e9236d01f`) is selected, from artifact source
`7643b204def6acea0b616a2c2de2bade2fc4c7c9`. Release is **AFTER_APPROVAL**; this is a successful
submission, not an approved or publicly available update. The preceding public version remains
1.15.0 (32) until Apple finishes review/release.

The maintainer reported that TestFlight testing was already completed and working, and instructed
that further local testing stop. That is maintainer-reported acceptance for this release; it is not
an agent measurement of human speaker accuracy, audible playback quality or battery performance.
No more local device checks or participant requests should be started for this submission. The
basic source-equivalent development-signed capture passes below retain their original scope.

The API rechecked the exact build, en-CA metadata/reviewer contacts and all **24 COMPLETE screenshots**
with their native dimensions, checksums and order before creating one review submission, adding
only this version and sending it. No new binary was uploaded. Watch stays excluded; the macOS draft
and macOS publication were untouched. PR [#314](https://github.com/tomqwu/ListenToMe/pull/314) merged
as `493894d` after independent review and all three required checks passed.

Receipt, request/readback evidence and the maintainer's acceptance are preserved in
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-appstore-publication/`, particularly
`app-review-accepted.json`, `review-submission-readback.json` and `public-version-after-submit.json`.
This Canadian submission was subsequently canceled. For current status, read refreshed US review
`4e63cda8-70db-4d67-9928-63409df4dbda` in `refresh-us/`; never resume or resubmit a canceled review.
The preparation section below is historical.

## Historical public App Store preparation — October 26, iOS 1.18.1 (36)

The maintainer requested public App Store distribution. The configured API key can manage the
public listing as well as TestFlight; no manual upload or new credential was needed. Apple readback
still reports iOS **1.15.0 (32) READY_FOR_SALE**. Draft **1.18.1** (`c60352d3-eb78-479b-970c-d6ed6faa3242`)
is PREPARE_FOR_SUBMISSION with accepted build **36** selected, release after approval, and en-CA
metadata/reviewer instructions saved and read back. This is preparation, not a review submission or
public release. No review submission was created.

All **24** source-`7643b20` screenshots now report COMPLETE in four native iPhone/iPad sets. The
source checksums, dimensions, order and downloaded RGB pixels match. Five inherited draft images
were backed up/decoded/hashed before replacement; all production locales, image IDs/order and
metadata were read back unchanged after draft cleanup. Independent review cleared the guarded
screenshot finalization. The checked-in description reflects device-dependent capabilities and
known speaker limits. Watch remains excluded; the macOS 1.0 draft has no selected build and was
untouched.

Basic attended capture passed on **iPhone 12 Pro Max / iOS 27.0** and **iPad Pro 12.9-inch (4th
generation) / iPadOS 27.0.1**: one native test per device, zero failures/skips, fresh microphone
transcription, Stop and retained Play/Pause controls. The installed app was development-signed
Release with app inputs verified identical to accepted source `7643b20`; this is not proof of
installing the App Store/TestFlight artifact. Audible playback quality was not separately attested.
Speakers, Auto and correction were off in these basic runs. Human speaker accuracy, returning edited
names, latency/battery and the remaining affected-device gates are still pending; do not submit
production yet.

Preserve the failures: the first iPhone run rejected pre-existing test text after an interrupted New
tap; the first fresh human-speech run timed out without the expected phrase; the first iPad runner
required Apple's on-device XCTest passcode authentication before UI automation. None is a passing
capture result. The repaired physical-only harness requires the actual empty-transcript placeholder
and absence of old phrases, bounds New retries and returns before opening the microphone if freshness
fails. The successful synthetic sample played only after native Listening confirmation. The phone
is now idle with native speaker models ready, awaiting the maintainer's two-person availability.

Evidence and resumable, identity-guarded API scripts are outside the checkout under
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-appstore-publication/`; never create a second draft,
re-upload accepted build 36 or replace already-matching screenshots to resume this work.

## Current TestFlight publication — October 26, iOS 1.18.1 (36)

PR [#311](https://github.com/tomqwu/ListenToMe/pull/311) merged as `51cc890` and closed #310.
Apple accepted the API-key upload from exact artifact source `7643b204def6acea0b616a2c2de2bade2fc4c7c9` at
**2026-10-26T17:29:24.328646+00:00**. Apple build `2fd8477d-504e-44d2-ac7f-6c7e9236d01f` is VALID and
IN_BETA_TESTING; both existing Dev testers retain accepted group access. en-CA What to Test and
beta description were applied/read back. The exact-source tag and [non-Latest pre-release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.1-build36)
were verified. No installation of this new beta or production-ready acceptance is claimed.

Full local validation passed on `164c54a`: 1,239 Core tests (seven skips, 98.249328% coverage),
528 iOS tests (516 passes, 12 skips), 39 Mac tests including 13 real-model cases, four Watch tests,
107 BDD scenarios, helper/lint/signed-build checks and both real server contracts. Only four
release-documentation files changed before artifact source `7643b20`, whose three required CI
checks passed. All 24 fresh native screenshots across four iPhone/iPad categories were inspected,
hashed and preserved. [Image provenance](images/ios/release-1.18.1.json). Listing upload is pending.

Live iPhone/iPad speaker analysis now keeps recording-scoped streaming state. Actual-model
single/two-person regressions, overlap, returning names, final flush, bounds, cancellation and
reachable opt-out controls passed. Original tester audio and physical-device accuracy, latency
and battery remain unverified. Three-person synthetic speech still merges two voices; ten slots
are capacity, not established accuracy. Mac/Watch file analysis retains its existing pipeline.
Watch stays unembedded pending paired-device acceptance; Mac publication remains paused.

Evidence is preserved externally under `2026-10-26/listentome-speakers`, including exact archive,
IPA, upload receipt/log, Apple readback, tag/merge proof, full validation and 24 screenshots.
Completed Mac Dev-session cleanup preserved signing/test evidence, found no running Dev session,
moved only its inactive exact Dev bundle to Trash and successfully reset only
`com.tomwu.ListenToMe.dev` permissions. Production, other worktrees, data and keys were untouched.

Remaining issues: #181 Watch paired recording/sync acceptance; #205 physical multilingual Whisper
measurements; #223 additional semantic-search languages; #236 physical vocabulary-bias measurements;
and tracker #98. The dated sections below preserve earlier checkpoints and do not supersede this
publication record. No public App Store submission was made.

## Vocabulary biasing — #236 controlled measurements

The [evaluation report](vocabulary-biasing-evaluation.md) and [recorded observations](evaluations/vocabulary-236-2026-10-26.json)
preserve the existing physical-iPhone/Mac file-inference experiment. Five production adapter hashes
still match main `0901588`; four synthetic Medical/Cloud waveforms use the exact smoke-test scripts.
Every off/on baseline transcript was identical (36/64 targets). The explicit SDK diagnostic also
scored 36/64 with 100 accepted context terms. Contextual Dictation scored 41/64 on both platforms;
custom models scored 42/64 on phone and 41/64 on Mac, with no added pronunciation benefit by this
metric. This does not justify integrating a custom engine. Preparation/cache measurements and
ordinary/silence controls are recorded with their limited scope.

Only documentation and recorded evidence changed. No production model/engine, dependency, provider
choice or privacy setting changed; no binary train is called. The actual app read-aloud, mid-recording
changes, language switches and personalization acceptance remain incomplete, so #236 stays open.
The maintainer stopped further local device-testing/participant requests for the current release;
none were restarted. Original sources/native results remain under the external
`2026-10-26/listentome-vocabulary236` directory. Native build/harness failures are not product BDD red.

## Additional semantic-search languages — #223, October 26 follow-up

The new [evaluation record](semantic-search-evaluation.md) preserves isolated MiniLM, E5-base and
MPNet runs. Token parity passed; the final frozen MPNet holdout retrieved 36/40 expected matches
and rejected all 16 negatives, but Spanish recall was 7/10 versus the required 80%. Independent
review confirmed the no-go. Four-language integration is not accepted, #223 remains open, and
production still uses existing Apple embeddings/keyword fallback. No app dependency/model was
changed. Original plans, corpus/model/source hashes and raw scores are outside the worktree under
`2026-10-26/listentome-semantic223`; do not retune and relabel these observed sets held-out.
The earlier connected-device inventory enabled the controlled vocabulary measurements recorded above;
it is historical device state, not a claim of current unlock status or completed live vocabulary acceptance. No physical
paired Watch was found; same-machine simulator Watch inventory is not hardware acceptance.

## Historical combined publication — October 26, iOS 1.18.0 (35)

**PR #308 is merged; iOS 1.18.0 (35) is published to TestFlight.** All 18 prior PR heads and the
completed #134 implementation are preserved in ancestry. Nineteen implemented issues closed with
the merge. Subsequent speaker feedback is recorded in the current publication above. The source is `b1570ad567a43a093294974871d7f0abf1872708`;
merge `8c8023f12b0c324540614adc1a1f6906e8915eaf` has the exact same tree. The maintainer explicitly
approved “Defer Mac acceptance; merge and publish TestFlight.” Mac GUI/real OTHERS acceptance
remains pending and Mac DMG publication stays paused.

Apple accepted the API-key upload at **2026-10-26 12:51:44 UTC**. Build
`18ed5ceb-99cc-4658-b07b-3232b0bb23ce` is `VALID`, `IN_BETA_TESTING`, and included in the existing
internal Dev group; both existing testers have accepted group membership. en-CA What to Test and
beta description match their prepared files. The exact-source tag and [complete non-Latest GitHub
pre-release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.0-build35)
were read back; no binary is attached. Latest remains macOS `v1.4.4`. No installed TestFlight build
or production-ready acceptance is claimed. Current-source iPhone/iPad physical checks remain pending;
prior `215d818` microphone/Stop/Play-Pause checks are historical because persistence changed later.
Watch stays unembedded pending its approved paired-device gates.

Full `make validate-local` passed on clean frozen product source `45e015f`: 1,232 Core tests,
seven skips, 98.25909% coverage; 513 iOS passes and 12 intentional skips; 26 Mac and four Watch
passes; all 91 BDD contracts, helper/lint/build checks and real Ollama/OpenAI-compatible contracts.
Only CHANGELOG/HANDOFF/ORCHESTRATION documentation changed before b1570ad, whose three required CI
checks passed. All validation inputs remained unchanged. Twenty-four fresh inspected native screenshots
from b1570ad cover iPhone Pro/Pro Max and iPad mini/13-inch Pro. Originals, lossless orientation-normalized
copies, native dimensions and hashes are preserved; App Store listing upload remains pending.
See [image provenance](images/ios/release-1.18.0.json). No production App Store submission was made.

Release receipts, signing checks, tag/merge verification, Apple readback, screenshots and original
red/green/native evidence are preserved externally under `listentome-features/combined-train/release`
and `listentome-features/orchestration-134`. Four inactive temporary Dev bundles from the completed
session were moved to Trash after checking no Dev app was running; source/signing/screenshots/logs
were preserved. Four known changed test preferences were restored, and only
`tccutil reset All com.tomwu.ListenToMe.dev` ran successfully. Conversation data and API keys were
untouched. A pre-existing mac-menu build outside the completed acceptance session was left intact.

Remaining real issues: #181 paired Watch recording/sync acceptance; #205 multilingual Whisper
physical-device accuracy/performance/battery spike; #223 additional semantic-search languages;
#236 vocabulary-bias measurements; and their review tracker #98. The external #223 German/Spanish
embedding experiments are no-go research, not an implemented or published language expansion.
The dated checkpoints below are historical and do not supersede this publication record.

## Historical speaker-identification candidate — #310

PR [#311](https://github.com/tomqwu/ListenToMe/pull/311) contains the reported all-Speaker-1 fix for
**iOS 1.18.1 (36)**. Merge and upload remain pending; accepted TestFlight is still 1.18.0 (35).
Live iOS uses recording-scoped LS-EEND DIHARD II streaming. Mac capture and prepared Watch/file
imports retain their offline pipeline. See [model behavior and limits](speaker-identification.md).

Full `make validate-local` passed on clean frozen source **`164c54a`** at **2026-10-26 17:08 UTC**:
1,239 Core tests (seven skips, 98.249328% coverage); 516 iOS passes and 12 intentional skips;
39 Mac passes including 13 actual-model cases; four Watch passes; the 107-scenario BDD gate and
all bound automated native checks, helper/lint/signed-build checks, and real Ollama/OpenAI-compatible
contracts. Manual/device acceptance remains separate as described below.
Source hashes stayed unchanged and both dedicated simulators were deleted. The three required
hosted checks passed on that source. This release preparation changes documentation only; preserve
its product-source equivalence and require fresh CI on the final head before merging.

Independent correctness review passed. Real-model tests cover brief, balanced and unequal turns,
a second voice pair, returning names after silence, moving/duplicate windows, bounded long-run
prediction state, final flushing, cancellation, file readiness and old-run cleanup. Native controls
and rendered Settings tests prove opt-out is reachable while listening and re-enabling waits for Stop.
The largest-text release-history test now reaches the oldest heading through observed geometry;
its earlier fixed-gesture failure and other genuine red/green records remain in the dated external
evidence ledger. The interrupted/failed full runs are not counted as passes.

Fresh four-category release screenshots, final-head archive selection, merge, accepted upload,
Apple processing/Dev access, exact-source tag and GitHub pre-release remain pending. Earlier local
archives are preserved; none was uploaded. Only use the selected exact-source candidate after the
release-documentation commit and fresh checks. App Store Connect preflight found build 36 unused
and the production baseline still 1.15.0.

The original private recording and physical iPhone/iPad accuracy, latency and battery remain
unverified. An observed three-person synthetic sample still merges two voices under both old and
new models; this is explicitly disclosed in What to Test. Do not claim reliable three-person
separation or production readiness. Mac publication remains paused and Watch stays unembedded.

## Historical combined PR train — October 25

The maintainer explicitly requested consolidation of all 18 open PRs into one release and TestFlight
publication. Existing PR #308 (`codex/306-ipad-start`) is the integration PR; no new feature PR was
opened. It preserves the heads of #264, #280, #281, #283, #285–#296 and #303, including the older
refactor stack. The later #134 continuation above completes its implementation; required gates and
merge still determine done. Preserve all earlier history and evidence.
The combined candidate is **iOS 1.18.0 (35)**; the unpublished 1.17.1 candidate is folded into it.
Latest accepted TestFlight remains **1.17.0 (34)** from `cbd2e454dbf502df5832dc3654ee2d284f147380`.
Build 35 must be checked for reuse before uploading. Nothing in this integration is published yet.

Integration found real regressions: shared file re-transcription lost older-device dictation fallback;
summary/title/language copies lost incomplete-import provenance; the old capture adapter bypassed
readiness/start-error state; and cancelled normal OS errors could reappear after Stop. Native/Core
red and green evidence is preserved in the external `listentome-features/combined-train` folder.
Existing branch tests are baseline adoption, with no invented historical red. Independent review
found the cancelled-error and removed-title-task references and required direct native Mac capture
and checkpoint adapter bindings. Final frozen full validation, review, CI, merge, fresh screenshots,
archive/upload receipt and Apple tester/metadata readback are still required.

The first combined freeze `3f4d1e2` passed all 20 native Mac tests and the signed Mac app build.
Both connected physical iPad/iPhone passed real new microphone speech, Stop and opt-in Play/Pause
on that source, with one synthetic phrase played only after both confirmed Listening. Native
screenshots were inspected and preserved. Independent review cleared the integration. Hosted CI's
Core BDD run then aborted in the default naming initializer with "freed pointer was not the last
allocation"; its async public-default closure matches the trigger described in
[Swift #92017](https://github.com/swiftlang/swift/issues/92017). The partial full validation was
interrupted and preserved, not reported passed. The default closure now lives in a non-inline
convenience initializer inside Core; an additional native client file exercises linkage. A local
pre-workaround run passed, so the genuine red is the hosted crash, not a fabricated local failure.
Corrected source `215d818` passed all three hosted checks. Both physical devices repeated recording,
Stop and retained Play/Pause successfully on that exact source; 24 fresh native-resolution release
screenshots were captured, inspected, hashed and backed up. Its full local run passed 1,186 Core
tests (seven skips, 98.22% line coverage), then completed 522 iOS tests: 508 passed, 12 skipped and
two failed. The failures were a settings scrolling helper dismissing the sheet when returning to
the first row and stale release-note expectations for the unpublished 1.17.1 version. This is a
failed full run, not a candidate pass. The helper now uses actual navigation-bar bounds, and the
release contract and test identify 1.18.0 (35); focused and full validation must establish green.

The Mac was unlocked. Installed Dev acceptance then reproduced Start waiting for an OS microphone
callback and Stop/Quit remaining in Finalizing. TCC logged a delayed consent prompt. Native UI
automation cannot access the system consent surface; a specific request to bring Dev forward and
answer any prompt is pending, with no reset requested. The empty owned stalled test process was
terminated only after preserving screenshots, stack sample, signing and OS evidence, then reopened
from Finder. No synthetic audio has been played during this stalled Mac acceptance. Native Mac
regressions reproduced both the pending permission and pending capability cancellation failures.
The Mac preflight now races only resource-free metadata/consent waiting against cancellation using
a single-completion reply; real capture drain ownership is unchanged. Late results remain fenced.
All 24 native Mac tests passed, including late-grant and pre-execution cancellation cases, and
independent review found no blockers. All three focused cloud-settings/release-note UI tests passed,
including the large-text history check and the current 1.18.0 (35) announcement.
New frozen validation, CI, Mac GUI/OTHERS acceptance, merge and actual upload remain outstanding.

The earlier feedback-only `40d8e9a` full validation and 24 inspected images are historical evidence,
not acceptance of this combined source. Earlier physical iPad/iPhone recording and opt-in Play/Pause
checks passed at `e0e5062`; the connected iPad Pro4 has local dictation support but cannot use advanced
speech or Apple Intelligence. Those physical checks must be identified by their source, never
silently attributed to this release. Prior Dev cleanup was completed; the new installed Dev session
is still active. Restore its original settings and perform the authorized app-scoped cleanup only
after acceptance finishes, preserving other sessions, conversation data and keys.

**Historical pre-Watch-train checkpoint:** those builds excluded Watch. Current [Watch beta preparation](watch-beta.md) supersedes its blanket beta restriction under AGENTS.md; physical #181/#193 acceptance still gates production readiness. At this earlier checkpoint no physical Watch was found;
the maintainer's model/watchOS question is pending. Once included, install the iPhone beta in
TestFlight, then use its App Details → Information Watch install action on the paired iPhone, or
Watch → My Watch → Available Apps → Install. Current published builds have no Watch companion.
Mac DMG releases remain paused. This request authorizes a single TestFlight beta, not a public
App Store submission or store screenshot upload.

The sections below preserve older checkpoints; the current combined-train state above supersedes
older per-PR candidate and "next train" planning. Update this block after verified merge/publication.

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
| iPhone/iPad (TestFlight) | **1.19.0 (38)**, published 2026-10-27 UTC, tag `ios-v1.19.0-build38` at `e43244f` | Watch-enabled beta and Summary-icon fix available to Dev in en-US. Physical acceptance remains pending. |
| macOS | **1.4.4 (14)**, 2026-09-14, tag `v1.4.4` | **Releases paused on the maintainer's decision.** About 50 commits of Mac work are merged but unreleased; see [CHANGELOG → macOS (unreleased since 1.4.4)](../CHANGELOG.md#macos-unreleased-since-144). Do not start a macOS train yourself; the maintainer calls it. |
| Apple Watch | Included in **TestFlight 1.19.0 (38)** | Accepted/VALID package and processed Watch identity verified; [installation](watch-beta.md). Physical installation/recording/paired transfer/wrist-down/battery/storage remain pending; no public Watch App Store release. |

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
  the last App Store production release (ASC reported iOS 1.15.0 on October 25; recheck each train).
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

## Speaker-summary request candidate (#167) — October 25

Local work on `codex/167-speaker-summary-refresh` prevents speaker edits from creating a first
Listener summary with Auto off. It invalidates the old stream and ledger even when no replacement
request starts, while retaining explicit Refresh and rebuilding completed summaries. Focused Core
coverage passed (1,064 tests, seven skips, zero failures; 98.11% line coverage). Lint and independent
review passed, including fixes for repeated edits during rebuilding and rejected resets. Full
validation, rendered Mac acceptance and hosted CI remain pending. This work is not merged or published.

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


## Automatic review contract candidate (#148) — October 25

`codex/148-automatic-review-contract` caps the assembled request rather than only normalized
conversation text, composes the shared language rule once, and adds direct coverage for directive-only
changes and a speaker rename during a Quick read. The rename test preserves #180 behavior: already
acknowledged speech is relabeled without being sent again; unread stale work is rejected and retried
with the new label. Core validation passed (1,060 tests, seven skips, zero failures; 98.1079% coverage), along with lint
and independent review. The app/test targets compile for both simulator architectures. A simulator
UI scenario passed and its two native screenshots were inspected: the limit notice is readable, and
shortening input produces Summary successfully. Full `make validate-local` passed at `209a1f8`,
including simulator unit/UI tests, Core coverage, release helpers, real provider contracts, lint and
the signed Mac build. Current-main integration checks and Mac installed-app acceptance remain pending.
Not merged or published.

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
