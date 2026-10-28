# Translation validation — October 27, 2026

[PR #331](https://github.com/tomqwu/ListenToMe/pull/331) implements
[translation #330](translation.md). The frozen tested source is
`6c1542a6dd2f03135469db11ad0f103c6960dc3f`, based on
`164ef4b6adf2d18d64dc35f0fb5e8b064076ddda`. All 58 recorded file hashes matched after testing;
subsequent changes for this report are documentation only. No version, binary upload or store listing
was changed. This feature is absent from TestFlight 1.19.1 (39).

## Automated outcomes

| Check | Observed result |
| --- | --- |
| `make bdd-check` | 139 valid scenarios; new contracts `TRANSLATE-001`–`TRANSLATE-014` |
| Core coverage run | 1,254 tests, 7 opt-in/gated skips, zero failures; 98.2218% line coverage |
| iOS simulator UI | 79 tests, 5 gated/fixture skips, zero failures |
| iOS simulator unit | 460 tests, 7 gated/fixture skips, zero failures |
| Native Mac | 43 tests passed; every bound Mac selector observed on the complete rerun |
| Native Watch | 29 unit and 5 UI tests passed; both binding verifiers passed |
| `make e2e` | Signed Dev app build and real Ollama/OpenAI-compatible contracts passed with local `qwen3:0.6b` |
| Required hosted CI | All three jobs passed on the frozen source in [run 40566493399](https://github.com/tomqwu/ListenToMe/actions/runs/40566493399) |

The aggregate `make validate-local` **exited 2 at Mac log verification**. All iOS tests and 43 Mac
tests had passed, but a framework diagnostic split a selector in the middle of its stdout pass
record. Structured XCTest results independently report that exact method Passed. A complete
`make mac-test` rerun produced a clean log and verified every Mac binding; `make watch-test` and
`make e2e` then passed on the unchanged source. This is a completed component matrix with an explicit
resumption, **not a claim that the original aggregate command exited zero**. No failed test or binding was filtered out, no verifier was bypassed, and no assertion was relaxed.

Commands used the dedicated Pro Max simulator `4718C0B2-95ED-4EBA-8D53-E12711E37885` and Watch
simulator `F632D1F6-4379-43ED-8D89-2B5335CD9475`; all owned simulators were isolated from user devices.
The iOS runtime was 26.5, Watch runtime 26.5, host macOS 27.0.1 and Xcode 27.1 (27A9275).

## Red, green and review evidence

- Preference archive/rename/re-transcription and opt-in/live cancellation tests failed against the
  original/scaffold implementation, then passed. Native adapter tests reproduced an always-ready
  scaffold sending text for unprepared pairs (2 tests, 11 failures).
- `SummaryTranslationTests` first produced 13 failures against its scaffold. The native
  `MobileTranslationUITests/testSummaryPageOffersExplicitTranslationAndKeepsOriginal` then failed
  because Summary had no Translate option. Both passed after implementation.
- Native phone and Core Mac session tests reproduced missing source/target synchronization before
  the session adapters were connected; reopening preserves targets without saving derived text.
- `SummaryTranslationTests/testLongerMarkdownFencesNeverSendTheirCodeForTranslation` reproduced
  code being translated inside longer fences (4 failures). Full marker-length/closer validation
  made it green. Both backtick and tilde fences are covered.
- `MacLanguageControlsTests/testWindowTranslationSuspensionFencesBothWorkersAndResumesOnReturn`
  reproduced held results/backlog continuing after suspension (4 failures). Both workers now suspend
  on window teardown and resume on return; normal Mac background recording is unchanged.
- Separate harness failures were retained rather than called product regressions: an incorrect
  initial scheme, unhosted Mac AX access, native menu virtualization at largest text, cropped
  app-only landscape screenshots, a Notes attachment action below the initial viewport, a stale
  five-swipe Settings limit, and a test-class lint limit. The repaired tests retain their original
  action, guidance, persistence, cancellation and hittability assertions. Independent review found
  no assertion weakening or remaining source blocker.

## Rendered UI and native metadata

Four translation UI tests passed on each of Pro Max, iPad mini and 13-inch iPad: live portrait/Duo,
missing-pack explanation without automatic download/capture, explicit Summary translation with the
original retained, and largest-text setup/Close/original readability. Fresh full-display captures
were inspected; earlier cropped landscape captures are excluded. Mac uses an in-process SwiftUI
render plus the actual session binding and lifecycle tests, with its installed-app limitation below.

The frozen-source full run retained 100 iOS PNGs, 10 Watch PNGs and one Mac control-render PNG.
Supplemental native iPad captures include both original/translated speech and Summary translation.
Native resolution, result-bundle device IDs/timestamps, source hashes and signing provenance are
preserved with the local evidence. DEBUG synthetic translations establish UI behavior only.

The real Mac adapter recognized English locally and queried every offered non-English target
(12 pairs), plus earlier reverse French/Spanish/Simplified Chinese checks. All required language
preparation on this Mac. The probes requested no model downloads and sent no text for translation.
This proves observed setup handling, not installed-pack output quality or universal device support.

## Retained evidence and remaining acceptance

Local evidence: `/Users/tomwu/Documents/Codex/2026-10-27/listentome-translation/`.
Key records are `source-validation-final.json`, `source-after-tests.json`, `ci-6c1542a.json`,
`validate-local-mac-log-failed.log`, `ios-full-passed.log`, `mac-interleaved-first.log`,
`mac-first-structured.json`, `mac-resume.log`, `watch-resume.log`, `e2e-resume.log`, the focused
red/green result bundles, native image manifests and Dev cleanup records.

Installed Mac interaction, an installed real translation pair's output quality and physical-device
acceptance remain **unverified**. No new audio capture pipeline changed; existing real OTHERS/audio
publication gates remain separate. This work does not establish production readiness or publication.
A later authorized train must capture its own candidate media, retain these acceptance boundaries,
and follow the [release runbooks](IOS-RELEASING.md).

Completed-session cleanup preserved signing/source evidence, found no other running Dev session,
moved only the temporary bundle with exact identifier `com.tomwu.ListenToMe.dev` to Trash and reset
only that bundle's TCC permissions. All five dedicated simulators were removed. Conversation data,
in-app settings, API keys, production app permissions and shared simulators were left intact.

## iOS train test-harness backport — October 28, 2026

The 1.20.0 preparation adopts the reviewed `MobileTranslationUITests` scrolling correction from
PR #318 source `a1eb0fb`. The original full-run failure came from blind swipes overscrolling the
Translate control at the largest accessibility size. Whole-button bounds assertions reproduced the
harness failure; bounded direction-aware drags and an explicit phone overshoot/recovery check passed
on phone and iPad. Source-matched red/green evidence is preserved under
`2026-10-28/listentome-dual-channel336/translation-ui-diagnostic/`: `visibility-red.log`,
`visibility-green.log` and `phone-ipad-green.log`.
This is a test-only portability/reachability correction, not a new translation engine change or a
new regression-red claim. The final release source still requires its own complete validation.
