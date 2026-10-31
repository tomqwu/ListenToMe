# Mac speaker rename acceptance and long-name containment (#334)

The unreleased Mac fix keeps a long speaker name within its transcript column and displays an
ellipsis when necessary. The full title, tooltip and accessibility label remain available. It changes
neither saved names nor transcript text, speaker identity, audio, permissions or model behavior.

## Installed observations before the layout fix

On October 30, the signed normal Debug app from `5f1e909` had Mac runtime inputs identical to merged
`97ef2461`. Two synthetic conversations in the normal Dev archive exercised single/double click,
the actual speaker-label context menu, Save/Cancel, blank-name refusal, full process quit/relaunch
and isolation of the neighboring conversation. Two matching target lines retained the saved name;
the other speaker and neighbor retained their original names and text. All ten pre-existing archive
files remained byte-identical. The two owned fixtures were preserved before removal, the exact `.dev`
bundles were moved to Trash, and only the Dev permissions were reset after the sessions ended.

A separate VoiceOver pass used its actual caption window to read the full speaker name and button
role, opened the correct editor with VO Space, and navigated/activated Cancel and Save. The visible
full-name tooltip worked. New conversation dismissed a pending editor without leaking its unsaved
name into either fixture. VoiceOver was restored off and its process was absent after cleanup.
This is normal Debug acceptance, not Store sandbox, iOS VoiceOver or acoustic speaker-quality proof.

That same installed inspection exposed the remaining defect: a long native button title drew over
the adjacent transcript. Those earlier acceptance results do not establish acceptance of its fix.

## Reproduced native regression

`SPEAKER-020` binds
`MacTranscriptInteractionTests/testLongSpeakerNameDoesNotPaintOverAdjacentTranscript`. It renders
the actual production row, changes only its name, then compares native bitmaps. It requires visible
name changes inside the actual column, visible original transcript ink, stable adjacent text and
geometry, and no changed pixels past the column's one-pixel antialias boundary. It also checks the
real control's complete tooltip and accessibility label; reading a configured width alone cannot pass.

On base `f26e655` plus the recorded test/scenario inputs, the test failed two assertions: the native
label grew from 100 to 266 points, and 2,675 changed name pixels appeared outside its column. The
minimal fix lowers horizontal compression resistance and uses native tail truncation. The same test
then measured 1,201 changed name pixels inside the column, zero outside, and 2,888 unchanged original
transcript ink pixels. All ten speaker/transcript methods passed with zero failures or skips.

Both processes were reaped and all 1,059 frozen inputs remained unchanged within each run. The only
input changed between runs was `App/MacSpeakerNameButton.swift`; the test and scenario were unchanged.
Before/after native images were inspected. They are bounded control diagnostics, not README or Store
listing media. [The sanitized receipt](releases/mac-speaker-name-overflow-f26-validation.json) records
exact hashes and references evidence under `2026-10-30/listentome-mac334-name-overflow`.

## Integrated validation attempt

After integrating the History Refresh runtime, exact source `9a39a12` ran `make validate-local`.
Core completed 1,294 tests (seven skips, 98.0768% coverage); iOS completed 606 tests (twelve skips),
both with zero failures. All 119 Mac tests passed, including the unchanged rendered `SPEAKER-020`. Helpers,
lint and BDD passed. All 1,074 frozen inputs remained unchanged. **The aggregate failed**, exit 2:
Xcode changed from build 27A9275 to 27B52 during the run, and Watch testing could not start because
installed CoreSimulator 1174.9.2 did not match required 1174.21.0. No Watch pass is claimed.

The separate same-source `make e2e` then passed the signed normal Debug build and all four real-server
contracts on Xcode 27B52. Its preserved `.dev` app has 34 byte-matching payload files and a valid
signature. The owned Xcode first-launch recovery stopped at PackageKit administrator authentication;
it was terminated and reaped without permission, keychain or simulator-service resets. The completed
aggregate is still failed, not a composite full pass. [Source-bound component receipt](releases/mac-speaker-name-overflow-9a39-validation.json).

PR [#351](https://github.com/tomqwu/ListenToMe/pull/351) subsequently merged History Refresh at
`0714b9ec` with all three required checks green. Local merge `7b19c69` brings in only its final docs
and gallery; this candidate's runtime, tests and build configuration remain identical to `9a39a12`.

## Corrected installed acceptance — October 30, 23:04 UTC

The maintainer completed Xcode setup. At 22:43 UTC, first-launch status and simulator inventory both
returned zero on Xcode 27.2 (27B52). At that checkpoint a new full run was required; the earlier
aggregate remains failed regardless of later results.

The installed normal Debug app from `9a39a12` passed double-click and context-menu rename,
Save/Cancel, empty-name refusal, full quit/relaunch persistence and neighboring-conversation isolation.
Both matching turns show the long name within the speaker column, with every transcript word readable
at 2,200- and 1,672-point window widths. The complete name remains visible in the editor and tooltip.
Actual VoiceOver captions read the full name and button role; VO Space opened the correct editor and
activated Cancel and Save. VoiceOver was restored off. These are installed observations, separate from
the native callback and bitmap tests above.

Two synthetic conversations exercised the flow. All eleven original archive files remained
byte-identical; the neighboring fixture was unchanged. Only the target's two matching speaker names
and derived transcript changed. Canonical segment IDs, recording IDs, capture times, text and language
were preserved. The owned app processes ended and its exact `.dev` bundle was moved to Trash.
At 23:05 UTC another session started a Dev app using the same archive, so removal of the two owned
fixtures and the scoped Dev reset were deferred; its app and permissions were left untouched.
The **October 31, 00:36 UTC follow-up** preserved and removed the two owned conversation files and
their two derived vector files. All eleven original archive files remained byte-identical; the target's
post-quit serialization changed no decoded content. No Dev process remained, the owned app was
already trashed, and the later session had already completed the scoped Dev reset. No reset was
repeated. The original deferred event and completed follow-up are both retained in the receipt.

That source's fresh, unchanged native-resolution window captures remain in the README's labelled
historical gallery. Independent review inspected
the rendered images, actual VoiceOver/input evidence, archive differences and source/signing receipt.
[Capture provenance and originals](images/mac/speaker-rename-unreleased-2026-10-30/manifest.json) ·
[Sanitized installed acceptance receipt](evaluations/mac-speaker-name-overflow-installed-2026-10-30.json).
Some initial automation captures omitted the child sheet or captured an offset/black region; those
remain diagnostics and were excluded. Full-screen dialog evidence and native window captures repaired
the evidence gap without changing the app. No acoustic, Store-sandbox or physical iOS pass is claimed.

## Historical CI and setup checkpoint

All three required checks passed on exact `f108857` in
[run 41143536177](https://github.com/tomqwu/ListenToMe/actions/runs/41143536177). That checkpoint's
runtime/tests/config were unchanged from `9a39a12`; it predates the combined workspace candidate.
The October 31, 00:42–00:43 UTC fresh setup attempt was refused by the resource guard after simulator
preparation, before make/tests. All 1,085 inputs matched and both owned devices shut down. The
reviewed retry waited for the foreign native run to finish. This was a setup refusal, not a product
test result or a full pass. Cleanup is complete; no repeated setup/unlock/reset is needed.

## Combined candidate `89e9226`

This candidate integrates main `5e1a8f4`, including independently accepted workspace PR #353.
Its #334 runtime delta against that main is the two-line native compression/tail-truncation fix.
`MacSpeakerNameButton.swift`, `EditableTranscriptRow.swift` and the bound bitmap-test file are
byte-identical to `9a39a12`. The whole app is not: the integrated workspace changed, so the earlier
installed observations and gallery do not establish combined installed acceptance.

Exact-source `make validate-local`: **passed (exit 0)**.
Core completed 1,294 tests with seven skips and 98.0768% coverage; iOS completed 611 tests with twelve
skips (510 unit/seven skips and 101 UI/five skips). Mac passed 120 tests and Watch passed 35,
with no skips. Every suite had zero failures, and all four real-server contracts passed.
The run finished October 31 at 02:26:33.729853 UTC with all 1,103 frozen inputs unchanged;
the runner was terminal/reaped and its owned process groups were absent. Shutdown code 149 meant
an owned simulator was already stopped, not a validation failure.
Fresh `SPEAKER-020` short/long native PNGs from this run were inspected: the long name truncates
inside its column, while `00:34` and the complete synthetic cedar transcript remain readable and
unchanged. The bound test passed; these images establish only the production row's rendered result.
[Sanitized full validation receipt](releases/mac-speaker-name-overflow-89e-validation.json).
The original `9a39a12` aggregate remains failed; separate focused, installed and CI results are not
combined to relabel it. The new native row images remain diagnostics, not full-app README media.

All three required checks passed on exact `89e9226` in
[run 41156133221](https://github.com/tomqwu/ListenToMe/actions/runs/41156133221).
The existing source-labelled hosted README passed inspection at 1,280- and 390-pixel widths:
44 images loaded at each width, and 11 downloaded assets/manifests matched local bytes. The recorded
review is `docs-gallery-corrected/readme-89e9226/visual-review.json` in the external evidence directory.
This verifies the existing gallery's rendering and links, not a new combined installed screenshot.
Final documentation changes still need content/link checks, final gallery review and their own CI.

PR [#354](https://github.com/tomqwu/ListenToMe/pull/354) remains open; final review and merge remain.
Combined installed Mac acceptance and a fresh full-app long-name capture remain open while the Mac
is locked. Preserve the source-labelled earlier gallery and its capture manifest; do not substitute
native component diagnostics or repeat unchanged unlock requests. Installed acceptance and release
screenshots remain separate publication gates. No merge, production-ready or publication claim is made.
