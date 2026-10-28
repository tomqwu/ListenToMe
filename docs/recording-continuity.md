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

`CONTINUITY-001`–`CONTINUITY-004` in
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

`make lint` and `make bdd-check` passed after the final fixes (147 catalog scenarios). Full local validation, independent
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
