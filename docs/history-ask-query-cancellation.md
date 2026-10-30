# History answers follow the current query

Local candidate based on `0714b9ec`, not merged or released. This reliability fix does not
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
methods in `HistoryAskQueryCancellationTests`. The same test file and actual shared production
model were compiled byte-identically in a temporary SwiftPM test target with copied Core sources.
A keyword-only fake embedder and held local providers exercise real index retrieval, partial
answers, cancellation, new-question excerpts/citations and attempted late publication. No
embedding model, network provider, microphone, Xcode project or GUI was used.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-30/listentome-history-ask-query-cancellation`.
`PYTHONDONTWRITEBYTECODE=1 python3 run-focused.py red` reproduced two failing methods with twelve
assertions; the whitespace control passed. The unchanged three methods passed with zero failures
under `run-focused.py green` after the one-line shared fix. Both supervised runs exited/reaped
inside 600 seconds and all 159 pinned repository inputs matched before/after their respective run.
This focused headless proof is not a full Mac/iOS suite, rendered interaction or installed/device
acceptance. Those checks, full validation, independent review, CI and merge remain pending.

For manual Mac and phone checks, see [the smoke test](manual-smoke-test.md). No view appearance
changed, so the existing README gallery remains applicable; gallery links still need checking.
