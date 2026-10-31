# Explicit local History refresh — #223

The original October 30 implementation subsequently merged in PR #351. Its iPhone/iPad behavior is
distributed in [TestFlight 1.20.4 (44)](releases/ios-1.20.4-build44.json); the Mac feature remains unreleased.
The capture follow-up below is included in the validated release source; physical acceptance remains separate.
This does not restore the withdrawn MPNet runtime or establish additional-language search quality.

## Build 44 landscape capture follow-up — October 31

The full run on `3a83918` passed before the seven-profile capture attempt. iPhone 17 Pro passed
all five capture methods; Pro Max failed the selected History row/search nonintersection assertion
after a 13-point upward drag, while its other four methods passed. Its native before/after images,
activity tree and original results are preserved. iPad and Watch capture profiles were not started.
[Sanitized failure receipt](evaluations/ios-1.20.4-history-capture-failure-2026-10-31.json).

`HISTORYREFRESH-010` covers compact and larger phones and adaptive Duo or wide iPad workspaces.
Its test uses a minimum 44-point upward drag, capped at one third of the viewport. Whole-row
containment, search separation, exact query and conversation open/reopen assertions remain intact;
diagnostic failure text includes both frames. The corrected History method passed on both phones.

The portrait-first concise preview passed on Max but initially failed on Pro because status content
precedes its answer in the Quick scroll view. The bounded Quick-only scroll correction then passed
the two-method focused Pro retry on `9460f00`; complete local validation on that source also passed
History and preview on Pro Max, where the answer fits without scrolling. Both earlier failures remain
preserved. These are test corrections, with no app layout or fixture-text change.

The later `9460f00` capture exposed a separate initial iPad mini precondition: its compact-height
landscape workspace correctly used Duo, while the test expected a wide container from device idiom.
Only that initial assertion failed; later History outcomes completed. Source `ca7ab57` accepts either
existing adaptive container and passed the same focused mini method. Its fresh seven-profile capture
then passed all **21 methods**, with **71 unedited native originals** preserved and independently
inspected for individual gallery suitability. Some remain QA-only; completing capture does not make
every image suitable for a listing. Final complete `make validate-local` then passed on the same
`ca7ab57` source: the 261-scenario catalog validated and all 602 required bound selectors passed.
[Current full receipt](evaluations/ios-1.20.4-full-ca7ab57-2026-10-31.json), [capture receipt](evaluations/ios-1.20.4-release-captures-2026-10-31.json) and
[README capture manifest](images/ios/release-1.20.4/manifest.json) preserve those separate source-bound results.
Final documentation/CI/merge and hosted README inspection passed; build 44 is accepted in TestFlight
from `08810e8`, whose changes from `ca7ab57` are documentation/gallery only. The original capture
receipts remain unchanged, and publication does not establish physical or language-quality acceptance.

**Refresh search** in Mac and iPhone/iPad History replaces the local Apple embedding adapter and
rebuilds derived vectors, including unchanged records previously cached without vectors. Ordinary
saves still reuse unchanged vectors. Refresh does not request language assets, download a model,
change an AI provider or rewrite conversation files. Unsupported local capabilities may still return
no vectors; finishing Refresh is not proof a language became supported.

One explicit attempt owns the operation. Exact-word search remains usable while rebuilding or after
storage failure. Ask is blocked before provider creation until a current-archive pass succeeds;
failure retains retry guidance. Delete/Clear and newer work fence late vectors and answers. If deleting
a held first record interrupts a rebuild, Refresh reconciles surviving current records before it
reports idle and permits Ask. The original ranking rules and language-quality assertions are unchanged.

The shared control is [HistoryRefreshControl](../SharedPlatform/HistoryRefreshControl.swift), backed by
[HistorySearchModel](../SharedPlatform/HistorySearchModel.swift) and the same
[HistoryIndex](../Sources/ListenToMeCore/HistoryIndex.swift) actor. Contracts
`HISTORYREFRESH-001`–`010` are in [the executable catalog](../Behaviors/history-capability-refresh.json).
The [manual checks](manual-smoke-test.md#explicit-local-history-refresh-223-unreleased-follow-up)
cover literal results, retries, no-results control reachability and deletion during Refresh.

[Sanitized focused receipt](evaluations/history-local-refresh-focused-2026-10-30.json).

## Recorded focused evidence

Evidence is retained outside the repository under
`/Users/tomwu/Documents/Codex/2026-10-30/listentome-history223-local-refresh/`.

| Slice | Actual result |
| --- | --- |
| Equal-recipe cache refresh | The same three Core methods: red had two failed methods/six assertions; green passed all three. Normal incremental reuse and held deletion remain covered. |
| Deletion during rebuild | The held two-record native method failed five assertions; after reconciliation, the same method passed with the other eleven transition methods. |
| Older queued maintenance | Two new held tests failed seven assertions: an older sync dropped a new record and an older save replaced current evidence. Resolving current records when queued work executes made all fourteen transition methods pass. |
| iPhone no-results layout | Initial two-method run passed tapping assertions; image inspection exposed an overlapping overlay. Two strengthened geometric assertions failed, then the same two methods passed after moving empty guidance into the results section. |
| Mac actual shared control | `mac-controls-native-release` passed all sixteen methods (fourteen transition + two control), zero skips, exit 0/reaped after 15.520 seconds; 1,058 frozen inputs matched. |
| Recovery caption contrast | The actual caption failed one assertion at 3.949:1. Changing only its native foreground from secondary to primary made the unchanged test pass at 14.938:1. `mac-caption-green` passed all sixteen methods, exit 0/reaped after 14.849 seconds; 1,067 inputs matched. This is Aqua coverage, not every appearance or accessibility setting. |

The final Mac native tests deliver pointer events to the actual production control through an owned
AppKit window and event loop. They prove one held attempt, disabled duplicate activation, rendered
failure guidance, usable retry and current semantic results. The actual installed Apple branch
rebuilt a formerly empty cache; every saved archive filename and byte remained unchanged. Native
idle/busy/failure/retry PNGs were exported and inspected. This is a hosted native control check,
not installed full-app or VoiceOver acceptance.

Earlier selector/compile errors and hosted-control failures remain preserved and are not product
reds. A black-preview diagnosis was corrected: the 226×34 PNGs contained real glyphs on transparency,
not blank output. Fixed-size opaque wrappers established rendering; public AX readbacks remained
incomplete. The successful native event-loop/release repair also coincided with changed OS lock
state, so the evidence does not isolate a single cause for earlier dispatch failures. No permission
reset or unlock request was used, and no AX/VoiceOver pass is claimed.

`ios-overlay-red` / `ios-overlay-green` preserve the unchanged geometric method and 1,058 input
hashes per run. The no-results action remains tappable, the query stays intact and Ask/disclosure no
longer overlap the guidance. The long test query extends below the keyboard and stays scrollable;
those images are QA evidence, not clean README media. Ask blocking after failed refresh is separately
proven by the native transition test's zero provider calls before recovery.

`ios-gallery-final` passed all three phone methods with zero skips, exit 0/reaped after 51.327 seconds;
1,069 inputs matched. Empty History coverage passed on first execution. One earlier capture attempt
failed a new hittability assertion on a noninteractive text match; targeting the actual existing
record Button fixed this test-harness error without a production change. The native originals in
[the README manifest](images/history/unreleased-2026-10-30/manifest.json) preserve a clean short-query
preview and empty History. The installed Mac History sheet and full-window originals now supplement
the clearly labelled isolated Mac component. No pixels were edited.

## Full aggregate and installed Mac acceptance

Full `make validate-local` passed on `c8fdcd29`, exit 0/reaped, with all **1,071 inputs** unchanged,
including the separately pinned ignored Dev signing override. Core: **1,294 tests / seven optional
skips / zero failures / 98.0768% coverage**. iOS: **509 unit tests / seven skips** and **96 UI tests /
five skips**; Mac: **118 tests**; Watch: **29 unit + five UI tests**, with no Mac/Watch skips.
All native suites had zero failures and their original result summaries agree with the logs.
The **245-scenario catalog validated**; all **579 required bound selectors**, release/tooling
helpers, the native hotkey check and both two-test real-server contracts passed. The Mac Chinese test explicitly used its installed
real-model branch; this is not phone or general translation-quality acceptance.

The source-matched signed normal Debug Dev app (**1.4.4 (14)**, as configured; Store configuration
remains **1.5.0 (15)**) then passed actual installed History acceptance. A second exclusive synthetic
record was added while History was open: the real Refresh changed the filtered result from one to
two rows, showed busy/disabled then idle/enabled, preserved the query, repeated successfully and
opened the new record after an actual Quit/relaunch. Two owned cache files contain real `w:en:1`
Apple vectors. Root recorded eleven pre-existing archive files unchanged; all four owned QA/gallery
records and derived vectors were preserved before removal, the Dev app quit/Trashed and only its
app-scoped permissions cleaned. No Settings, Ask, download or recording action was exercised.
The defaults comparison found **zero matching top-level keys**; it does not prove every setting
was exhaustively checked or preserved. The removed backup/absent final snapshot prevents replay
of that settings comparison. The original signed build still verifies; the later Trash copy has
matching file bytes but now fails strict codesign for Finder metadata, a preserved cleanup-artifact
limitation. Native images independently show only two synthetic Airship records, readable controls
and an empty background, without private conversation or permission/error/debug overlays.

[Sanitized aggregate/installed receipt](evaluations/history-local-refresh-validation-2026-10-30.json).
The original focused receipt above retains its earlier pending status as historical evidence.
Follow-up `13573f90` changes only the landscape test and BDD binding; production/build inputs
remain byte-identical to full-tested `c8fdcd29`. Its focused native run passed **two test invocations,
zero failures/skips**, one each on iPhone 17 Pro and iPad Pro 13-inch M5 / iOS 26.5, exit 0/reaped;
all **1,074 inputs** matched. The final catalog has **246 scenarios**. Selected native originals show
**unqueried History**, Refresh and a complete record card, with no keyboard. The phone's lower hint
can sit behind the floating search toolbar and additional actions require normal scrolling; this
is not an all-content-at-once image. Queried control/result frames remain QA-only. Stored portrait
pixels and EXIF orientation 8 are preserved; the manifest separately records landscape display size.

Initial app-only screenshots cropped landscape coordinates; an iPad test initially missed the normal
collapsed search drawer. A later simultaneous-fit assertion after scrolling imposed an unjustified
preview constraint, and `transcriptText` was a test selector typo. Those harness/constraint failures
and all originals remain preserved; none is presented as a production regression red. No runtime
or fixture content changed. The queried iPad disclosure's existing “this iPhone” wording remains a
separately reported copy observation, not a fix or new language-support claim.

Current exact-head CI, hosted final-gallery review and merge remain pending. This is composite
validation (full runtime plus subsequent test-only coverage), not a newly repeated full aggregate.
The retained failed multilingual quality results remain failed; this explicit Apple capability
refresh is a separate bounded implementation slice, not completion of #223.
