# Handoff — 2026-10-26

A snapshot for an agent picking up ListenToMe cold. [AGENTS.md](../AGENTS.md) and
[CLAUDE.md](../CLAUDE.md) stay the rules; this note is only the state of things on the date above.
Re-check anything time-sensitive (`gh issue list --state open`, `git log`, tags) before acting on it.

## Current US screenshot refresh and App Review — October 26, 21:13 UTC

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

**Watch remains excluded from distribution** until the physical paired-device spike/recording-sync
acceptance in #181/#193. Simulator native tests do not waive this gate. No physical Watch was found;
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
| iPhone/iPad (TestFlight) | **1.18.1 (36)**, published 2026-10-26, tag `ios-v1.18.1-build36` at `7643b20` | Speaker fix published to Dev; Watch excluded. Current physical accuracy/performance and original audio pending; three-person separation unproven. |
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
