# History answers follow the current query

Local candidate now integrates main `0177431`; focused red/green below used base `0714b9ec`.
The shared runtime fix and three original Mac test methods remain unchanged. A complementary
iOS test uses the actual phone session to check clearing a completed answer and its nonempty
citations/count, plus whitespace preservation. Its genuine native red/green passed as recorded below.
This fix is not merged or released. This reliability fix does not
establish additional-language search quality or close #223.

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
acceptance. Those checks, full validation, final independent review, CI and merge follow the
Watch and saved-audio fixes in the sequential queue; no feature PR is open for this change.

For manual Mac and phone checks, see [the smoke test](manual-smoke-test.md). No view appearance
changed, so the existing README gallery remains applicable; gallery links still need checking.

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
cases remain separately bound to Mac tests for the upcoming combined full validation.
