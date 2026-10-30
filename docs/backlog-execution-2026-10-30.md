# Backlog execution — October 30, 2026

GitHub's open-issue query was read back at 22:22 UTC: **#181, #205, #223, #236, #334 and #336**.
They remain open because the outcomes below are incomplete. This is a delivery checkpoint, not a
replacement for implementation, acceptance or the sequential PR queue.

PRs #318, #349, #350 and #351 merged. #318 closed #333, #335, #337, #346, #347 and #348; #225
was already closed. TestFlight **1.20.3 (43)** was accepted from `97ef2461` and verified for the
existing Dev group. The subsequent History Refresh in #351 is merged but unreleased. The last
recorded public-release readback is iOS **1.19.1 (39)** and macOS DMG **1.4.4**; this checkpoint
does not perform a new Apple review submission or public-release readback.

## Implemented local candidates

| Issue | Source and evidence | Remaining delivery work |
| --- | --- | --- |
| [#334](https://github.com/tomqwu/ListenToMe/issues/334) — speaker-name overflow | `codex/mac-speaker-name-overflow`, tested runtime `9a39a12`; genuine two-assertion rendered red followed by ten passing native methods. The integrated attempt passed Core 1,294/seven skips, iOS 606/twelve skips and Mac 119. **The aggregate failed before Watch testing** during the Xcode update. Same-source signed build and four real-server contracts passed separately. After setup recovery, corrected installed rename/VoiceOver, full relaunch, archive preservation and fresh README captures passed independent review. | Run fresh full validation when the other session releases native resources, finish final review, required CI and merge. Keep this first in the PR queue. Complete deferred Dev cleanup when the other session ends. |
| [#336](https://github.com/tomqwu/ListenToMe/issues/336) — saved-audio ordering | `codex/mac-saved-audio-order`, docs head `bf0f2ae`, runtime `d36b212`; real native ordering red followed by three passing rendered methods and 145 Core tests. Playback keeps canonical source/offset identity, duplicate restored IDs and untimed/legacy boundaries. | Integrate final #334 main; finish full validation, installed playback/gallery, review, CI and merge. The original near-end/overlap/repeated-speech/headphone/route matrix remains required separately. |
| [#181](https://github.com/tomqwu/ListenToMe/issues/181) — preserve Watch audio during redelivery | `codex/watch-inbox-redelivery`, docs head `105c91d`, runtime `5f52da6`; two unchanged iOS-source tests reproduced 18 assertions and then passed in a portable Mac host. The first durable audio/sidecar survives a duplicate transfer when the manifest is missing or corrupt. | Run the bound iOS tests and full validation after simulator repair, then review/CI/sequential merge. Portable filesystem tests do not establish iOS file protection, WatchConnectivity or physical Watch recording/reconnection/wrist-down/battery/storage acceptance. |

These candidates are **not merged or included in beta 43**. Their source, native results and
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

At 23:05 UTC another active session owned a Dev app and iOS native tests. Fresh full validation waits
for those resources. The completed #334 app is quit and trashed; its two synthetic archive fixtures
and scoped Dev permission reset remain deferred to protect that session. Do not repeat setup/unlock
requests, reset shared permissions/services or interrupt another session's tests.

The last bounded phone check timed out and reaped; it establishes **no current device lock state**.
Resume the affected native/installed/device work after an actual environment change and resource-ownership check.
Preserve the exact candidates; finish #334 before opening the next feature PR. After every merge,
verify CI and delete only that PR's safe matching feature branches. Publication remains a later
batched step with separate production acceptance and screenshot requirements.

[Current handoff](HANDOFF.md) · [Speaker acceptance](speaker-rename-acceptance.md) ·
[Semantic evaluation](semantic-search-evaluation.md) · [iOS acceptance](IOS.md) ·
[Watch acceptance](watch-beta.md)
