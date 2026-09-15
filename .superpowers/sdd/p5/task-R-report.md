# Task R — Issue #112: re-wire proactive question answering

Branch: `feat/112-proactive-rewire` (from origin/main `acb556a`) · PR https://github.com/tomqwu/ListenToMe/pull/168 ("Closes #112")

## Decision implemented
Re-wire, not delete (controller decision). The feature is advertised in README and the smoke test and is a live-copilot differentiator.

## Core (`Sources/ListenToMeCore/MeetingSession.swift`)
- `ingest(_:)` now calls a new private `fireProactiveIfWarranted(for:)` after `handleLiveEvent(.transcriptChanged)`.
- Guard chain: `proactiveEnabled`, `isRunning`, `aiEnabled`, `!streamingRoles.contains(.quick)`, `providers[.quick] != nil`, `providerAvailability(models[.quick] ?? "") == nil`, and `context.shouldFireProactive(for:now: clock())` (which supplies the own-speech exclusion, the is-final/is-question checks and the debounce).
- The fire runs in a stored `proactiveTask`, **not** awaited by `ingest`: awaiting a full LLM stream inside `ingest` would stall the transcriber's segment pump. The task re-checks `runID == run`, `isRunning`, `proactiveEnabled` before calling `respondQuick(.proactive)`, so a question from a finished/restarted run cannot answer into the next one. `beginStop()` and `resetConversation()` cancel it (`resetConversation` already rebuilt the `ContextEngine`, which resets the debounce).
- Because the path is `respondQuick`, the answer goes through `startRoleTask` → `run(.quick,…)` → `manualQuickAnswer.completed(at:)`, i.e. it sits in the same manual-answer freshness state as a button press: the automatic recap cannot overwrite it mid-read, and **Show recap** returns to the recap. It is independent of `autoSummaryEnabled`.
- Added internal (`@testable`) `awaitProactiveFire()` so tests can await the fire plus the Quick stream deterministically.
- Deleted the unused `listenerDebounce` init parameter and all call sites (8 test files).
- `proactiveEnabled` gained a doc comment stating the default and the relationship to Auto.

## macOS UI
- `App/CommandCenterPanes.swift`: a **Proactive** checkbox in the Quick pane's `headerExtra`, with help text, writing `MeetingView.proactiveDefaultsKey`.
- `App/MeetingView.swift`: `static let proactiveDefaultsKey = "proactiveQuickAnswers"`, restored in `.onAppear` with `object(forKey:) as? Bool ?? true` so the documented default (on) survives an absent key (`bool(forKey:)` would have defaulted it off).

## iOS
No change. iOS captures a single microphone source and has no `.others` channel, and `MobileSession` shares `LiveSummaryScheduler`/`QuickSummaryReader` but not `MeetingSession`. Documented in `docs/SHARED-LIVE-SUMMARY.md`.

## Tests
- New `Tests/ListenToMeCoreTests/ProactiveQuickTests.swift` (11 tests): fires once for an Others question; the answer holds the pane like a manual one; debounce (fires, suppressed at +3s, fires again at +13s via an injected `TestClock`); does not fire for your own question, non-question speech, a non-final segment, when disabled, when not running, when AI is off, when the Quick model is unavailable, or while a manual Quick is still streaming (`GatedProvider` holds the stream open). All negatives assert `RecordingProvider.requestCount == 0` after awaiting the work — never a synchronous read of `quickSuggestion`.
- `Mocks.swift`: `RecordingProvider` now records every request (`requests`, `requestCount`).
- `MeetingSessionTests.swift`: the four vacuous negatives removed; the remaining `testIngestDoesNotGenerate…` renamed to `testIngestDoesNotGenerateAnAutomaticRecapWithoutAutoOptIn` and now disables proactive to isolate the recap path.
- `MeetingSessionIntegrationTests.swift`: test 3 rewritten as `testPumpFiresProactiveQuickForARemoteQuestion` (asserts the answer arrives through the real pump) plus `testPumpStaysQuietForARemoteQuestionWhenProactiveIsOff`.
- `SharedQuickLoopTests.testAReviewCompletingAcrossANotesEdit…` sets `proactiveEnabled = false` with a comment: it gates the Quick provider to one response, which a proactive answer would consume.

### Mutation check (proof the negatives can fail)
1. Replacing the whole `ingest` guard chain with `isQuestion && isFinal` → own-speech, model-unavailable and debounce tests fail.
2. Additionally neutralising the task's `runID/isRunning/proactiveEnabled` guard and `startRoleTask`'s `aiEnabled` guard → disabled, not-running and AI-off tests fail too (10 failures total).
Guards restored; suite green afterwards.

## Verification
- `swift test` → 420 tests, 3 skipped, 0 failures.
- `./scripts/check-coverage.sh 95` → PASS, 97.65%.
- `make gen && make build` → BUILD SUCCEEDED.
- iOS build/tests not run (no iOS sources touched).
- The new checkbox was not exercised in a running app (no manual `make run`); it compiles, and step 7 of the smoke test now covers it.

## Docs
- `README.md` Quick bullet: describes the Proactive checkbox, the default, the own-speech exclusion, the debounce, non-interruption of a manual answer, and independence from Auto.
- `docs/manual-smoke-test.md` step 7: expanded into a falsifiable procedure (fires once; a repeat inside ~8s must not fire; your own question must not fire; off → nothing, and the choice survives a relaunch).
- `docs/SHARED-LIVE-SUMMARY.md`: new paragraph on how Proactive relates to Auto and why iOS has none.
- `CHANGELOG.md` untouched (release-time; no version bump per the brief).

## Concerns / notes
- Removing the `listenerDebounce` public init parameter is a public API change to `ListenToMeCore`; it had no readers in the initializer body, but any out-of-repo caller would break.
- The debounce is `ContextEngine`'s (default 8s in the app's construction path); it is shared with nothing else, and `resetConversation` resets it.
- The Quick pane header now has a checkbox plus a conditional "Show recap" button; layout in a narrow pane was not visually verified.

---

## Round 2 — review follow-up (commits `4832b3c`, `7e04acc`; merged origin/main `231979b`)

### 1. Cancellation / run-ID coverage — gap closed, and it found a real bug
Writing the requested test showed the run-ID guard did **not** hold: `start()` restores `isRunning` and bumps `runID` only *after* awaiting the previous teardown, so a proactive task body scheduled inside that await saw a live session under the run ID it had captured and fired into the new run. `testAProactiveFireScheduledBeforeStopDoesNotAnswerIntoTheNextRun` failed on the original implementation.

Fix: the task now guards on `!Task.isCancelled` (the signal `beginStop()` actually sends) plus `isRunning`/`proactiveEnabled`. The `runID == run` comparison was **removed**: with cancellation in place it is provably unreachable — removing it alone leaves the suite green, because every path that changes `runID` (stop, stop+restart) cancels the task first. Keeping it would have been exactly the untested-dead-branch pattern issue #112 is about. The `proactiveTask?.cancel()` in `resetConversation()` was removed for the same reason (a reset is only legal after a stop, which already cancelled) and replaced by a comment.

New `ProactiveQuickCancellationTests` (4 tests, gated provider): scheduled-then-stopped never reaches the provider; does not answer into the next run after a restart; an answer already streaming when the session stops never lands in the pane; a reset leaves nothing behind. Mutation-checked: removing `proactiveTask?.cancel()` from `beginStop` **or** the `!Task.isCancelled` check fails the restart test.

### 2. Tautological pane test — replaced
`testProactiveAnswerHoldsTheQuickPaneAgainstANewerAutomaticRecap` now runs Auto alongside (a `SplitQuickProvider` answers `quickEvaluation` with a publish decision and everything else with prose), waits for `quickRecap` to become `- The ETA is Monday.`, and asserts `quickSuggestion` still holds `PROACTIVE ANSWER`, `quickAnswerOverridesRecap` is true, and `dismissQuickAnswer()` returns to the recap.

### 3. Bounded poll
`testProactiveDoesNotInterruptAManualQuickThatIsStillStreaming` now uses a `settle(50)` yield-poll both to wait for the manual request and to give an unguarded fire every chance to reach the provider.

### Minors
- `SharedQuickLoopTests.testMacAutomaticReviewsCarryAttributionNotesAndUserDirectives` sets `proactiveEnabled = false` with a comment.
- Quick pane placeholder: "With Proactive on, a question from Others is answered here automatically. Enable Auto while listening, or request a recap."
- Both leftover trailing commas removed (`MeetingSessionTests` helper signature, `MeetingSessionIntegrationTests:162`).
- Proactive test fixtures moved to file scope so neither class trips SwiftLint's `type_body_length`.

### Merge with main
`origin/main` had advanced to `231979b`; merged in. `Tests/ListenToMeCoreTests/CoreReviewPapercutTests.swift` (from #166, landed after this branch was cut) passed the deleted `listenerDebounce:` argument — dropped in `7e04acc`. This was the CI failure on the first push of round 2.

### Verification (round 2, final)
- `swift test` — 432 tests, 3 skipped, **0 failures**
- `./scripts/check-coverage.sh 95` — PASS, 97.79%
- `make gen && make build` — BUILD SUCCEEDED
- `make lint` — 331 findings, all pre-existing (the one `error:` is `iOS/MobileReleaseNotes.swift`, untouched); the round-1 `ProactiveQuickTests` `type_body_length` warning is gone, so this branch adds none
- CI on `7e04acc`: ListenToMeCore tests + coverage **pass**, macOS 26 app build **pass**, iOS 26 app build **pass**
