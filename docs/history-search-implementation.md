# Optional History search model — #223 implementation checkpoint

## Current delivery scope — October 30, 2026

The optional MPNet runtime, installer and Settings controls are withdrawn from the current PR #318
candidate because their language-quality gate failed. The complete experimental source and original
tests remain in commit `08521d5f2bf7d5e20410359e6560bd2d5c066eb6`; the failed native results and
independent evaluations remain preserved. This is a scope withdrawal, **not a passing quality result
or completion of #223**. No threshold, corpus label or original acceptance criterion is relaxed.

The candidate retains independently tested Apple vocabulary/query compatibility and generic-query
repairs, indexing cancellation/save/Clear guards and relevance-group isolation. Both applications
use Apple embeddings with keyword fallback. Old experimental preferences and downloaded files are
left intact but cannot activate the withdrawn runtime. A fresh candidate validation is required;
historical passes below do not establish its result.

The actual Settings scope regression failed one assertion, then passed unchanged after withdrawal.
The new native cache-migration baseline passed on first execution after correcting a test-target
selector; that selector error is not a product regression. Independent review cleared the narrow
boundary. BDD236, lint and diff checks pass; full combined validation and current CI remain pending.
[Source-bound focused evidence](evaluations/history-delivery-scope-2026-10-30.json).

The following sections describe the preserved experimental checkpoint, not currently shipped controls.

## Historical implementation — October 29, 2026

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
See [the runtime](https://github.com/tomqwu/ListenToMe/blob/08521d5f2bf7d5e20410359e6560bd2d5c066eb6/SharedPlatform/MultilingualHistoryEmbedder.swift) and
[the index](../Sources/ListenToMeCore/HistoryIndex.swift).

[The asset owner](https://github.com/tomqwu/ListenToMe/blob/08521d5f2bf7d5e20410359e6560bd2d5c066eb6/Sources/ListenToMeCore/HistoryModelAssets.swift) downloads only on an explicit
install action: six immutable public files, **1,126,353,221 bytes** (1.13 GB), at revision
`4328cf26390c98c5e3c738b4460a05b95f4911f5`. Readiness checks never download. Size and streamed SHA-256
checks precede activation; staging, cancellation, removal and unsafe-path refusal preserve unrelated
files. Storage uses the existing protection and backup-exclusion policy. No additional model assets
were downloaded during this implementation turn; native tests reused retained local research assets.

[Shared Settings](https://github.com/tomqwu/ListenToMe/blob/08521d5f2bf7d5e20410359e6560bd2d5c066eb6/SharedPlatform/HistoryLanguageSettings.swift) exposes download, progress,
Cancel, opt-in and Remove. [Its owner](https://github.com/tomqwu/ListenToMe/blob/08521d5f2bf7d5e20410359e6560bd2d5c066eb6/SharedPlatform/HistoryLanguageModel.swift) fences late
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


### Case-sensitive Apple vocabulary regression — October 29 follow-up

German word embeddings became loadable after the earlier sentence-only snapshot. An unchanged
synthetic travel passage then exposed a separate default-Apple defect: the adapter lowercased every
noun before lookup. A frozen native probe found **five original-spelling vocabulary hits and zero
lowercase hits**, both normally and with network access denied. Language detection was German and
the sentence model returned a finite vector; the actual adapter nevertheless returned nil because
its existing word-model branch takes precedence. No threshold or corpus change was involved.

`APPLEWORD-001`–`005` cover the exact five-noun vector, compatible topic queries, unchanged content
minimum/filler refusal, empty-cache migration with archive-byte preservation, English normalization
and Spanish lowercase fallback. The native red reproduced **two failing methods / six assertions**;
the other two original controls passed. The supplemental Spanish control passed on the old code
and is baseline compatibility evidence, not a regression red.

The repair keeps English lowercase lookup, tries original spelling for other languages, and retains
lowercase fallback when that spelling is absent. Each token contributes once. Signature v3 rebuilds
stale derived entries, including cached empty results; conversation files are unchanged. Sentence
fallback, noun eligibility, model tags and relevance thresholds are unchanged.

All **five new methods pass**; the wider native run passes **29 functional methods** with no skips.
Its four unchanged MPNet quality methods still fail **12 assertions** (DE 2/8, ES 1/8, JA 4/8, KO 2/8),
so that combined command correctly exits 65. All **1,043** tracked/new source inputs stayed unchanged
in each run. A separate unchanged Apple German historical baseline now stores real `w:de:1` vectors,
but finds **4/8** paraphrases and incorrectly admits hiring for “der Plan für nächste Woche”. It still
fails two assertions. The preceding zero-vector baseline was incomplete coverage, not measured
retrieval quality. Neither result establishes additional-language support or production readiness.

Evidence folders under `/Users/tomwu/Documents/Codex/2026-10-29/`:
`listentome-history223-apple-vocabulary/`,
`listentome-semantic223-apple-german-word-diagnostic/`, and the original/`-case-fix`
`listentome-semantic223-apple-german-baseline/` packages. Complete native results, frozen inputs,
commands, terminal/reaping records and prior failures remain intact. No visible UI changed; the
README gallery remains labelled with its actual capture sources and needs no new image for this
lookup correction. Full validation, current-source physical acceptance and merge remain open.


The full Core suite passes **1,298 tests / seven optional skips / zero failures**, with **97.6925%**
coverage and all **261 Core BDD selectors** observed. All **253** scenarios pass structural checks.
An overlong new test-string line initially failed lint; formatting preserved its exact text, the
five native methods passed again, and lint now passes. Nine iPhone simulator runtime methods pass,
zero skips; that simulator reports Apple Spanish unavailable and exercises the optional-runtime
branch. This is not physical or Apple German iPhone acceptance. The owned simulator was deleted
after all **248** native-result files were hashed and reverified; other simulators were preserved.
Independent source/terminal reviews cleared these bounded results, with all model-quality failures
retained. The current source still requires hosted CI and cannot pass full validation while those
quality contracts remain red.


### Stored Apple query representations — October 29 follow-up

An archive can retain genuine Apple sentence vectors after the same language's word model becomes
available. The previous query adapter chose the current word model and then filtered it out against
the stored sentence tag, leaving that archive without a compatible semantic query. `APPLEQUERY-001`
reopens a persisted genuine German sentence vector under the existing signature and requires a
Related result, exact query-vector agreement and unchanged persisted bytes. Keyword survival alone
cannot pass. `APPLEQUERY-002` checks both real word/sentence representations, stable ordering and
unchanged word-only behavior. Both methods failed before repair: **five assertions**.

Queries now load each requested canonical type/language/revision and check the returned model's
actual revision. Passage vectors, signature, content minima, language selection and relevance
thresholds remain unchanged. `APPLEQUERY-003` preserves the two-word sentence-query minimum and
rejects malformed tags and unsupported revisions. Review reproduced three empty-field parser
failures; preserving empty fields fixes those failures. A fourth failure in that supplemental run
was an incorrect test assumption: Apple's sentence loader returns revision 1 when asked for
unsupported revision 2 rather than nil. The corrected test checks actual revision mismatch and
requires no query vector under the unsupported tag; the production guard already rejected it.

The three new methods pass with no skips. The wider run passed **32 functional methods** while the
four unchanged MPNet quality methods failed **12 assertions**, so its aggregate exit remains 65.
The full Core suite passes **1,298 tests / seven optional skips / zero failures**, with **97.6489%**
coverage. Each completed run preserved all **1,045** tracked/new inputs. Evidence, original red,
parser red, corrected green, full native results and independent reviews are retained under
`/Users/tomwu/Documents/Codex/2026-10-29/listentome-history223-stored-model-query/`.
This is a saved-model compatibility repair, not acceptance of additional-language relevance.
No visible UI changed, so the README gallery retains its source-labelled images. Full validation,
current-source device acceptance, exact commit CI and merge remain outstanding.


All **261 Core BDD bindings**, **256 structural scenarios**, repository lint and diff checks pass.
Nine iPhone simulator runtime methods pass without skips on an isolated iOS 26.5 simulator; Apple
Spanish is unavailable there, so this verifies optional/missing-assets routing rather than German
Apple-model or physical acceptance. Build-for-testing passed first; the initial install attempt
failed because the new simulator was still shut down. After booting that owned device, the existing
unchanged build completed the runtime suite. That harness failure remains recorded separately.
No Mac Dev session or permission change was needed. Independent source, terminal and documentation
reviews cleared the bounded fix; exact commit CI and full acceptance remain separate gates.


### Generic query parity — October 29 follow-up

Installed Apple German/Spanish models admitted unrelated topics for generic planning questions.
The native regressions use the **unchanged** eight-topic corpus: only its test visibility changed
so the new methods can reuse it. `GENERICQUERY-001`–`008` require actual Related/retrieve/request
outcomes, literal keyword preservation, real topics within the same framing, exact stored sentence
routing, optional-model refusal, compounds and capability/one-word uncertainty. Native red executed
six methods: **four failed / 36 assertions**; two positive controls already passed. The initial
async-in-XCTUnwrap compile failure is a harness failure, not red. Core literal-term red failed seven
assertions, then ten after adding polysemy controls, all before implementation.

`HistoryQueryVocabulary` contains reviewed whole-token DE/ES equivalents of the existing English
concepts, with explicit common inflections. Semantic query nouns and narrower Ask stopwords remain
separate. Ask still retains question/project/day/month/year and decided equivalents. Contar-family
account/story terms and German painting `malen` are not Ask exclusions. This is neither stemming nor
a failed-phrase blacklist, and cannot distinguish every proper name from an identical generic word.
The prospective concept mapping and both versions of its independent review are retained externally.

Known insufficient multiword queries are refused by Apple word/sentence routes and the existing
optional adapter. Unknown linguistic capability keeps its prior behavior; no Japanese/Korean support
is inferred. An initial implementation incorrectly treated a stored-model language as a query hint
and applied Ask localization to a single guessed word. Review reproduced **one native assertion and
four Core assertions**. The final implementation evaluates Apple queries without a hint and applies
new Ask exclusions only to multiword queries. Existing English exclusions remain unchanged.

The final native selection passes **38 functional methods**, including all six new methods and
actual optional inference, while four original quality methods still fail **12 assertions**
(DE 2/8, ES 1/8, JA 4/8, KO 2/8). Aggregate exit 65 remains a failure. A separate focused final run
passes 18 methods. Both greens preserve all **16** actual persisted passage hashes from a pre-fix
baseline; no passage recipe, model signature, minimum or ranking cutoff changed. The new full-topic
positive controls prove retention, not improved paraphrase recall. Core passes **1,300 tests / seven
optional skips / zero failures**, with **97.9288%** coverage. Each final supervised native/Core run preserved
all **1,048** tracked/new inputs. Nine iPhone simulator runtime methods also pass with no skips;
build/runtime input inventories remain unchanged. All 263 Core BDD bindings, 264 structural scenarios,
lint and diff checks pass. No provider request, private conversation or download was used.

Evidence: `/Users/tomwu/Documents/Codex/2026-10-29/listentome-history223-generic-query/`; prospective
mapping/review: sibling `listentome-history223-generic-query-plan/`. Exact commands, source inventories,
original failures, xcresults, passage hashes and independent reviews are retained. No visible UI
changed, so the README gallery keeps its source-labelled captures. Full validation, physical/device
acceptance, exact commit CI and merge remain separate outstanding gates.
