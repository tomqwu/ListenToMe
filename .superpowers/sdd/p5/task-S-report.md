# Task S — #136 + #147 (macOS lifecycle/UX papercuts; preparing state & teardown follow-ups)

- **Branch:** `fix/136-147-mac-papercuts-teardown` (rebased onto `origin/main` @ `231979b`)
- **PR:** https://github.com/tomqwu/ListenToMe/pull/170 — body says `Closes #136` and `Closes #147`
- **Status:** complete; every checklist item of both issues addressed, with three explicitly scoped
  deferrals noted below and in the PR body.

## Commits (one per checklist item where practical)

| Commit | Item |
| --- | --- |
| `8493297` | #147 — distinct `isPreparing` state that gates automatic reviews |
| `c6733da` | #147 — `start()` uses the cancellation-racing prepare wait |
| `b07c859` | #147 — injectable capture-pump drain grace; `drain` doc comment moved back; unused mocks removed |
| `fe8c1eb` | #147 — skip the eager `.others` analyzer when Screen Recording is unavailable |
| `8d480f2` | #147 — WhisperKit model-load continuation wait instead of the 50 ms poll |
| `c18abe6` | #136 (1) — rail Engine label follows the live run |
| `1dd9450` | #147 — rail/header render the preparing state (PREP, "Preparing…") |
| `28e05d3` | #136 (2, 5) — window-only menu items disabled; Session menu shortcuts; footer; a11y; Reduce Motion |
| `2757535` | #136 (3) — Quit & Reopen finalizes before launching the replacement |
| `9f1c0b3` | #136 (4) — en-US locale fallback is surfaced |
| `5b572aa` | #136 (6) — calendar title; denial vs no-meeting; dismissable banner |
| `03771a8`, `ea4f4a1` | Docs (README, manual smoke test) |
| `e5ebd94` | Review follow-up — preparing gates for the transcript chip and speaker analysis, plus the three minors |

## What changed

### #147

- **`MeetingSession.isPreparing`** (`Sources/ListenToMeCore/MeetingSession.swift`): true from Start
  until the transcriber pipeline is warm. Gates `automaticReviews.synchronize(enabled:)`,
  `evaluateLiveQuick()`, the `LiveSummaryScheduler.Snapshot.recording` flag and the in-flight
  `isCurrent` guard (all in `MeetingSession+AutomaticReviews.swift` after the upstream file split);
  both `autoQuickStatus` and `automaticReviewStatus` report
  "Auto paused · Preparing on-device speech model…". Cleared in `beginStop()` and on the
  capture-start failure path. UI: `RailRecStatus` renders **PREP** + spinner, the header says
  "Preparing…".
- **`start()` prepare wait**: now `Self.prepareRacingCancellation(transcriber)`, matching the import
  path, so a Stop during a download whose platform call ignores cancellation cannot park the start
  task (and therefore cannot leave a second concurrent download on the next Listen).
- **Eager `.others` analyzer**: `SpeechAnalyzerTranscriber(locale:warmSystemAudio:)`. `prepare()`
  warms `[.you]` only when the flag is false. `MeetingView` derives it from the new prompt-free
  `PermissionsModel.systemAudioLikelyAvailable()` (CoreGraphics preflight OR the live window-name
  check). `feed` still builds the pipeline lazily, so a false negative costs only the warm-up; the
  import path keeps the default `true` (imports feed `.others`).
- **WhisperKit model-load polling**: `modelBox()` suspends on a `CheckedContinuation` via
  `withTaskCancellationHandler`. `finishModelLoad()` wakes waiters when the load settles;
  `finish()` calls `releaseModelWaiters()`. `cancelledModelLoadWaiters` guards the race where the
  cancellation handler runs before the continuation registers.
- **Timing-sensitive test**: `capturePumpDrainGrace` is a `Duration` init parameter (default
  unchanged, 250 ms) threaded into the now-parameterised static `drain(_:grace:)`.
  `testChunksBufferedAtStopAreStillFedBeforeFinalize` injects 10 s.
- **Test tidy-ups**: `testTranscribeAudioPreparesBeforeTheFirstChunk` and
  `testCancellingAnImportDuringPrepareReturnsPromptly` each constructed a throwaway
  `MockTranscriber()` for the session and then passed a *different* one to the call under test —
  both now pass the mock they actually assert on. `drain`'s doc comment was moved back onto `drain`
  (it had drifted above `DoneFlag`).

### #136

1. **Engine label** — new Core `TranscriptionEngineLabel` (`name(_:)`, `rail(active:saved:)`).
   `MeetingView.activeEngine` is snapshotted immediately before `session.start()` in both
   `toggleCapture` and `restartForLocaleChange`, and cleared on stop / start failure /
   `prepareToClose`. Rail shows `SpeechAnalyzer · WhisperKit next start` when they disagree.
2. **Closed-window menu items** — `.disabled(actions == nil)` on Export / History / Settings.
   I took the issue's *first* recommendation (disable, mirroring New/Save) rather than adding a real
   `Settings` scene + `openWindow`, because the latter needs a pending-command queue consumed by
   `MeetingView.onAppear` and that file is being edited concurrently by two other agents.
3. **Quit & Reopen** — `relaunch()` is now a `Task { @MainActor }` that awaits
   `ApplicationLifecycle.shared.prepareToClose?()` first, returns without launching anything when it
   is refused, and clears `prepareToClose` before terminating.
4. **Locale fallback** — `supportedLocale(for:)` returns `(locale:fellBack:)`; the status rail shows
   `TranscriptionLocaleStatus.fallback(requested:resolved:)` when it fell back. Both status strings
   keep the `"Transcription:"` prefix `stopAndWait()` looks for (asserted in a test).
5. **Shortcuts / a11y** — `ConversationCommands` grew `isCapturing`, `canToggleCapture`, `canUseAI`,
   `toggleCapture`, `deepAnswer`, `recap`, `refreshSummary`; new `CommandMenu("Session")` with
   ⌘⇧L / ⌘⇧D / ⌘⇧R / ⌘⇧U. `MeetingView.toggleCapture` de-privatised. Footer lists exactly the wired
   set (nine hints, spacing 18→12) and its stale "labels only" comment is replaced by a
   keep-in-step note. `.accessibilityLabel("Copy \(title) text")` on the pane Copy button;
   `RecordingIndicator` gates its `repeatForever` pulse on `@Environment(\.accessibilityReduceMotion)`
   and stops an already-running pulse via `onChange`.
6. **Calendar** — `CalendarService.currentOrNextMeeting()` returns the new Core
   `CalendarLookup` (`meeting`/`noMeeting`/`denied`/`failed(String)`) with `message` and
   `offersPrivacySettings`. `loadFromCalendar` sets `conversationTitle` when
   `ConversationTitle.isGenerated(conversationTitle)` (new Core helper, also used for the two places
   that build the default title). The banner gained an **Open Calendar privacy settings** button
   (shown via a *computed* `calendarDenied` derived from `startError`, so it can never disagree with
   the visible message) and a ✕ dismiss.

### Review follow-up (`e5ebd94`)

Both gates the reviewer asked for, plus all three minors:

- **`transcriptStatusLabel`** said "live" throughout PREP. The rule moved to Core as
  `TranscriptStatusLabel.text(isRunning:isPreparing:sources:)` — so it *is* testable —
  and now returns `"preparing"`. New `TranscriptStatusLabelTests` (3 tests) covers
  idle / preparing-never-reads-live (including with a previous run's sources still in the store) /
  the live source count.
- **Speaker-analysis timer** (`App/MeetingView.swift`, the per-second `onReceive`) now also requires
  `!session.isPreparing`. No audio has reached the diarization sink yet at that point, so an
  analysis would run against the previous run's leftovers — the same rationale as the automatic-review
  gate.
- **Reduce Motion**: `RecordingIndicator` now routes both `onAppear` and `onChange` through one
  `applyPulse(reduceMotion:)`, so turning Reduce Motion back **off** restarts the pulse instead of
  leaving the dot static until the view reappears.
- **`ConversationTitle`** moved out of `CalendarLookup.swift` into `ConversationTitle.swift`, and its
  test moved into `ConversationTitleTests.swift` (2 tests, one new: the generated-title format).
- **Smoke test**: step 4 now checks that all nine footer hints and the AI-mode label stay readable at
  the window's 1100 pt minimum width; step 2 was rewritten to cover the preparing chip and the
  speaker-analysis gate alongside the automation gate.

### Issue hygiene (CLAUDE.md DoD)

The three deferred #136 items are now tracked, so "Closes #136" is honest:

- **#172** — "Populate transcription language pickers from `SpeechTranscriber.supportedLocales`
  (macOS + iOS)", `enhancement` + `priority: P2`, "Part of #98", with the concrete file/line evidence
  and a done-when list.
- **#173** — "Split exportError from startError so one banner can't hide or outlive the other",
  `enhancement` + `priority: P3`, "Part of #98".
- **#124** — a checklist item for the user-configurable global hotkey added as a
  [comment](https://github.com/tomqwu/ListenToMe/issues/124#issuecomment-5682184370), noting it pairs
  with that issue's existing `RegisterEventHotKey` migration.

All three are linked from the PR body's "Follow-ups" section.

## Verification

| Command | Result |
| --- | --- |
Re-run after the review follow-up commit `e5ebd94`:

| Command | Result |
| --- | --- |
| `swift test` | **438 tests, 0 failures, 3 skipped** (was 434 before the follow-up) |
| `./scripts/check-coverage.sh 95` | **PASS — 97.78%**; the five new Core files 100% |
| `make gen && make build` | **BUILD SUCCEEDED** |
| `make lint` | 332 warnings, identical to `main`; the one `error` (`iOS/MobileReleaseNotes.swift:53`, 182-char line) is pre-existing and unchanged |
| `gh pr checks 170` | Core tests+coverage / macOS build / iOS build — all **pass** on the first push; re-watched after `e5ebd94` |

New tests: `TranscriptionEngineLabelTests` (5), `TranscriptionLocaleStatusTests` (3),
`CalendarLookupTests` (3), `ConversationTitleTests` (2), `TranscriptStatusLabelTests` (3), and in
`TranscriberPrepareTests`: `testSessionIsPreparingUntilTheSpeechModelIsWarm`,
`testAutomaticReviewsDoNotDispatchWhilePreparing`,
`testStopDuringAnUncancellablePrepareDoesNotParkTheStartTask`.

**Not run:** the GUI paths. `App/` has no test target, so every UI behaviour above is covered by a
manual step instead — `docs/manual-smoke-test.md` gained an eight-step
"macOS lifecycle and UX papercuts (#136, #147)" section, two of whose steps need a machine without
the speech model installed and a Calendar denial.

Note: the local Xcode license *was* unaccepted at the start (both `swift test` and `xcodebuild`
refused). I worked around it by building Core with the CommandLineTools toolchain and type-checking
the tests with `swiftc -typecheck` against the built module plus Xcode's XCTest framework. The
license was accepted mid-task (presumably by another session), so the numbers above are from real
`swift test` / `make build` runs, not from the workaround.

## Concerns / deliberate deferrals

1. **Three parts of #136 are deferred but now tracked** (#172, #173, and a checklist item on #124 —
   see "Issue hygiene" above), so closing #136 with this PR does not lose them:
   populating the language pickers from `SpeechTranscriber.supportedLocales`; a user-configurable
   global hotkey; splitting `exportError` from `startError`.
2. **`PermissionsModel.systemAudioLikelyAvailable()` can read false negative** right after a grant
   made without relaunching (the CoreGraphics preflight is process-cached and the window-name check
   is inconclusive when no titled windows are on screen). The consequence is bounded: only the eager
   warm-up of the system-audio pipeline is skipped, and `feed` builds it lazily. I chose to err low
   deliberately.
3. **The `Session` menu is a new top-level menu.** If the reviewers would rather have these items
   inside an existing menu group, it is a one-line move.
4. **Concurrent-edit risk.** I rebased onto `origin/main` @ `231979b` mid-task; the only conflict was
   the upstream split of `MeetingSession`'s automatic-review extension into
   `MeetingSession+AutomaticReviews.swift`, which I resolved by re-applying the `isPreparing` gating
   into the new file. I did not touch `SpeechRecognizerTranscriber.swift`, `SpeakerAudioBuffer.swift`,
   `SpeakerDiarizer.swift`, `MeetingView+Speakers.swift`, `MeetingSession.ingest/respondQuick`, or the
   Quick pane header. I did touch `MeetingView.swift`, `MeetingView+Conversations.swift`,
   `CommandCenter.swift` and `CommandCenterPanes.swift`, so the #112 agent may see conflicts in the
   Quick-pane region of `CommandCenterPanes.swift` (I only edited the rail's `RailRecStatus` /
   Engine lines there).
