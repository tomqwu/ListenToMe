# Optional History search model — #223 implementation checkpoint

October 29, 2026. Unmerged implementation checkpoint based on `57ac48f`.
This is not a merged feature, a language-support claim or a release. The latest combined
validation and installed acceptance recorded in [HANDOFF](HANDOFF.md) concern earlier source;
this implementation still needs full validation, current CI, completion of acceptance and merge.

## Implemented code

Apple embeddings remain the default. The optional pinned MPNet backend targets German, Spanish,
Japanese and Korean through the existing History index. It runs locally and keeps keyword fallback,
existing ranking thresholds, passage-vector reuse and transcription-language hints. The runtime
uses the verified XLM-RoBERTa tokenizer/mean-pooling recipe, serializes model work and returns no
vector for input beyond its 128-token limit; the complete original text remains keyword-searchable.
See [the runtime](../SharedPlatform/MultilingualHistoryEmbedder.swift) and
[the index](../Sources/ListenToMeCore/HistoryIndex.swift).

[The asset owner](../Sources/ListenToMeCore/HistoryModelAssets.swift) downloads only on an explicit
install action: six immutable public files, **1,126,353,221 bytes** (1.13 GB), at revision
`4328cf26390c98c5e3c738b4460a05b95f4911f5`. Readiness checks never download. Size and streamed SHA-256
checks precede activation; staging, cancellation, removal and unsafe-path refusal preserve unrelated
files. Storage uses the existing protection and backup-exclusion policy. No additional model assets
were downloaded during this implementation turn; native tests reused retained local research assets.

[Shared Settings](../SharedPlatform/HistoryLanguageSettings.swift) exposes download, progress,
Cancel, opt-in and Remove. [Its owner](../SharedPlatform/HistoryLanguageModel.swift) fences late
completion. Backend transitions clear old answers/results and retain the intended choice for retry
when index storage is unavailable. Exact-word search stays available while a transition is blocked;
Ask waits for that transition. This changes neither the selected summary provider nor its disclosure:
embeddings stay local, while explicitly asking an existing remote provider can still send retrieved
excerpts under the existing Ask policy.

[Content eligibility](../Sources/ListenToMeCore/HistoryContentEligibility.swift) reuses the existing
English generic-noun exclusions and passage/query minima only where the runtime advertises lexical
tagging. English and Spanish provide that capability on the observed Mac; German/Japanese/Korean
do not, and fallback `OtherWord` tags remain **unknown**. An unhinted one-word query also remains
unknown rather than being excluded by an unreliable language/POS guess. Known insufficient content
is rejected before MPNet work. The `mean128-content-v2` identity invalidates persisted vectors from
the earlier eligibility recipe; the public asset revision is unchanged.

## Focused BDD evidence

The following are focused results, not a full validation pass. External evidence is retained below
`/Users/tomwu/Documents/Codex/2026-10-29/`.

| Contract | Red / green evidence and limits |
| --- | --- |
| `HISTORYASSET-001`–`009` | Initial six tests failed eight assertions/stub errors. Separate late-progress, linked-owner/attribute and redirected-cleanup regressions failed before repair. Final nine Core tests passed using tiny injected files. `listentome-semantic223-assets/final-focused-outcome.json` and `independent-final-review.json`; real download transport was not exercised. |
| `HISTORYASYNC-001`–`012` | Held inference exposed deletion, cancellation, backend and overlapping-snapshot ownership failures; later tests covered unvisited records and pre-cancelled backend selection. `listentome-history223-async/final-focused-outcome.json`, `cancelled-selection-outcome.json` and `independent-source-review.json` retain commands and scoped results. |
| `HISTORYBACKEND-001`–`007`, `HISTORYMODELUI-001`–`004` | Actual shared-model tests exercise failed opt-out/storage recovery, current-record retries, stale search/answer fencing and controller consent/cancellation. The last functional batch passed seven transition and four controller methods. Raw commands/results are in `listentome-history223-native/`. |
| `HISTORYCONTENT-001`–`005` | Three Core methods first failed 11 assertions, then passed. The native routing test subsequently exposed “comida” being rejected by a short-query language/POS guess. A corrected Core regression failed four assertions, then all four Core methods passed without skips. `listentome-history223-content-eligibility/single-query-outcome.json` preserves the initial incorrect explicit-word test assumption separately. |
| `HISTORYMPNET-*`, `HISTORYMODELUI-005` | Real model/runtime and rendered Settings results remain bounded as described below. Fixtures do not prove downloaded-file integrity, model quality or physical-device behavior. |

The initial Core run reported **1,293 tests, seven optional skips, zero failures and
98.0316% coverage**, including the single-word helper repair. After relocating installed-language
checks as described below, the complete Core rerun passed **1,290 tests, seven optional skips,
zero failures and 97.7364% coverage**. Neither run validates the app UI.
The final native Mac batch passed all **17 functional methods** (seven transitions, four controllers
and six runtime checks). Its separate four language-quality methods still fail; the overall batch
therefore correctly exits 65. The earlier short-query failure and repair remain preserved.
The recipe-invalidation regression had four genuine red assertions before its identity fix.

## Quality and remaining acceptance

The original-style real-model language suite is still **no-go**: all four methods failed, with
15 assertions covering below-minimum paraphrase retrieval and generic/filler matches. Do not waive
those assertions, fit ranking cutoffs against the failures, or treat earlier fixed topical diagnostic
success as language acceptance. [Historical evaluation](semantic-search-evaluation.md), original
labels and failed outcomes remain unchanged. Passage reuse and language hints were already completed
parts of #223; this model addition does not redo them.

All six iOS runtime methods now pass with the actual retained model assets copied into the owned
simulator. The first attempt used an absolute container path that changed during app reinstall;
that harness failure is retained. The repaired test resolves the fixture within the current container
and verifies every file exists before inference. This is simulator inference, not physical-device
memory, speed or battery acceptance.

Rendered testing exposed a real Form-row hazard: tapping the containing control row invoked its
adjacent Remove action. The controls now occupy separate native rows. Later off-value failures came
from the test pressing the label row rather than its nested native switch; the repaired test keeps
the row-removal check and also operates/asserts the real switch. Download/Cancel, opt-in/Remove and
the corrected Recording explanation pass on iPhone; all three pass together on iPad. Captured native
screenshots were inspected for readable text and separate usable controls. They are QA evidence,
not uploaded App Store media. The simulator Busy launch refusal and every earlier failed attempt
remain preserved.

- Final Mac runtime/control result: 17 passed. Quality: four methods failed, 15 assertions; DE 2/8, ES 1/8, JA 4/8 and KO 2/8 versus the unchanged minimum of six.
- iOS UI: three journeys pass on iPhone; three pass together on iPad. Actual runtime: six passed, no skips.
- Full combined validation, exact-head CI and merge have not completed for this checkpoint. The unsigned native Mac application also builds; it was never installed or launched.
- Actual app installation, optional-download operation, device resource behavior, physical acceptance
  and source-matched release media remain separate. No new TestFlight/App Store publication is claimed.

The completed native runs and retained failed bundles are under
`listentome-history223-native/` (`final-reviewed-runtime-quality.*`, `ios-actual-runtime-relative.*`, `ipad-controls.*`,
`ios-switch-native-control.*`, `recording-copy-final.*` and all earlier failed attempts). These names identify evidence, not passing outcomes.

The final Recording Settings test, including interruption/resume assertions, passed once on each
owned phone and iPad simulator. Raw result files were hashed before deleting only those two
completed test devices. The unsigned Mac build was never launched and its exact `.dev` bundle
was moved to Trash. No production application data or permissions changed. Cleanup receipts and
the native-bundle preservation manifest remain with the external evidence.


## Hosted-runner test placement repair

The first hosted Core check on `ee4d25f` failed its BDD execution gate because the macOS 26
runner lacked Spanish lexical assets: two required selectors skipped. This is an observed
test-placement failure, not a product regression or a search-quality result. All original
16 equality-assertion sites, expected values and fixture text remain intact. The independent
unhinted-query check stays in Core; four installed-language/capability methods now run as required
native Mac tests. Missing native prerequisites fail explicitly rather than satisfying acceptance.
`HISTORYCONTENT-005` records the split explicit-language/multiword contract.

The repaired local Core BDD runner passed all **253 required selectors**. The full Core rerun
passed as recorded above, and all **four native eligibility methods** passed with no skips. These
are additional to the 17 earlier functional methods, not a rerun of that whole native batch.
Independent review verified every original assertion and unchanged runtime/quality source.
Evidence: `eligibility-native-placement.*`, `eligibility-placement-core-bdd.log`,
`core-after-placement.log`, `core-after-placement-coverage.json` and
`independent-eligibility-ci-placement-review.json` under the external native evidence folder.
There are now **235 BDD scenarios**. This repair changes no application behavior or quality rule;
the four failing model-quality methods and all original acceptance gates remain open.
