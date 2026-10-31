# Behavior-driven development

ListenToMe develops behavior from examples across the whole repository: Mac, iPhone/iPad, Duo,
Watch, shared services, imports, data ownership, privacy and build/release tooling. The rules live
in [AGENTS.md](../AGENTS.md); the executable examples live in [Behaviors](../Behaviors/).

Each JSON feature groups observable scenarios with stable IDs, a name, `given`, `when`, `then`,
scoped repository-relative `covers` patterns and `bindings`. This is a native-test adapter: Swift
XCTest and Python unittest execute the assertions. JSON carries the behavior contract and exact
test selector, so there is no duplicate Cucumber implementation or dependency to keep in sync.

`RELEASE-009` binds explicit manual TestFlight signing to offline upload decisions, invalid-file/field refusal, dry runs, exact phone/Share/Watch profile maps, unchanged automatic defaults, private options snapshots that survive changes to the original file, and accepted-receipt provenance. Exported native signatures/profiles and Apple upload/processing/tester readback remain separate release gates.

The Mac Store draft uses `RELEASE-010`–`RELEASE-013` for its generated sandbox configuration,
existing DMG/Dev identities, vault bookmarks and selected-file/folder reference scopes. These were
`RELEASE-006`–`RELEASE-009` on the draft before the Watch train added its own scenarios to main.
Integration preserves main's IDs and remaps only the unmerged Mac examples; their original red/green
evidence remains valid under that explicit mapping. Temporary-directory bookmark tests do not prove
installed sandbox picker grants across relaunch, which remain manual acceptance.

AUDIOFEED-001–004 bind native iOS `AudioChunkFeedTests` and Mac `MacAudioChunkFeedTests` to generated local PCM frame/tail, timeline, Stop and empty/error outcomes. The genuine Int16 regression and focused/supplemental results are recorded in [the audio-feed evidence](audio-file-feed-tail.md); structural validity and simulator/native converter checks are not speech-quality or physical acceptance.

## Working an issue

`RELEASE-014` binds the locally testable Store sandbox configuration, unchanged production/Dev
identities, release optimization and fail-before-build missing-signing outcome to generated native
settings and an actual make invocation. CI's explicit unsigned build proves compilation only.
Installed Dev sandbox picker/relaunch/audio checks and Apple-distributed installation remain
separate outcomes; the recorded Store-profile launch failure is not a permission failure.

Finish the current change through validation, review, CI and merge before opening another feature
PR. Future work stays in GitHub Issues. Work down existing drafts sequentially and consolidate
multiple drafts for the same issue without deleting their source or acceptance evidence.

1. Understand the issue and choose concrete examples before writing production code. State the
   starting condition, user action/event and observable outcome. Add edge cases, failures, data
   erasure, cancellation and off-device consent as the behavior requires.
2. Add/update a scenario in the appropriate feature. Narrow `covers` to the affected files or
   domain; baseline platform globs route ownership and do not prove exhaustive behavior coverage.
   Bind it to a specific `Class/testMethod` and source file in `core`, `ios-unit`, `ios-ui`,
   `mac-unit`, `watch-unit`, `watch-ui` or `tooling`. A scenario may need multiple bindings across platforms.
3. Write the reproducing native test and run it **before** implementation. Record the expected
   failure, implement the behavior and record the passing run. Refactor under the same tests.
   A failing compile caused by a typo is not evidence that a regression was reproduced.
4. Run `make bdd-check`, affected suites and the existing `make validate-local` gates. Exercise
   rendered UI and actual audio/device paths when required. Preserve source, commands and results.
5. Update all affected docs and platform release notes, request independent correctness review,
   include scenario IDs and actual red/green evidence in the PR template, then merge with the three
   required CI checks green. Publication remains a separate authorized release train.

Example from the retained-Watch-audio contract (`WATCH-001`):

```json
{
  "id": "WATCH-001",
  "name": "Retain Watch audio only with consent",
  "given": "a Watch recording arrives on iPhone",
  "when": "transcription finishes with Save audio recordings on or off",
  "then": "opt-in retains playable audio and opt-out removes the inbox copy",
  "covers": ["iOS/MobileSession+Watch*"],
  "bindings": [{
    "suite": "ios-unit",
    "file": "iOSUnitTests/MobileWatchAudioTests.swift",
    "test": "MobileWatchAudioTests/testOptInRetainsPlayableAudioAndOffDeletesOnlyInboxCopy"
  }]
}
```

The real catalog also records paired-device acceptance steps. Simulator tests cannot prove
disconnected Watch transfer, real microphone/system capture or physical-device readiness.

## Speaker model accuracy is behavior

The #310 regression exposed a missing boundary: fake diarizer IDs proved label mapping, not that
actual voices were separated. `SHARED-001` now explicitly describes already-diarized groups.
`SPEAKER-001`–`SPEAKER-016` bind actual model inference, streaming lifecycle, timeline authority and
native controls separately. The Mac native suites call the same `productionDiarizer()` selected on
physical iPhone/iPad; the unit/UI host substitutions cannot satisfy these quality contracts.

`make mac-test` and `make validate-local` run the checked-in synthetic stock-voice WAV fixtures
through real CoreML inference. First preparation may download public model weights from Hugging Face;
subsequent runs use the excluded-from-backup cache. No microphone, private conversation, audible
playback or cloud inference is used. Assert each known turn's correct voice identity, single-voice
controls, a second voice pair, successive overlapping windows, returning voices and edited names
through silence, bounded long-run state, final flush, cancellation and cleanup. Merely finding two
raw speaker IDs is insufficient: swapped identities must fail. These fixtures are regression gates,
not proof of the original private recording, physical-device performance or universal accuracy.
The separate three-person diagnostic still merges two voices and is documented as a known limitation.
Native property tests also need reachable user controls: the opt-out contract includes a rendered
Settings-switch test while recording, rather than treating a direct property assignment as UI proof.
See [speaker evidence and acceptance](speaker-identification.md).

## Translation inference and stalled-service recovery

#343 exposed the same distinction as speaker quality: injected translations and simulator screenshots
proved placement, not Apple engine output. The installed native Mac journey now uses the actual
`AppleTranscriptTranslator` and summary coordinator. Its installed-pair branch checks Chinese prose,
budget/weekday facts, code and originals; setup/unsupported branches are explicitly recorded and
are never called inference passes. Physical phone accuracy remains separate.

`TRANSLATESTALLED-001`–`004`, `TRANSLATENATIVE-001`–`003`, `TRANSLATEUI-001` and
`TRANSLATEINSTALLED-001` cover a held readiness/inference service, bounded timeout, cancellation
forwarding, safe drainage, actual controls, late completion/timer races and the real installed pair.
Held-service tests intentionally ignore cancellation; they prove bounded state without multiplying
native work. See [evidence and acceptance limits](translation-recovery.md).

`TRANSLATIONLEGIBILITY-001`–`003` bind essential translation text to actual iOS Summary/status
renders and supported native Mac card/rail renders. Native environment, opaque surface, text bounds
and measured glyph contrast are checked before a pass; a palette-only assertion is insufficient.
The preserved initial scroll/appearance harness failures are separate from the genuine iOS contrast
red. Mac increased-contrast propagation remains unverified. See [legibility evidence](translation-legibility.md).

## Watch durability and beta eligibility

`WATCH-005`–`WATCH-014` exercise native AAC encoding/reading, crash recovery, metadata-first handoff, duplicate/conflicting chunks, end-marker storage failure, continued recording boundaries, pending counts, active-recording protection and Delete/relaunch. Transport and audio-session adapters isolate tests from real WatchConnectivity and microphone capture. Red evidence is retained separately from passing baseline adoption and test-harness failures; simulator assertions never prove physical delivery or wrist-down/battery acceptance.

`RELEASE-003`, `RELEASE-006` and `RELEASE-007` separately cover default embedding, explicit Watch beta selection and refusal of unintended or malformed companions. A generated PBX configuration, a built embedded app and a distribution-signed exported IPA are separate checks. Current AGENTS.md permits beta distribution with physical acceptance recorded as pending. Its separate standing review-submission authorization applies only when production-readiness gates, including affected-device acceptance, are satisfied; beta eligibility does not waive them.

`WATCH-015` preserves a device/runtime regression that the iOS 26.5 simulator tests missed: that runtime accepted
Float32 `AnalyzerInput` buffers while iOS 27.0.1 trapped with a signed-integer precondition. Native AAC
language/speaker decoding now stays outside Speech; transcription alone uses the negotiated Speech
format. `WATCH-016` tests the actual recording presentation binding and rendered background/return
controls. Neither a passed binding test nor a preview capture establishes physical wrist-down audio.

## Release-history accessibility acceptance

`RELEASE-004` includes the actual oldest release heading and fixed Continue control at the largest
text size. Scroll toward the observed heading through the unobscured viewport, recover from
overshoot, and retain geometry/screenshots on stalls. A fixed gesture count cannot establish
reachability as release history grows. The #310 train exposed the former 70-swipe test stopping
above the oldest entry; its failed capture is evidence of an incomplete test journey, not proof
that the app truncated history. Both the heading and Continue must remain usable in the corrected
native test; never remove the old-heading assertion just to pass a release.

## Device compatibility is behavior

For each affected feature, specify its supported and unavailable states before implementation.
Do not infer support from the OS version or Apple Intelligence eligibility alone: local speech,
summary AI, model readiness, microphone access and paired-device connectivity are separate capabilities.
This applies to iPhone/iPad (including Duo), Apple Watch and Mac.

Use the shared `DEVICE-001`–`DEVICE-004` readiness contract together with concrete platform scenarios:

- Given supported hardware and language, when listening starts, then current microphone speech is
  transcribed even if summary AI is unavailable. An available local dictation engine is a valid fallback.
- Given an unsupported engine/language, when the screen opens, then Start is disabled and the reason
  and supported alternatives are visible before a tap; no microphone request or download starts.
- Given denied permission or missing setup, when the feature is shown, then execution is blocked
  with an applicable recovery action. Unknown permission may still be requested by an explicit tap.
- Given unavailable Apple Intelligence, when choosing AI, then it cannot be selected as a working
  provider; saved choices remain intact, with explicit alternatives and no automatic cloud routing.
- Given changed language, permissions, model readiness or connectivity, when availability refreshes,
  then obsolete asynchronous checks cannot re-enable an unavailable action. Stop remains usable.
- Given an unreachable or incompatible paired iPhone, when the Watch remote appears, then Start is
  unavailable with a recovery reason; the Watch's independent offline recording remains separate.

Bind platform adapters and control behavior to native tests. Generic readiness booleans alone do
not establish native integration. Record coverage gaps explicitly and retain physical-device,
rendered UI and real Mac OTHERS acceptance where applicable; a simulator pass cannot replace them.

## Physical capture freshness

The attended capture helper must prove that New reached an empty transcript before Start. Match
actual text elements, require the empty-transcript placeholder and reject phrases from a prior run.
A notification can intercept New: bound retries, capture the stall and return before opening the
microphone if freshness still fails. An old transcript must never satisfy a live-audio assertion.
The October 26 acceptance caught that guard failing; the repaired helper then passed on physical
iPhone/iPad with a synthetic phrase played only after native Listening confirmation. This is a
harness repair, not an invented product-regression red. Retain the earlier failures and distinguish
Play/Pause-control acceptance from audible playback quality, and basic capture from speaker accuracy.

`MACAUDIO-002` runs the actual native SpeechAnalyzer through prepared-but-empty, single-source,
cancelled and real speech-file completion. It asserts bounded completion and result-stream closure,
with first/final words and native audio times retained. Installed Start/New recovery remains a separate
manual check; a missing installed English model skips the test and cannot satisfy BDD acceptance.

## Native log evidence

`HISTORYREFRESH-010` covers ordinary scrolling on compact and larger landscape iPhones and wide
iPads. The build-44 capture attempt passed all five methods on iPhone 17 Pro, then failed the
History row/search separation assertion on Pro Max after a 13-point upward drag; its other four
methods passed. The test now requests at least 44 points, capped at one third of the viewport,
without relaxing whole-row containment, nonintersection, exact-query or open/reopen assertions.
The corrected History method passed on both phones. Final source `9460f00` then passed the
complete local validation, including this method on Pro Max; the same-source focused Pro run also
passed. [Current full receipt and scoped render evidence](evaluations/ios-1.20.4-full-9460f00-2026-10-31.json).
[Preserved failure and capture limits](evaluations/ios-1.20.4-history-capture-failure-2026-10-31.json).

The subsequent `9460f00` capture passed both phones but exposed an incorrect iPad precondition:
mini's actual 1,093-by-415-point landscape content correctly used Duo, while the test expected
the full wide workspace from device idiom alone. Only that initial assertion failed; all later
History checks completed. The test now recognizes the existing adaptive Duo or wide container,
as the translation journey already does, without changing the app or any History outcome assertion.
The corrected mini execution and final full validation are pending; the prior full pass remains
bound to `9460f00`. [Preserved mini failure](evaluations/ios-1.20.4-ipad-mini-capture-failure-2026-10-31.json).

`READMEPREVIEW-001` captures the existing concise fixture first in portrait, requiring both
complete transcript lines and the complete Quick answer, then retains its original Duo checks.
That added baseline passed on Max but exposed an unscrolled answer about 17 points below its
Quick viewport on Pro; the History method passed on both. The correction uses one bounded scroll
inside Quick only when needed, re-reads its viewport and rechecks both transcript lines afterward.
All text/containment assertions remain. The same-source focused Pro retry passed both methods
on `9460f00`, exercising the conditional Quick scroll; the complete local run also passed both on
Pro Max, where the portrait answer fits without scrolling. These native images are bounded QA;
fresh release captures and gallery inspection remain separate. Longer translation/live fixtures
are not substitutes for a clean portrait gallery image.

`ENDPOINTUI-001` and `ENDPOINTUI-002` bind rejected-address recovery, exact replacement and honest
server/privacy labels to native Settings controls and the corresponding persistence policies.
During build 44 validation, the Ollama journey reached its HTTPS rejection notice but failed because
the transient **Select All** menu was absent. Later normalization/privacy assertions were not reached.
A native keyboard selection attempt also failed its exact-value assertions. Both journeys now
close and reopen Settings, verify its discarded draft is empty, then enter the corrected address
and retain all outcome assertions. The Ollama UI also verifies its saved destination survived the
rejection and reopen. This is a harness repair with observed harness failures, not a claimed product
regression, in-place text-editing acceptance or an invented red for adopted unit tests.

`MACAUDIO-001` covers the actual native PCM-to-`AnalyzerInput` boundary exposed by #333, beyond the
older scalar `BATCH-291` timeline tests. Nine methods exercise real conversion, separate raw/sample
clocks, exact frame accounting, gaps after accumulated drift, invalid input and cancellation/queue
ownership. See [the timing evidence](speech-input-timing.md); native buffer construction is not
recognition quality or installed OTHERS acceptance.

`DEV-008` covers a real aggregate-validation failure: macOS joined a timestamped framework diagnostic
to a complete XCTest pass record. The native result bundle reported all 39 Mac tests passing, but
the line-start-only verifier missed one bound selector and stopped validation before Watch/e2e.
The verifier now extracts the exact class/method from a complete passing XCTest event, allowing
that framework prefix without accepting diagnostic mentions, other selectors, skipped/failed tests
or incomplete records. The original run remains failed; new offline regression cases and the saved
native log verify the parser fix before the full candidate validation is repeated.

`DEV-009` covers an actual false-success boundary in Apple's GNU make 3.81: `.SHELLFLAGS` was
ignored, so a failing native command piped into `tee` could return success and reach later stages.
Six offline methods execute the repository Makefile and native recipes with harmless commands,
checking failures, successful controls, preserved diagnostics, paths with spaces and refusal to
run later verification. Bash flags now belong to `SHELL`, which the older make actually uses.
The original native failure remains failed; these tooling tests do not accept any app behavior.

`VAULTUI-001` adopts the existing Save-to-folder journey and its observed full-run failure. The
native screenshot/AX showed the enabled toggle partly outside the viewport, while lower lazy rows
had not appeared. The corrected test reveals complete controls/disclosure inside Settings and scopes
text queries to that form; a first revised page-wide query incorrectly found the warning behind the
sheet and is retained as a harness failure. Default-off, explicit picker, Cancel, enabled-but-needs-
folder and reachable Choose folder assertions remain. No folder behavior changed. See
[the combined evidence](validation-pipeline-recovery.md).

## Commands and enforcement

```sh
make bdd-check                         # change-aware check against origin/main
make bdd-check BDD_BASE=origin/parent   # actual base for a stacked PR
make bdd-test BDD_SUITE=core
make bdd-test BDD_SUITE=tooling
make bdd-test BDD_SUITE=ios-unit IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=ios-ui IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=mac-unit
make bdd-test BDD_SUITE=watch-unit WATCH_DESTINATION='platform=watchOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=watch-ui WATCH_DESTINATION='platform=watchOS Simulator,id=<dedicated-UUID>'
make bdd-manual                        # lists required acceptance; does not mark it passed
python3 scripts/test-bdd.py            # offline gate regression tests
```

Create a fresh dedicated simulator for iOS tests and delete it after preserving evidence. These
commands never reset a shared simulator, alter macOS permissions or authorize a production release.
Native BDD commands select exact methods. Full local validation runs the iOS unit/UI, headless
native Mac adapter/control and Watch unit/UI suites. Supply dedicated `IOS_DESTINATION` and
`WATCH_DESTINATION` simulator IDs; Watch commands refuse a missing ID or wrong platform.
`make ios-test`, `make mac-test` and `make watch-test` preserve native output and verify every bound
selector passed, so a skipped or filtered-out scenario cannot satisfy the gate. Mac native tests
compile production framework adapters and menu controllers without opening the app or user data.
Watch tests run the actual app/client/recorder on watchOS Simulator; they do not establish real
paired transfer or microphone acceptance.

The checker rejects missing/duplicate IDs, empty Given/When/Then steps, unscoped patterns, missing
test files/methods, mismatched suites and behavior files without a scenario. Its change-aware gate
requires an updated scenario covering each changed behavior path and a new/changed bound test
method. A changed file header or unrelated test in the same file does not satisfy it. New unknown
code roots fail until they are assigned a scoped contract. Docs, release copy and test-only Swift
changes do not demand an unrelated production scenario. Python test helpers remain tooling.

The required **ListenToMeCore tests + coverage** CI job checks PR changes against their actual base,
fetches the current target branch for PRs (including stacked PR targets), tests the gate, executes
bound core/tooling scenarios and retains the 95% core coverage floor. A push compares against its
event’s before commit. Failed target fetches fail the check; they never fall back to a stale PR base.
The existing macOS and iOS build checks remain required. Main also requires branches to be up to
date before merge, so older drafts must incorporate the current BDD workflow. The three required
check names are unchanged; the live Main ruleset's strict up-to-date requirement was enabled and
read back on October 25, 2026.
Local `pre-push` and `make validate-local` include the structural/change-aware check. The latter also
tests the gate, checks observed iOS, Mac and Watch binding results and retains all native, helper and real model
contracts. Python execution checks exact verbose selectors rather than accepting aggregate counts.

BDD runs save source, working-tree state, input hashes, commands, selectors, logs and results in
gitignored `dist/bdd/`. A successful native process with zero tests, missing passing selectors or
skipped bound tests fails the BDD runner. Running the checker alone does not execute scenarios.
Manual acceptance always needs separate source-matched evidence; a catalog entry is not a pass.

## Adopting existing work honestly

The initial catalog binds existing representative regression tests across the repository. These
are **baseline adoption**, with no invented historical red evidence and no claim of exhaustive
legacy behavior coverage. Existing unit/integration tests remain valuable and stay in normal
suites; they do not need cosmetic Given/When/Then renaming. As each backlog issue or older branch is
integrated, add/update the relevant examples and record a real regression reproduction for its
behavior changes. Do not silently exempt old branches from the change-aware gate.

Automation checks structure and observed execution, not intent, causality or test quality. An
independent reviewer must compare each scenario with its assertions and verify red/green evidence.
Do not satisfy a behavior change with an unrelated test or weaken coverage/manual acceptance gates.

## iPhone and iPad recording continuity (#339)

`CONTINUITY-001`–`CONTINUITY-003` distinguish an already user-started microphone from pending or
idle capture. Native session tests keep one recording through inactive/background, preserve final
speech and elapsed start, keep explicit Stop authoritative, and fence auxiliary AI/correction/speaker
work. The native sink holds at most its bounded newest speaker audio. A simulator UI journey uses
actual Home/activate and the production meeting view; its injected recorder does not prove physical
screen-lock capture, audio-session routing, battery behavior or paired-Watch control.

`LANGREPLAY-001`–`LANGREPLAY-004` bind actual session replay handling: a cumulative utterance crossing
the replay cut must show progress without prematurely deleting originals, commit its final once,
and release later checks. Inactive preparation and detection completions are generation-fenced;
foreground can retry using recent retained audio. A replay without advancing results gets one
same-locale restart after 30 seconds of accepted audio activity, with silence excluded and progress
resetting that budget. The native adapter cancels/fences the superseded result generation. Failed
recovery retains text/capture, permits future checks and reports possible missing speech instead of
claiming a complete transcript. Stop or new progress cancels an obsolete in-flight recovery. Undo owns its task across context and
native preparation: inactivity, Stop or New fence late switch/pin/error effects, and native locale
and saved-language metadata commit together before post-commit context work can suspend. Stop
preserves the user's already-requested Undo intent and applies it after drain; inactivity cancels an
uncommitted Undo without applying it. Explicit stopping-time Undo remains queueable.

The cheap activity detector is not a speech-quality oracle. These tests use injected audio/results,
not real multilingual inference. The existing detection cadence, confidence, dwell and switch cap
remain; detection pauses while inactive/background and the Apple recognizer remains single-language.
Physical continuous bilingual speech, lock/background, route changes, Stop/Undo and saved-audio
opt-in acceptance remain separate. See [language replay evidence](language-replay-progress.md),
[recording continuity](recording-continuity.md) and the [manual script](manual-smoke-test.md#iphone-and-ipad-continuity-and-language-replay-339).

## Translation boundaries

`TRANSLATE-001`–`TRANSLATE-014` cover opt-in final-line translation, independent Summary-page
translation, original preservation, native pair readiness, saved choices and lifecycle fencing.
Native UI fixtures prove placement and control behavior; installed-model quality needs separate
real-model acceptance. The [validation record](translation-validation.md) distinguishes genuine
regression reds from test-harness failures and records the complete unchanged-source component
matrix after a torn native stdout event prevented the aggregate verifier from completing.

## Transcript speaker rename shortcuts (#334)

`SPEAKER-020` compares short and long names in the actual native Mac row: the label must visibly
change within its column while the adjacent transcript's pixels, text and geometry remain intact.
It also checks the full tooltip/accessibility name. The initial native run reproduced an expanded
266-point label and 2,675 changed pixels beyond its 100-point column; the unchanged test passed with
zero overflow after native compression and tail truncation. The ten-method related suite passed.
[The source-bound receipt](releases/mac-speaker-name-overflow-f26-validation.json) retains both runs.
Corrected installed rename, full quit/relaunch, tooltip and VoiceOver acceptance passed on `9a39a12`,
with source-labelled native README captures. The later `89e9226` candidate also includes PR #353's
workspace changes; the speaker control, production row and bound bitmap-test files remain
byte-identical to that earlier source, not the whole app. Combined validation: passed (exit 0).
[Current evidence](speaker-rename-acceptance.md) records the complete counts, source audit and fresh
native attachment inspection while preserving the separate source scopes and failed runs.
Combined installed acceptance and a fresh full-app Mac long-name gallery capture remain open;
the locked Mac blocks that capture, and diagnostic test images do not replace it.

`AUDIOVIEW-001` covers the retained-audio player above the expanded transcript at standard and
largest text sizes: complete visible phrases, single-line time, usable controls and enough reading
space to reveal the original speaker without playback. The real AX5 layout red, distinct test-harness
failures and final phone/iPad passes are recorded in [the layout evidence](saved-audio-accessibility.md).
The rename test explicitly reveals the same original row before its real long press; it does not
replace an offscreen target with another speaker or weaken editor/keyboard assertions.

`SPEAKER-017` binds native iPhone/iPad long-press, Save/Cancel, repeated identities, blank names,
Notes synchronization, keyboard visibility, Duo and rotation. `SPEAKER-018` binds native Mac
double-click versus single-click/disabled controls, accessibility activation and name validation.
Mac installed sheet/save/reopen and VoiceOver remain explicit acceptance steps.

The initial native reds were a missing Rename speaker menu on iOS and no callback on Mac double-click.
Duo then reproduced a real editor-dismissal failure when the keyboard changed the workspace layout;
the sheet now belongs to a stable parent and retains the original conversation/line identity.
Large-text screenshot inspection found clipping despite passing hittability checks; those earlier
passes are not evidence of acceptable rendering. Preserve before/after captures with release evidence.

Mac review also reproduced a live-breakdown regression: a known participant without attributed
transcript lines could no longer be named. `testRenameLiveParticipantBeforeTranscriptAttribution`
failed two native assertions before restoring participant-first lookup. The same adapter test group
checks all restored lines change together and unknown IDs leave both labels and revision unchanged.
The earlier integration added `SPEAKER-019` for cold readiness and strengthened `SPEAKER-017` to
require the actual two-pane workspace before/after rotation and Save. On base `6705543` plus the
retained dirty test/scenario inputs, the two methods failed four assertions. The DEBUG simulator
fixture then adopted the existing production lifecycle bridge; those exact tests passed unchanged.
The six-method related rerun also passed, including largest text, opt-out, Notes and saved-audio
controls. [The source-bound receipt](releases/speaker-rename-6705543-readiness.json) distinguishes
these fixture controls from real diarization/Watch transfer/audio quality. At that checkpoint,
combined validation, installed Mac, VoiceOver and disk-relaunch acceptance were pending; the later
source-specific results are recorded above and in [current acceptance](speaker-rename-acceptance.md).
No historical results are relabelled, and no release is implied by the fixture correction.

## Dual-channel audio and presentation

`MACEDIT-001` hosts the production transcript row and sends native pointer events at actual glyphs.
It checks the correct editor, partial-line refusal, selected-text Copy serialization, an accessible
Edit action, and complete multiline/CJK layout after resizing while preserving selection on refresh.
Programmatic selection in that native Copy test does not prove pointer-drag selection; installed
signed-app drag/keyboard/menu and Save/Cancel acceptance remains separate. See
[the regression evidence](transcript-interaction.md).

`MACAUDIO-003` and `MACAUDIO-004` distinguish chronological display/persistent line identity from
microphone echo control. The native lifecycle tests cover setup failures and route/profile state changes through injected drivers,
recovery cooldown and terminal Stop. Playback-only OTHERS success is insufficient: separately
accept independent microphone speech and overlapping speech, without text-based duplicate removal.
See [the #336 evidence and remaining acceptance](dual-channel-capture.md).

The #334/#336 integration extends the restored-identity native test with delayed channel finals:
renaming preserves chronological presentation and canonical line/run IDs, capture times and text.
It passed on first execution and is recorded as integration coverage, not a new regression red.

## Combined speaker and transcript gestures

On the speaker-rename branch, `SPEAKER-018` also hosts the production row alongside `MACEDIT-001`.
Native pointer events on transcript glyphs open only the line editor; speaker-label events open
only the name sheet, and its Escape shortcut dismisses without changing the name or transcript.
These additional integration assertions do not replace installed pointer, keyboard, menu, VoiceOver
or persistence acceptance. The native sheet bitmap is diagnostic: missing button-label rendering
prevents treating it as a complete visual pass.

## Withdrawing an unaccepted optional feature

`HISTORYDELIVERY-001` traverses real iPhone Settings through Recording and rejects the withdrawn
optional-model controls. It failed on the visible heading/download button, then the same method
passed after removal. `HISTORYDELIVERY-002` exercises the shared default History composition with
old optional derived vectors: Apple/keyword behavior preserves original archive bytes and dormant
asset/preference sentinels. The latter is new baseline coverage, not a historical regression red.
Optional-only runtime tests remain preserved with their source at `08521d5`; removing that product
scope does not turn its failed quality gate into a pass or complete #223. Apple/indexing contracts
remain required. [Focused evidence](evaluations/history-delivery-scope-2026-10-30.json).
