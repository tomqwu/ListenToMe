# iPhone and iPad recording through screen lock (#339)

In the upcoming 1.20.1 (41) candidate, an established, user-started microphone recording stays active when the screen locks or the
app backgrounds. Returning to the app preserves the recording and its elapsed start; Stop still
ends it. An interruption, unavailable route or capture/transcription failure can still stop the
recording with the existing recovery message. This does not allow a cold/background launch, Watch
Start or delayed cancelled preparation to open a new microphone session.

The app declares the audio background mode and keeps its existing recording audio session. No
silent playback, periodic background-task trick or broad permission reset is used. Device/language
compatibility checks and the selected on-device speech module remain unchanged. Apple documents
the [recording background mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
as the mechanism for recording through screen lock; that does not prove this application's native
speech behavior on every supported device or OS.

## Optional work and data handling

Inactive/background transitions pause manual and automatic Quick/Summary requests, automatic titles,
vocabulary classification, speech correction, translation, speaker passes and language-model
preparation/checks. Queued requests check cancellation before starting a provider or classifier.
Outstanding work is cancelled
and stale completions are fenced; a model already executing may finish, but cannot publish its old
result or start the next pass. A current foreground can resume optional work without opening a
second recording. Existing provider selection and text-sharing disclosures remain in force.
Vocabulary suggestions remain independent of speech-correction opt-in. An interruption-end while
inactive keeps recording stopped and offers tap-Listen recovery rather than falsely reporting a resume.

Speaker identities retain their run. Its native sink bounds the rolling speaker audio to the
existing ten-minute window plus one storage block while passes are paused. A long background
interval can therefore leave earlier lines labelled Microphone; it is not a promise to relabel all
background speech. The language buffer keeps its separate existing rolling limit. Neither buffer
is a saved audio file. Save audio recordings continues writing only when enabled, and Stop closes
that writer. With saving off, background continuity does not start hidden raw-audio persistence.
Existing backup exclusions and complete-until-first-authentication protection remain unchanged.

## Executable evidence

`CONTINUITY-001`–`CONTINUITY-010` in
[the behavior catalog](../Behaviors/recording-continuity.json) bind native session, provider,
speaker, actual PCM sink and installed-plist assertions plus a rendered simulator journey.
Evidence is preserved outside the checkout under
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-recording-continuity339/`:

- `native-red.log`: seven methods, 16 assertion failures on the original background-stop,
  missing audio mode and insufficient paused-pass memory bound. The initial pending-start
  cancellation case already passed; no historical red is claimed for it.
- `native-privacy-red.log`: eleven methods, 24 assertion failures, including inactive held
  Quick/correction output and speaker completion/preparation fencing. The extra fake acquisition
  boundary assertion passed on its first execution and does not prove hardware acquisition.
- `native-green.log`: a test-harness optional-Bool compilation error; no product red or pass.
- `native-green2.log`: 67 native methods passed, including eleven new continuity/privacy/speaker
  methods and 56 existing lifecycle, preparation, remote-control, correction and summary methods.
  These results precede subsequent language-recovery and rendered-UI additions; final combined
  validation is recorded separately by the release owner.
- `ui-notice-red.log`: the real simulator Home/return/Stop journey reached its assertions, with
  one expected failure for the absent disclosure. The owned Xcode process then waited on its own
  600-second `simctl diagnose` collection; that diagnostic child alone was terminated after the
  completed test result, and Xcode exited 65 and was reaped. A process sample is retained. This is
  not a microphone failure or a claim that the original capture bug was reproduced by this UI run.
- `native-ui-green-final.log`: 67 native methods and the one rendered UI method passed on the
  combined continuity/language-recovery source, with actual TEST SUCCEEDED, exit 0 and reaping.
  Verbose failure-diagnostic collection was disabled for this focused run; assertions were retained.
  `ui-green-attachments/` preserves three native-resolution screenshots and their exported manifest.
  Inspection verified Listening/Stop before and after actual Home/background return, one start and
  zero stops across that transition, followed by Ready/Start and exactly one explicit Stop. The new
  recording disclosure is fully visible. The fixture's diagnostic probe overlaps the toolbar;
  that is fixture-only QA composition and these images are not approved listing media.
- `inactive-interruption-red.log`: one new native method, two assertion failures reproducing the
  false resumed message while inactive, despite no new microphone run.
- `optional-ai-red.log`: a test-only invalid enum case prevented compilation; no product result.
- `optional-ai-red2.log`: four new native methods, 25 assertion failures reproducing queued
  manual/selection provider starts, inactive queued/held title naming, and vocabulary scheduling/
  banner publication after inactivity. These are actual regressions, separate from the earlier
  green source; their final fixed-source results are recorded with release-owner validation.
- `optional-final-green.log` is a failed attempt despite its filename: 111 native methods had one
  test-isolation failure (a second case restored the previous case's completed summary), and three
  UI methods had one version failure because the generated project still built 40 instead of the
  configured 41. The new privacy/interruption assertions, Home/return and large-text release-history
  journey passed. Exit 65 was reaped and all 601 frozen inputs were unchanged. The isolated test
  setup and generated project require correction before a new green claim.
- `optional-final2-green.log`: after isolating each queued-summary case, regenerating the version-41
  project and preserving the existing requested-Undo-on-Stop intent, 111 native methods and two UI
  methods passed, TEST SUCCEEDED, exit 0/reaped. All 604 frozen source/test/config/generated-project
  hashes matched afterward. The UI methods cover Home/return/Stop and version-41 notes/reopen. The
  unchanged expensive large-text history method passed in the preceding attempt and was not rerun
  in this focused retry; full local validation must run it again on final source. Four exported
  native-resolution images in `ui-final2-attachments/` were inspected; version/build, disclosure and
  recorder counters match the assertions. Continuity images retain the synthetic QA probe and are
  not listing media. `ui-final2-review.json` records image hashes and limits.

`make lint` and `make bdd-check` passed after the helper follow-up (149 catalog scenarios). Full local validation, independent
review, hosted checks, merge and any authorized distribution remain separate requirements.

The simulator-only `--recording-continuity-fixture` is compiled only for Debug simulator builds.
It hosts the real meeting view and session, receives actual scene phases, and displays recorder
start/stop/background counters. Its recorder generates text without microphone capture or network
access. Home/return and Stop screenshots are QA evidence, not listing media, physical lock-screen
acceptance or speech/model-quality evidence. Confirm this flag is absent from Release binaries.

## Remaining physical acceptance

On a supported iPhone and iPad, begin in the foreground and confirm Listening before providing
known speech. Lock beyond the ordinary suspension interval, provide further speech, unlock and
verify continuous words/times and the same elapsed start. Repeat with saving on/off, real supported
advanced and fallback speech modules, a call/route interruption and explicit Stop. Stop and a later
foreground return must not reopen capture. Preserve the exact build, device, OS, source, native
screenshots and outcomes. Simulator lifecycle tests cannot establish actual background SpeechAnalyzer
availability, hardware audio quality or battery performance; do not claim a physical pass from them.

## Full-validation UI follow-up

The first aggregate validation at `b84973e162c86fe1195e3e3a27971959a0abfa4d` was interrupted after
two actual UI failures; iOS unit, Mac, Watch and real-server stages had not been reached. This is a
failed aggregate, regardless of the earlier focused passes. Evidence under
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-ios1201-continuity/ui-failure-investigation/`
preserves the original 2,106-file result bundle with matching hashes, its failure AX attachments,
bounded traces and subsequent exact-source reproductions.

The long-conversation test deterministically tried to swipe `dashboardScroll` in a portrait layout
that instead exposes the Quick panel's own reading scroll. With the new recording notice, the Quick
output was below that viewport. The other failure occurred after a Summary tap, with AX still saying
Live selected; its provisional-summary assertion was never reached. That unchanged manual test
passed both alone and after the failing Quick test, with screenshots confirming provisional text
then its removal. The intermittent missed transition is preserved as a failure, not explained away
as a model defect or claimed as a reproduced product fix. The ordered pair's native exit was 65;
its bounded screen recording exited 0/reaped, and all 918 source hashes matched. The actual Quick
video frame is `repro-pair/quick-video-14.5.png`; earlier 14.8/15.5-second frame estimates show
SpringBoard and are explicitly not Quick evidence.

`CONTINUITY-005` updates only the UI test/navigation contract. The test scrolls the existing outer
or Quick reading area with six bounded attempts, checks final output hittability, and verifies the
requested Summary selection and visible generation control. It retains Monday/Sarah, Catching up,
no-Refresh and provisional-to-final content assertions. Production UI and model behavior were not
changed by this follow-up. The whole six-method incremental-summary UI class passed in 214.076
seconds, TEST SUCCEEDED, exit 0/reaped, with all 918 recorded inputs unchanged during that run.
Three inspected native screenshots in `helper-green/attachments/` confirm visible Quick content
and both Summary states; the scrolled Quick image does not show the offscreen status, whose
Catching up assertion passed separately. These are synthetic QA images. Full validation must run
again on the final committed source before any merge or publication claim.

## Recording in landscape Duo

`CONTINUITY-006` adds an actual portrait-recording → landscape-Duo → Stop journey, including panel
frames, usable transcript/model controls, Quick content, disclosure accessibility and one start/stop.
Its first run (`duo-baseline`) failed four assertions. The debug simulator probe was then changed from
a safe-area inset to a non-layout, non-hit-testing overlay, and screenshots switched to native
`XCUIScreen` capture to avoid the application crop artifact after rotation. That harness repair did
not fix Duo: `duo-overlay-green` is a failed attempt despite its name. Home/return passed, but the
landscape method still failed the same four assertions, with identical AX workspace geometry.

The separate recording-notice row left about 161.7 points of workspace, below the existing 180-point
Duo threshold; the transcript stacked above Quick, which was below the fold. The compact,
non-accessibility header now keeps concise visible disclosure inline with title/status, preserving
the full explanation as its accessibility label. Portrait and accessibility text retain the full
paragraph. The global layout thresholds are unchanged. This is an observed candidate regression
and a small production header fix, distinct from the debug probe/screenshot harness repair.

`duo-inline-green` passed both Home/return and landscape Duo/Stop, two UI methods, zero failures,
24.538 seconds, TEST SUCCEEDED, exit 0/reaped; all 918 recorded inputs matched during the run.
Inspected native portrait, landscape recording and landscape Stop screenshots show the full portrait
notice, side-by-side panels with usable controls and inline notice, and enabled Start after Stop.
The compact notice's full accessibility label passed its assertion. QA transcript/placeholder content
can be partially scrolled/clipped inside its reader; these probe-bearing images are not listing
media. Physical recording, speech quality and locked-device acceptance remain pending. Full local
validation must restart on the final committed source, and candidate release media must be recaptured
from that source before distribution.


## Cold-launch foreground readiness follow-up

Full validation at `73c61889dffffdb18b622ca04b17b907aca07e13` failed seven UI methods with
20 assertions; the 494 iOS unit methods completed with seven optional skips and no failures.
Mac, Watch and real-server stages were not reached. The failed aggregate remains a failure.
The unchanged five-method reproduction in
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-ios1201-continuity/ui-selection-investigation/repro-five/`
failed all five methods, native exit 65/reaped in 147.689 seconds, with all 918 source hashes
unchanged. Its bounded, silent simulator video exited 0/reaped. Native failure AX and extracted
frames are preserved with `visual-diagnosis.json`; these are QA diagnostics, not listing media.

The actual selection menu was disabled while the app was visible, saying “Return to ListenToMe
to summarize selected lines.” Tapping it left the same menu open; no selection summary sheet or
provider response was reached. The fixture's separate session had not received actual scene
updates, so its initial activity-based availability stayed stale. The transcript/design fixtures
also attempted model preparation during initialization, before the app was active, without an
active retry. The landscape capture and native AX show “Speaker labels: models not loaded” plus
Retry and a 710-by-116-point dashboard in an 874-by-402-point window. This is separate from the
earlier recording-notice height regression: these sessions were idle. The failed sheet-rotation
journey then left landscape orientation for later portrait tests.

`CONTINUITY-007` specifies observable cold-launch and Home-return readiness without changing the
conversation or provider. The app and affected fixture owners explicitly forward their actual
initial scene phase and later transitions to their own session. Simulator fixtures isolate shared
and Watch inboxes and use synthetic recording/speaker adapters; production activity checks remain
in force. Selection tests require an enabled action before tapping and retain selected-line answer
and rotation assertions. The added Home-return case is new coverage, without an invented earlier
red run. Initial portrait isolation and teardown prevent a failed rotation test from contaminating
following journeys. Focused follow-up results are recorded below; complete validation remains pending.


The scene bridge owns its pending asynchronous delivery. Every actually observed inactive/background
phase synchronously suspends optional work before a later active phase can coalesce delivery;
background also revokes an unfinished microphone Start. A later active phase cannot revive that
cancelled preparation, while an established capture stays on its original run. Detaching an owner
cancels obsolete pending activation, preserving the latest nonactive privacy suspension. Native
cases use held real session/provider requests and injected capture preparation, rather than only
counting bridge calls.

The bridge evidence is explicitly scoped in `bridge-evidence-interpretation.json` beside the UI
investigation. `bridge-red` was a compilation failure, not a product red. `bridge-red2` included an
incorrect expectation that an answer begun before actual inactivity should survive; that expectation
and its subsequent green attempts are superseded and are not accepted privacy evidence.
`bridge-privacy-red3` is the corrected regression: five methods, four assertion failures for absent
immediate provider cancellation and a pending Start incorrectly reaching recording.
`bridge-privacy-green3` passed all five native methods with exit 0/reaped and all 923 input hashes
unchanged. That run precedes the recording fixture's final switch from duplicate direct scene
handlers to the same production bridge; the following rendered journeys exercise that integration.

`lifecycle-ui-green` is a failed run despite its filename: 14 methods, 13 passed and one new method
failed two assertions because it queried the editable conversation title as static text. The actual
cold-launch/Home-return enabled-menu, selected-line answer, original text and on-device destination
assertions passed. Both recording journeys and all seven originally failing methods passed. The
run exited 65/reaped in 304.281 seconds with all 923 recorded inputs unchanged. The title query was
then corrected to the actual `conversationTitle` text field and its value; no application code was
changed. Only the affected new cold-launch/Home-return method was repeated in
`lifecycle-cold-green`: one passed, TEST SUCCEEDED, exit 0/reaped in 37.614 seconds, with all 923
recorded inputs unchanged. These are separate focused receipts, not a single successful aggregate.

Native attachments from both runs are preserved. Inspected corrected-run images show the enabled
menu and exact one-line answer before and after Home, with the same conversation title and selected
text. The broader run also shows actual-bridge Home/return with one recording, recording Duo and
Stop, translated Duo and the speaker-ready workspace without Retry. Probe-bearing and scrolled
transcript images are QA-only, not release-listing approvals. The original full-validation failures,
all superseded attempts and their exact source manifests remain intact. Full local validation on
the final committed source, hosted checks, merge, fresh candidate release media and any authorized
upload remain required; physical background/audio acceptance is still pending.


The final catalog separates the UI readiness journey (`CONTINUITY-007`), immediate old-answer
cancellation and new-answer fencing (`CONTINUITY-008`), detached-owner privacy (`CONTINUITY-009`)
and pending-versus-established capture through rapid reactivation (`CONTINUITY-010`). The same
five native and rendered assertions remain; this is a scenario clarification without application
changes or an invented additional test run. The earlier 150-scenario checks remain historical;
final `make bdd-check` validates 153 catalog scenarios. `make lint` completes with no errors, and
local documentation links and `git diff --check` pass. Complete validation remains pending.
