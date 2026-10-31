# History answers follow the current query

Local candidate now integrates Saved Audio main `63e1777`; focused red/green below used base `0714b9ec`.
The shared runtime fix and three original Mac test methods remain unchanged. A complementary
iOS test uses the actual phone session to check clearing a completed answer and its nonempty
citations/count, plus whitespace preservation. Its genuine native red/green passed as recorded below.
This reliability fix is in PR #357 and remains unreleased. It does not establish additional-language
search quality or close #223.

Mac and iPhone/iPad already pass search-field changes to the shared `HistorySearchModel.search`.
That callback now clears the previous question's answer through the existing cancellation and
request-token fence when the trimmed question changes, including becoming empty. The next Ask can
start immediately. Late output cannot replace its answer or citations. Leading/trailing whitespace
alone preserves the current request. This does not add automatic Ask dispatch, change providers,
send whole conversations, alter retrieval/ranking, or download assets. Cancellation stops local
consumption; it cannot recall excerpts already sent or guarantee a remote server stops computing.

`HISTORYASKCANCEL-001`–`003` in
[the behavior contract](../Behaviors/history-ask-query-cancellation.json) bind three native Mac
`HistoryAskQueryCancellationTests` methods. `HISTORYASKCANCEL-004` separately binds the
completed-answer journey in `MobileHistorySearchTests` on iOS. The original test file and actual
shared production model were compiled byte-identically in a temporary SwiftPM test target
with copied Core sources; that recorded result predates the complementary iOS test.
A keyword-only fake embedder and held local providers exercise real index retrieval, partial
answers, cancellation, new-question excerpts/citations and attempted late publication. No
embedding model, network provider, microphone, Xcode project or GUI was used.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-30/listentome-history-ask-query-cancellation`.
`PYTHONDONTWRITEBYTECODE=1 python3 run-focused.py red` reproduced two failing methods with twelve
assertions; the whitespace control passed. The unchanged three methods passed with zero failures
under `run-focused.py green` after the one-line shared fix. Both supervised runs exited/reaped
inside 600 seconds and all 159 pinned repository inputs matched before/after their respective run.
This focused headless proof is not a full Mac/iOS suite, rendered interaction or installed/device
acceptance. The subsequent combined full validation and scoped control inspection passed as recorded
below. Watch #355 and Saved Audio #356 are merged; PR #357 carries this change through final
documentation review, required CI and merge.

For manual Mac and phone checks, see [the smoke test](manual-smoke-test.md). No view appearance
changed, so the existing README gallery remains applicable. Local links and all 32 hosted local
gallery/icon image targets passed checks on the tested source; the existing source labels remain.

## Native iOS completed-answer regression — October 31, 2026

The new bound phone test first ran on reconstructed RED source `d36f3ed`; its shared runtime
was byte-identical to main `0177431`. One native method failed eight assertions: changing and
clearing the query each retained the old answer, question, citations and passage count. The
whitespace and no-extra-provider-request controls did not fail. The run exited 65/reaped.

Restoring only the shared `clearAnswer()` line produced source `d7c7124`. The same method and
controls passed on the iPhone 17 Pro simulator (iOS 26.5): **one pass, zero failures/skips**.
Both runs kept all **1,120 inputs** stable, reaped their process groups and confirmed the owned
simulator Shutdown. Both compiled app/test bundles were preserved before reuse; each archive
contains 113 verified files. Independent review checked both outcomes, unchanged test bytes,
the one-line implementation difference and preserved binaries.

[Source-bound native receipt](evaluations/history-ask-ios-query-cancellation-2026-10-31.json).
This tests completed answer state through the actual `MobileSession` with a local provider spy.
It does not establish physical acceptance or rendered interaction; the three streaming/cancellation
cases are separately bound to the Mac tests that passed in combined full validation below.

## Combined full validation — October 31, 2026

`make validate-local BDD_BASE=63e1777887c3083d3fe18f76f7a25c1d7016286a` passed on exact source
`3c8cc37231163bbb7134e9229205aa25273920fb`, **05:35–06:24 UTC**, exit zero and reaped.
Core **1,294/seven skips/98.0771% coverage**, iOS **513 unit/seven skips and 101 UI/five skips**,
Mac **126**, and Watch **29 unit/six UI** completed with zero failures. All four new Ask methods
passed once without skips. The 259-scenario catalog validated; all 600 required bound selectors,
71 helper methods and four real local-server contracts passed.

Independent audit verified **1,121 unchanged inputs**, **2,099 original and preserved result files**,
111 test/host payload files and the signed 34-file Debug Dev archive. Owned processes reaped and
both simulators were confirmed Shutdown. All three required checks passed on the tested head in
[run 41173088745](https://github.com/tomqwu/ListenToMe/actions/runs/41173088745).
[Complete source-bound receipt](evaluations/history-ask-query-cancellation-full-2026-10-31.json).

Eight existing History UI captures were retained; the run owner and root inspected three showing
Refresh, Ask and provider disclosure in portrait, landscape and no-results states. Keyboard and
scroll position obscure some lower content, so these are scoped QA captures, not full-page or
release-gallery images. They do not demonstrate editing during a streaming answer. The exact native
model assertions establish that behavior separately; installed Mac and physical phone interaction
remain production-acceptance gates. The unchanged README gallery remains source-labelled; final
documentation adds no runtime/test/config change. No language-quality, merge or publication claim
follows from this validation receipt.
