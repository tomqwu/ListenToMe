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

## Verification

| Command | Result |
| --- | --- |
| `swift test` | **434 tests, 0 failures, 3 skipped** |
| `./scripts/check-coverage.sh 95` | **PASS — 97.77%**; `TranscriptionEngineLabel.swift`, `TranscriptionLocaleStatus.swift`, `CalendarLookup.swift` all 100% |
| `make gen && make build` | **BUILD SUCCEEDED** |
| `swiftlint lint --quiet` | no new violations; the one pre-existing `error` (`iOS/MobileReleaseNotes.swift:53`, 182-char line) is unchanged from `main` |
| `gh pr checks 170` | Core tests+coverage / macOS build / iOS build — watched to completion |

New tests: `TranscriptionEngineLabelTests` (5), `TranscriptionLocaleStatusTests` (3),
`CalendarLookupTests` (4), and in `TranscriberPrepareTests`:
`testSessionIsPreparingUntilTheSpeechModelIsWarm`,
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

1. **#136 (4) is partially deferred.** Populating the language pickers from
   `SpeechTranscriber.supportedLocales` (macOS *and* iOS Settings, grouped Installed/Downloadable
   via `AssetInventory.status(forModules:)`) is a materially larger change than surfacing the
   fallback, and touches iOS files outside my assigned set. I implemented the "announce the
   fallback" half only, and said so in the PR body. If #136 must close fully, this needs a
   follow-up issue or a second pass.
2. **#136 (5) global hotkey is still fixed** at ⌘⇧Space — making it user-configurable means new
   Settings storage (keyCode+modifiers) plus validation against `ConversationMenu`, which is its own
   change. Flagged in the PR.
3. **#136 (6) `exportError` is not split from `startError`.** The banner is still shared; the ✕
   dismiss addresses the "stale message sits above a live recording" symptom but not the structural
   half. Flagged in the PR.
4. **`PermissionsModel.systemAudioLikelyAvailable()` can read false negative** right after a grant
   made without relaunching (the CoreGraphics preflight is process-cached and the window-name check
   is inconclusive when no titled windows are on screen). The consequence is bounded: only the eager
   warm-up of the system-audio pipeline is skipped, and `feed` builds it lazily. I chose to err low
   deliberately.
5. **The `Session` menu is a new top-level menu.** If the reviewers would rather have these items
   inside an existing menu group, it is a one-line move.
6. **Concurrent-edit risk.** I rebased onto `origin/main` @ `231979b` mid-task; the only conflict was
   the upstream split of `MeetingSession`'s automatic-review extension into
   `MeetingSession+AutomaticReviews.swift`, which I resolved by re-applying the `isPreparing` gating
   into the new file. I did not touch `SpeechRecognizerTranscriber.swift`, `SpeakerAudioBuffer.swift`,
   `SpeakerDiarizer.swift`, `MeetingView+Speakers.swift`, `MeetingSession.ingest/respondQuick`, or the
   Quick pane header. I did touch `MeetingView.swift`, `MeetingView+Conversations.swift`,
   `CommandCenter.swift` and `CommandCenterPanes.swift`, so the #112 agent may see conflicts in the
   Quick-pane region of `CommandCenterPanes.swift` (I only edited the rail's `RailRecStatus` /
   Engine lines there).
