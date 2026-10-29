# Optional History search model — #223 implementation checkpoint

October 29, 2026. Unmerged implementation checkpoint: application commit `ece5593` and its
documentation follow-up `0f94823` both passed all three required CI checks. The relevance-group
changes below are committed in existing draft PR #318.
This is not a merged feature, a language-support claim or a release. The latest combined
validation and installed acceptance recorded in [HANDOFF](HANDOFF.md) concern earlier source;
this implementation still needs full validation, current CI, completion of acceptance and merge.

## Implemented code

Apple embeddings remain the default. The optional pinned MPNet backend targets German, Spanish,
Japanese and Korean only where Apple lacks an installed embedding model. Enabling it preserves
Apple vectors and eligibility refusals for already-supported languages. It runs locally and keeps keyword fallback,
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
The earlier native Mac batch passed all **17 functional methods** (seven transitions, four controllers
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

- Latest Mac functional result: 22 passed, including the composite-backend check. The same batch
  has four quality methods failing 15 assertions: DE 2/8, ES 1/8, JA 4/8 and KO 2/8 versus the
  unchanged minimum of six. The aggregate exits 65; it is not a full pass.
- iOS UI: three journeys pass on iPhone; three pass together on iPad. The later actual-runtime
  suite passes all seven methods without skips, including strengthened model-group persistence checks.
- Full combined validation and merge remain incomplete. All three required checks passed on
  `ece5593` in run `40934516059` and documentation head `0f94823` in run `40938355944`.
  The newer Duo/README follow-up needs its own CI. The earlier unsigned native Mac application
  was never launched; the later signed sandbox checks in HANDOFF establish only their stated paths.
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


## Independent relevance groups and composite-backend preservation

The index now keeps each model's relevance population separate: its mean, sample count and top
score are computed within its declared group. Existing floor, gap and margin admission rules are
unchanged. Only admitted ranks are fused across groups; raw Apple and MPNet cosine scores are
not compared as one distribution. The legacy/default group and single-group ordering retain their
previous paths. Keyword results, global Related limits and Ask passage limits remain intact.
This prevents optional-model passages from suppressing otherwise valid default-model results; it
is not a calibration change or evidence that MPNet meets the language-quality gate.

Five focused Core group tests cover this policy. A deterministic multi-group Ask tie test actually
failed before the final tie-break repair: reversing input order reversed two equal-ranked results.
The same tests then passed within **55 focused Core tests, zero failures and zero skips**. The
single-group comparator was retained. Source review, exact commands and the one-assertion tie red
are preserved in
`/Users/tomwu/Documents/Codex/2026-10-29/listentome-history223-model-ranking/grouping-production-review-and-tie-outcome.json`.

The actual native composite-backend regression failed **five assertions** before the runtime's
relevance-group override. Its first attempt skipped because the model-assets environment variable
was not forwarded; that attempt is retained separately and is not the behavioral red. The subsequent
native batch passed **22 functional methods**, while the four unchanged quality methods failed
15 assertions. Evidence is under
`/Users/tomwu/Documents/Codex/2026-10-29/listentome-history223-native/`:
`model-groups-native-red-real.log`, `model-groups-native-green.log`,
`model-groups-final-native-quality.log` and their native result bundles.
`native-composite-grouping-review.json` identified a test-coverage gap: a future missing optional
vector could accidentally satisfy fallback-preservation checks. Additive checks now verify all 40
persisted current-model vectors, their source fingerprints, dimensions and finite nonzero content,
plus exactly both stored query-model tags. All **seven runtime methods passed with zero skips** on
Mac and an isolated iOS 26.5 iPhone simulator, including those checks. These additions do not invent
a new historical red. The initial iOS harness stopped before testing because system Python lacked
`hashlib.file_digest`; streamed hashing repaired it, and all six copied model files matched.

The current complete Core suite passed **1,298 tests, seven optional skips, zero failures and
97.6913% coverage**; the BDD execution gate observed all **261 required Core selectors**.
All **244 scenarios** pass structural checks and `make lint` passes. An extra noncanonical
`swiftlint --strict` invocation failed on warnings; it is not reported as a passed repository gate.
`independent-dirty-grouping-export-review.json` records no actionable code findings while preserving
quality and acceptance limits. None of these focused passes is a full `make validate-local` pass.

## Frozen sentence-window diagnostic — no application integration

A separate external paired diagnostic completed under freeze
`97422f2fcf5c28dd91a255404fa7c1db1f856e3fc8b93309ae3350dc9c8a43a4` at
`/Users/tomwu/Documents/Codex/2026-10-29/listentome-semantic223-sentence-window/`.
It reused the exact 32 positive documents, 32 positive queries, 40 negative queries and 12 fillers
from the current quality tests, with the same model, thresholds and acceptance rules. These are
historical calibration cases, not fresh holdout. The copied Core baseline is explicitly bound to
`bb50e673cf7892d64872c8e8ac4645b29214d6da`; this is not a run of the newer relevance-group changes.

Native sentence spans preserve complete source text. Child similarities are reduced to one maximum
per original parent, retaining parent-level statistics and complete original Ask text. Oversized
sentences are refused rather than prefix-truncated. The baseline adapter checks its outcomes against
actual copied `HistoryIndex`. A completed diagnostic command means the comparison ran, not that
language quality passed. `outputs/result.json`, `queries.json`, `parents.json`, `vectors.json` and
`terminal.json` retain the actual results and execution boundary.

| Language | Whole-parent positive recall | Sentence-window positive recall | Negative cases failing, whole → sentence |
| --- | --- | --- | --- |
| German | 2/8 | 4/8 | 1 → 1 |
| Spanish | 1/8 | 3/8 | 0 → 0 |
| Japanese | 4/8 | 4/8 | 2 → 2 |
| Korean | 2/8 | 3/8 | 1 → 2 |

Every language remains below six of eight. The negative-case count records a case failing either
Related rejection or meaning-only Ask rejection, not a count of individual assertions. Standalone
small-talk vectors still fail the unchanged gate in German, Japanese and Korean; Spanish passes
that check. Maximum aggregation also gives longer parents more opportunities for a high score.
The diagnostic therefore does not clear the original quality contract, justify threshold tuning,
prove additional-language support or change the application. All earlier failed outcomes and
original labels remain preserved; no sentence-window implementation has been integrated.

## Preserve installed Apple languages — October 29 follow-up

`HISTORYMPNET-012` and `HISTORYMPNET-013` reproduce an opt-in regression: this Mac has
Apple Spanish word/sentence revision 1, but the optional adapter previously replaced its vectors
and retained stale MPNet entries. The two new native methods failed **10 assertions** before the
routing change. The initial Swift async-autoclosure compilation failure and a skipped run caused by
missing test-runner environment forwarding are harness failures, not that regression red.

The adapter now snapshots actual Apple coverage only when constructing an installed optional
backend. Both detected and explicit language routes delegate supported languages exclusively to
Apple, including nil eligibility results. Query routing still follows stored model tags. The new
`apple-first-v1` signature includes sorted supported languages and invalidates old derived vectors;
original conversation text and language remain intact. Coverage refresh occurs on reconstruction
(relaunch or opt-out/on), not continuously while an existing adapter remains alive.

The Mac run passed **24 functional methods** with no skips. Its four unchanged MPNet quality
methods still failed **15 assertions**: DE 2/8, ES 1/8, JA 4/8, KO 2/8. The quality suite now
explicitly uses an unavailable Apple fallback and asserts MPNet tags, so installed Apple Spanish
cannot mask those failures. The combined run correctly exits 65.

The first iPhone run exposed a test prerequisite error: the fresh iOS 26.5 simulator has no Apple
Spanish embeddings, unlike this Mac. Its seven existing runtime methods passed while the two new
Mac-assumption methods failed three assertions. `HISTORYMPNET-015` now tests the actual native
capability branch, keeping the mandatory supported-Apple contract on Mac. All **nine iPhone runtime
methods pass with no skips**, including actual pinned MPNet vectors, missing-assets refusal,
nonempty compatible queries and persisted quantized-vector equality after migration. The observed
iPhone branch is Apple-unavailable; it is not physical acceptance or proof of both branches on iOS.

All 1,041 tracked inputs stayed unchanged in each native run. The owned simulator was deleted after
268 native-result files were preserved; other simulators and production apps were untouched.
Independent review confirms unchanged model-quality criteria and source-bound functional results.
All three required checks passed on `f5edcc5` in [CI run 40951031804](https://github.com/tomqwu/ListenToMe/actions/runs/40951031804). The fixture-only follow-up below needs its own CI. No full-validation, merge or release claim is made.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-29/listentome-history223-apple-routing/` retains
commands, complete native results, source hashes and separate harness failures. No model download,
private conversation, provider change or UI change was involved. The current README gallery was
reviewed; this routing correction does not alter its screens and requires no replacement image.

### German Apple asset availability and fixture correction

A bounded public `NLTagger.requestAssets` probe subsequently returned **available** for German.
This Mac now provides German lexical tagging and sentence embeddings, while word embeddings remain
unloadable. Japanese timed out; Korean was not requested after that timeout. The owned probe exited
and was reaped. Apple's separate asset job may continue; no native-download cancellation or permanent
unsupported status is claimed. No private text, application settings or permissions were involved.
Evidence is in the sibling `listentome-history223-natural-language-capabilities/asset-request-run/`.

The changed capability exposed a functional-test prerequisite error: the German smoke sample
contained only two nouns, below the unchanged three-content-word passage minimum. Two methods
failed three assertions. A separate native tagger probe confirmed the two nouns; the revised
synthetic smoke sentence adds a third noun and the tests now explicitly check eligibility. This
changes only the two runtime-test fixtures, not any quality corpus, threshold or production code.

After that fixture repair, **24 Mac functional methods and nine iPhone simulator runtime methods
pass without skips**. All 1,041 tracked inputs stayed unchanged per run. The actual MPNet quality
suite still fails all four methods, now **12 assertions** rather than 15 because German tagging
rejects previously unknown filler. Retrieval remains DE **2/8**, ES **1/8**, JA **4/8**, KO **2/8**;
this is still no-go. The earlier 15-assertion outcome remains evidence of the earlier asset state.
The second owned simulator was removed with absence verified and native result files preserved.
The README gallery is unchanged because no visible app behavior or layout changed in this follow-up.
