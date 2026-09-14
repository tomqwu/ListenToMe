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


## Fix report (PR #154 review round 1)

**1. Important — #125 not achieved (invite text).** `MeetingContext` (Core) gained two public helpers:
`safeLink(_:)` — the single link rule (keep scheme/host/path, drop query, fragment and user info) —
and `redactingLinksAndAddresses(_:)`, which runs `NSDataDetector` over free text, reduces every link
with `safeLink` and removes every e-mail address (a detected address is a `mailto:` link, so bare
addresses are covered), then tidies the whitespace an removal leaves. `MobileCalendar.event` now runs
both `event.location` and `event.notes` through it, and `MobileCalendarEvent.link` delegates to
`safeLink`, so the event URL, the location and the body obey one rule. Tests: Core
`MeetingContextTests.testSafeLinkAndRedactionStripJoinSecretsAndAddressesFromInviteText` (realistic
Zoom body plus a Teams `?context=` URL) and iOS
`MobileCalendarTests.testInviteBodyAndLocationAreFilteredBeforeBecomingNotes`. Both assert that a
meeting ID and other body text survive, so the docs' claim matches the code. `iOS/Info.plist` and
`docs/IOS.md` now list exactly two filters (addresses; the secret-bearing part of links) and say
plainly that dial-in numbers, meeting IDs and other text are imported as written.

**2. Important — device locale must not gate availability.** `AppleIntelligenceProvider.unavailableReason`
is back to a pure `SystemLanguageModel.default.availability` switch, so macOS's status line and
`stream` guard and the iOS fresh-install default are untouched by any locale. The locale check now
exists only as `unsupportedLocaleReason(for:isSupported:)`, with the `supportsLocale` call injected as
a parameter, and only `MobileSession.summaryAvailability(for:)` calls it — with the *conversation's*
`language`, which is the value the old code disagreed with. Covered by
`MobileAppleIntelligenceTests.testUnsupportedConversationLanguageIsReportedWithoutDisablingTheProvider`
(supported, unsupported, and availability still equal to `defaultProviderReason`). A conversation whose
language is unknown still gets a clear message at generation time from the `unsupportedLanguageOrLocale`
mapping.

**3. Important — docs.** `docs/IOS.md` states the fallback reasons exactly as the code produces them
(ineligible hardware, Apple Intelligence off, model not ready, or the unlisted-reason string), says the
language check is per conversation and that availability is locale-independent, and states explicitly
that macOS behavior is unchanged apart from the shared provider's failure wording.
`docs/SHARED-LIVE-SUMMARY.md` says the same about the shared transport.

**Minors.** The "no takeaway yet leaves your previous summary in place" sentence is corrected (an empty
prose answer shows "No key takeaway yet."; only a *failed* request keeps the previous summary); a line
was added telling users that notes imported by earlier versions may still contain a passcode or address;
`proseSummary` drops a leading unmarked line ending in ":" when more lines follow (a lone such line is
still treated as the answer).

**Verification of the fix round**

| Command | Outcome |
| --- | --- |
| `swift test --filter QuickSummaryContextTests` / `--filter MeetingContextTests` | 12 and 7 tests, 0 failures |
| `swift test` | 296 tests, 3 skipped, 0 failures |
| `./scripts/check-coverage.sh 95` | PASS — 97.28% |
| `make lint` | exit 0; no new violations |
| `make gen && make build` (macOS) | ** BUILD SUCCEEDED ** |
| `make ios-build` | exit 0 |
| `xcodebuild … -only-testing:ListenToMeIOSUnitTests test` on an erased iPhone 17 Pro Max simulator | ** TEST SUCCEEDED ** — 62 tests, 4 skipped, 0 failures |

The simulator was shut down and `xcrun simctl erase`d before the run and was not booted by another
process. One earlier attempt of that run failed four pre-existing Keychain tests (`-34018`) because I
passed `CODE_SIGNING_ALLOWED=NO`; the repo's `IOS_SIGN_FLAGS` uses ad-hoc signing precisely so Keychain
tests exercise real storage, and with those flags the bundle passes. The UI bundle was not re-run in
this round (it passed twice on the previous commit and none of these changes touch UI code); `make
ios-build` is the compile proof for the app target.

- Fix commit: `a19e2cd`, pushed to `fix/123-125-ios-apple-quick-calendar`.
