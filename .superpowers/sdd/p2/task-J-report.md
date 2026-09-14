# Task J — #123 (iOS Apple manual Quick) and #125 (calendar import privacy)

Branch: `fix/123-125-ios-apple-quick-calendar` (from `origin/main` @ 09b2b80).

## #123 — design decision

The brief offered two shapes. I chose **the prose Quick prompt on the Apple path, skipping the JSON
parser**, rather than a `@Generable` mirror of `QuickSummaryDecision`:

- `QuickSummaryDecision` lives in `Sources/ListenToMeCore`, which is a cross-platform SwiftPM library
  and cannot import FoundationModels. A `@Generable` mirror would have to live in `SharedPlatform/`
  and be kept in sync with the Core decision by hand — two schemas for one contract.
- Manual Quick only ever uses `decision.summary` (the bullets). `action`, `context` and `reviews`
  exist for the *automatic* loop's incremental memory and review recommendations, which the Apple
  path does not run (`AppleIntelligenceProvider` still refuses `.quickEvaluation`). Guided generation
  would force the ~3B model to produce three fields nothing reads.
- Guided generation is untestable without the real model; the prose path is exercised end to end in
  `iOSUnitTests` with a stubbed transport, which is what the issue asked for.

Implementation:

- `Sources/ListenToMeCore/QuickSummaryContext.swift`: `manualProseInstructions` (bullets only, keeps
  the "Notes: " grounding and the no-instructions/no-invention rules) and `proseSummary(_:)`, a
  lenient reader that tolerates `-`/`*`/`•`/`1.`/`1)` markers, a heading above the list and stray code
  fences, caps at three bullets and 240 characters each, and returns nil for "No key takeaway yet."
  or JSON-looking output.
- `iOS/MobileSession.swift` (confined to the summarize provider branch + `summaryAvailability`):
  the direct `LanguageModelSession` call is gone. Every provider now streams through one transport —
  `summaryProvider ?? (cloud ? ai.client(for:) : AppleIntelligenceProvider())` — so the Apple path
  gets the shared provider's guards and error mapping. Manual Quick on the Apple path sends
  `manualProseInstructions` and reads the answer with `proseSummary`; the JSON envelope and
  `QuickSummaryDecision.parse` remain for Ollama.
- `SharedPlatform/AppleIntelligenceProvider.swift`: `message(for:)` maps every
  `LanguageModelSession.GenerationError` case (context window, guardrail, unsupported locale, assets,
  rate limited, concurrent, decoding/guide, refusal) to text that names the cause and the way out;
  `stream` rethrows them as `QuickSummaryError.message`, so macOS gets the same wording.
  `unavailableReason(for:)` also checks `SystemLanguageModel.default.supportsLocale`.
- `iOS/MobileSession.summaryAvailability(for:)` reports an unsupported conversation language
  (`Locale(identifier: language)`) *before* Generate, next to the other availability reasons.
- `iOS/MobileAISettings.errorMessage` falls back to the same Apple mapping.
- Test seam: `MobileSession.onDeviceProviderOverride` (tests only) stands in for the on-device
  transport, so the simulator — where Apple Intelligence is unavailable — can run the path.

## #125 — calendar import

- `MobileCalendarEvent.link(_:)` keeps scheme/host/path and drops query, fragment and user info, so a
  `?pwd=…` join passcode never reaches notes; a URL with no scheme/host is omitted entirely.
- `MobileCalendar.attendeeNames(_:)` keeps display names only, matching `App/CalendarService.swift`.
  EventKit reports the address as `name` for an unnamed invitee, so a name containing `@` is dropped
  rather than published as an e-mail address.
- `iOS/Info.plist` `NSCalendarsFullAccessUsageDescription` now states which fields are imported, that
  notes go to the provider selected in Settings (Ollama Cloud or your own server) and are included in
  Share, and that addresses and join secrets are never imported.
- `docs/IOS.md` calendar section says the same; `docs/IOS.md` provider section documents the Apple
  prose Quick path and the new error/locale behavior; `docs/SHARED-LIVE-SUMMARY.md` records that the
  JSON decision contract is Ollama-only; validation checklist gained Apple-Quick and calendar steps.

## Verification

Commands run in this worktree:

| Command | Outcome |
| --- | --- |
| `swift test` | 295 tests, 3 skipped, 0 failures |
| `./scripts/check-coverage.sh 95` | PASS — coverage 97.32% |
| `make lint` | exit 0; no new violations (new Apple tests moved to their own file to avoid a type-body-length warning) |
| `make gen && make build` (macOS) | ** BUILD SUCCEEDED ** |
| `make ios-test IOS_DESTINATION='platform=iOS Simulator,id=A7BCE73A-6EE4-48B3-ADA3-EE8A2DD8A324'` | ** TEST SUCCEEDED ** — 89 passed / 8 skipped / 0 failed, twice (before and after the test-file split) |

The simulator (iPhone 17 Pro Max, iOS 26.4.1) was erased with `xcrun simctl erase` before each run and
was not one another process had booted (three other worktrees were running xcodebuild concurrently on
their own simulators). **The UI bundle did run**: `ListenToMeIOSUITests` appears in the xcresult with
its suites (MobileCalendarUITests, MobileWorkspaceUITests, …) and no failures.

TDD notes, honestly: the Core prose test was written first and run against the unimplemented API.
The iOS tests were written before any iOS build and failed to compile against the pre-change API
(`MobileCalendarEvent.link`, `MobileCalendar.attendeeNames`, `manualProseInstructions` absent) — red
first, but as compile failures rather than assertion failures.

Not verified: real Apple Intelligence hardware. The simulator has no on-device model, so the Apple
path is exercised through the injected transport only; the prose prompt's actual output quality and
the live GenerationError wording were not observed on device. docs/IOS.md's physical-device checklist
gained an Apple-Quick step (step 6) and a calendar-import privacy step (step 9) for that reason.

## Merge-safety with the concurrent #121/#122 agent

`iOS/MobileSession.swift` edits are confined to: the `onDeviceProviderOverride` property declaration
next to `summaryProvider`, the `.available` case of `summaryAvailability(for:)`, and the request /
transport / Quick-parse lines inside `summarize` (~:512-545). `importCalendarEvent` was not modified —
the calendar fix lives entirely in `MobileCalendar.swift`. No audio lifecycle handler, `save()`,
`refreshHistory` or debounce code was touched.

## Deliverables

- Branch `fix/123-125-ios-apple-quick-calendar`, commit `2e32cc5`.
- PR https://github.com/tomqwu/ListenToMe/pull/154 ("Closes #123", "Closes #125").

