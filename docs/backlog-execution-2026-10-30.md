# Backlog execution — October 30, 2026

The 22:22 UTC open-issue readback contained **#181, #205, #223, #236, #334 and #336**.
The subsequently opened [#352](https://github.com/tomqwu/ListenToMe/issues/352) is separately owned
cross-platform GUI refinement. PR #353 subsequently merged at `5e1a8f4` and closed #352 on
October 31, 01:34 UTC. PR #354 then merged at `946cb7e` and closed #334 at 02:49 UTC, leaving
**five** open: #181, #205, #223, #236 and #336. Do not duplicate completed work.
This is a delivery checkpoint, not a replacement for implementation, acceptance or the sequential PR queue.

PRs #318, #349, #350, #351, #353, #354, #355, #356 and #357 merged. #318 closed #333, #335, #337, #346, #347 and #348; #225
was already closed. TestFlight **1.20.3 (43)** was accepted from `97ef2461` and verified for the
existing Dev group. The subsequent History Refresh in #351 is merged but unreleased. The last
recorded public-release readback is iOS **1.19.1 (39)** and macOS DMG **1.4.4**; this checkpoint
does not perform a new Apple review submission or public-release readback.

## Implemented fixes and remaining candidates

| Issue | Source and evidence | Remaining delivery work |
| --- | --- | --- |
| [#181](https://github.com/tomqwu/ListenToMe/issues/181) — preserve Watch audio during redelivery | `codex/watch-inbox-redelivery`, integrated source `989a6b4` on main `946cb7e`, runtime fix `5f52da6`. Portable red reproduced 18 assertions, then both unchanged methods passed; actual focused iOS `105c91dd` also passed both without skips. Full `989a6b4` validation passed: Core 1,294/seven skips/98.0768%; iOS 613/twelve skips; Mac 120; Watch 35; zero failures, 1,109 inputs unchanged. [Audited full receipt](evaluations/watch-inbox-redelivery-full-2026-10-31.json). | PR [#355](https://github.com/tomqwu/ListenToMe/pull/355) merged at `0177431` after independent review and all three final checks on `f0f8d26` ([run 41166381562](https://github.com/tomqwu/ListenToMe/actions/runs/41166381562)); matching branches were deleted. Physical file protection, WatchConnectivity and recording/reconnection/wrist-down/battery/storage acceptance remain separate; [Watch scope](watch-beta.md). #181 remains open and the fix is unreleased. |
| [#336](https://github.com/tomqwu/ListenToMe/issues/336) — saved-audio ordering | `codex/mac-saved-audio-order`, full-tested integrated source `347ed05` on Watch main `0177431`, runtime `d36b212`. Full validation passed with zero failures, 1,112 unchanged inputs, all three actual Saved Audio methods passing and fresh native renders independently inspected. [Audited full receipt](evaluations/mac-saved-audio-order-full-2026-10-31.json). Historical ordering red and focused green remain preserved. | PR [#356](https://github.com/tomqwu/ListenToMe/pull/356) merged at `63e1777` after independent review and all three final checks on `eee22fe` ([run 41172229981](https://github.com/tomqwu/ListenToMe/actions/runs/41172229981)). Matching branches were deleted. Installed playback/gallery and the original near-end/overlap/repeated-speech/headphone/route matrix remain open; this slice does not close #336. |
| [#223](https://github.com/tomqwu/ListenToMe/issues/223) — cancel a stale History answer | Merged `09adc703` integrates main `63e1777`. Genuine shared-model and actual iOS red/green remain preserved. Full validation on `3c8cc37` passed: Core 1,294, iOS 614, Mac 126, Watch 35, zero failures with documented skips; all four new Ask methods passed once. Independent audit verified 1,121 inputs and 2,099 native-result files. [Audited full receipt](evaluations/history-ask-query-cancellation-full-2026-10-31.json). | PR [#357](https://github.com/tomqwu/ListenToMe/pull/357) merged after independent review and all three final checks on `00639a5`; matching local/remote branches were deleted. Existing portrait/landscape controls were inspected as scoped QA; installed/physical streaming gestures and the separate language-quality work remain open. |

The Ask fix is **merged but not included in beta 43**. Saved Audio #356 and Watch #355 are merged
but unreleased. The #334 fix is also merged but
unreleased: full `89e9226` validation, independently reviewed `19d152f` documentation, all three CI
checks and branch cleanup are complete. [Evidence and remaining publication gates](speaker-rename-acceptance.md). Their source, native results and
independent reviews are retained in `2026-10-30/listentome-mac334-name-overflow/`,
`listentome-mac336-saved-audio-order/` and `listentome-watch181-focused-review/` in the local evidence
archive. Later docs-only commits must not be represented as fresh runtime validation.

## Work still needing an accepted result

- **#223:** The unchanged installed-Apple Spanish baseline found 4/8 intended topics. A genuine
  test-first query-class candidate at `db88273` found 5/8, below the required six, and still missed
  visual style. All ten unrelated queries remained empty and all 17 existing native controls passed.
  Independent review confirmed all 19 stored passage payloads unchanged. The candidate is **no-go**,
  preserved with docs-only head `beab26e`; its six follow-on Core checks did not run because the native
  gate failed. The separate German contextual max-pooling experiment also failed at 0/8. None of these
  failures establishes added language support. A distinct installed Spanish sentence-model baseline
  also completed with **0/8**, while two unrelated queries incorrectly returned design passages in
  both Related and meaning-only Ask. This external baseline copied Core from exact main `0714b9ec`
  and used model `s:es:1`/640 dimensions,
  all eight topic vectors and the unchanged criteria plus both explicit query regressions. Its
  first attempt failed compilation before testing; the preserved minimal test-only repair completed
  with 173 unchanged inputs and a reaped worker. This is another no-go, not a product regression red.
  Evidence is in `2026-10-30/listentome-semantic223-spanish-sentence-baseline-v2/`. Do not lower
  thresholds, relabel examples or merge either failed candidate. Refresh/reuse/language-hint work
  already merged stays distinct from this unresolved quality gap.
- **#205:** Physical Mandarin–English Whisper accuracy, speed and battery measurements remain
  incomplete. The prior isolated device attempt stopped before tests, and its temporary app was
  removed. A failed launch is not a model-quality verdict.
- **#236:** Controlled vocabulary/context measurements support the recorded decision against a new
  custom Dictation integration. Actual-app off/on read-aloud, live Add, natural language switching
  and personal-name acceptance remain incomplete; unrelated tests do not complete them.

## Resume from the actual blockers

Xcode updated to **27.2 (27B52)** during validation. CoreSimulator initially mismatched and Apple's
installer stopped at administrator authentication; the owned attempt was stopped and reaped. The
22:35 UTC check returned first-launch 69 and a locked console. **The maintainer then completed setup**:
the 22:43 UTC check returned first-launch 0 and working simulator inventory. Corrected #334 installed
acceptance and native screenshots subsequently passed. Preserve the earlier failed aggregate.

At 23:05 UTC another session owned a Dev app and iOS native tests, so cleanup was deferred.
The October 31, 00:36 UTC follow-up preserved and removed both owned fixtures and their two vector
files, with all eleven original archive files unchanged. The later session had already completed
the app-scoped Dev reset; it was not repeated. The original deferred event remains in the evidence.

The 00:42–00:43 UTC fresh validation setup then met a new foreign native owner after preparing its
simulators. The guard refused **before make/tests**; all 1,085 inputs matched and both owned devices
shut down. At that checkpoint the reviewed retry waited for the foreign run to reap.
This was a failed setup attempt, not a product test failure or a full pass. The later combined
`89e9226` full result is **passed (exit 0)**, recorded separately in the
[current acceptance evidence](speaker-rename-acceptance.md). The original `9a39a12` aggregate remains
failed. Do not repeat setup/unlock requests, reset shared services or interrupt another session's
tests. [Installed/cleanup receipt](evaluations/mac-speaker-name-overflow-installed-2026-10-30.json).

Earlier phone checks timed out without establishing lock state. A fresh direct readback at
October 31 reached the iPhone 17 Pro Max and reported `passcodeRequired: true`; the Mac
also reported its screen locked. Resume affected installed/device work after an actual environment
change and ownership check, without repeating unchanged unlock requests.
Fresh passive readbacks at **06:08 UTC, October 31** still found the phone requiring its passcode
and the Mac locked. No app, permission or authentication state changed and no repeated request was made.
Preserve the exact candidates; #334, Watch inbox preservation and saved-audio ordering are merged.
Ask cancellation subsequently merged in PR #357 at `09adc703`, after independent review and all
three final checks on `00639a5`; its matching branches were deleted. Historical build 44 source
`9460f00` passed complete local validation and focused Pro History/preview checks. Current candidate
`ca7ab57` also corrects the iPad mini adaptive-workspace test precondition and passed its focused
method, all 21 fresh capture methods and the complete full-local gate, October 31 **12:31–13:17 UTC**.
[Current full receipt](evaluations/ios-1.20.4-full-ca7ab57-2026-10-31.json) ·
[Seven-profile capture receipt](evaluations/ios-1.20.4-release-captures-2026-10-31.json).
All 71 native screenshots were inspected; eight selected originals now populate the README gallery.
Hosted README review, final train CI/merge and upload remain pending, with physical and
installed/audio acceptance recorded separately. Earlier failures and source-bound passes remain preserved.

[Current handoff](HANDOFF.md) · [Speaker acceptance](speaker-rename-acceptance.md) ·
[Semantic evaluation](semantic-search-evaluation.md) · [iOS acceptance](IOS.md) ·
[Watch acceptance](watch-beta.md)

Saved-audio integration checkpoint: full-tested source `347ed05` includes Watch main `0177431`,
preserving the focused runtime/test/catalog bytes from `bf0f2ae`. The two HANDOFF/backlog conflicts
retained both workflows and source-labelled evidence. Combined validation, independent source/artifact
audit and all three checks on that source passed; [the full receipt](evaluations/mac-saved-audio-order-full-2026-10-31.json)
also binds the root's fresh rendered inspection. Final documentation review and all three checks
passed on `eee22fe`; PR #356 merged at `63e1777`. Installed playback/gallery remains blocked:
the passive 04:06 UTC readback reported
the Mac locked. No new unlock or permission request was made.
