# Explicit local History refresh — #223

October 30, 2026: implementation in an isolated follow-up checkout, not merged or released.
This does not restore the withdrawn MPNet runtime or establish additional-language search quality.

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
`HISTORYREFRESH-001`–`006` are in [the executable catalog](../Behaviors/history-capability-refresh.json).
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
| Mac actual shared control | Final `mac-controls-native-release` passed all sixteen methods (fourteen transition + two control), zero skips, exit 0/reaped after 15.520 seconds; 1,058 frozen inputs matched. |

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

Full local validation, current hosted CI, affected README screenshots, review and merge remain pending.
The retained failed multilingual quality results remain failed; this explicit Apple capability
refresh is a separate bounded implementation slice, not completion of #223.
