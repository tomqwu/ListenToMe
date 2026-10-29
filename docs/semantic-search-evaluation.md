# Additional semantic-search languages — #223 evaluation

## Unmerged implementation checkpoint, October 29, 2026

The [optional-model implementation](history-search-implementation.md) now exercises the real native
MPNet runtime and explicit asset controls in the applications. It is still incomplete: the translated
original-style paraphrase/negative suites fail under unchanged ranking. These implementation results
do not replace, relabel or waive any historical evaluation below, and do not establish added language support.

## Native topical baseline, October 29, 2026

The current native diagnostic exposes omissions in the existing Related behavior; it does not
implement the additional-language feature. [The source-bound receipt](evaluations/semantic-223-native-topical-2026-10-29.json)
records the exact 194-input adapter freeze, 21-input content freeze, native fidelity audit and raw
observation hashes. The two original deterministic fidelity methods passed; four separately approved
installed-Apple observations then passed eight native method invocations with no skips or failures.
The external package exercises the actual Core index/ranking/request code with recorded instrumentation,
not the installed app. All inputs remained unchanged and raw results were copied and byte-verified.

On this Mac/runtime, English produced `w:en:1` and **Spanish produced `w:es:1`** stored vectors for
all six body passages. An exclusive historical “English/French/Chinese only” description must not
be treated as current availability evidence. German, Japanese and Korean retained explicit
`no_stored_vector` rows; their semantic coverage is incomplete, not a passing result or a measured
zero-accuracy language verdict. No model was downloaded or selected, and this observation does not
establish a completed Spanish or other additional-language feature. The chunk language hints are
null because these synthetic records carry no transcription-language metadata; that is not evidence
that a language recognizer failed.

The authored English cases and their correlated German/Spanish/Japanese/Korean counterparts were
reviewed and frozen before these observations. They are **new synthetic diagnostics, not blind
heldout data**. Each language has a seven-record fidelity context retaining a title-only lexical
control, plus a prospectively separate six-body context. Title-only is always outside semantic
eligibility; it is never credited as a rejected semantic negative. The two contexts are not
independent replications. All 80 query/context cases remain in the external comparison.

| Fixed context | Intended topical memberships | Returned intended | Omitted | Extra eligible Related results | Exact eligible Related sets |
| --- | --- | --- | --- | --- | --- |
| English, seven-record fidelity | 16 | 7 | 9 | 0 | 2/8 |
| English, six-body projection | 16 | 7 | 9 | 0 | 2/8 |
| Spanish, seven-record fidelity | 16 | 7 | 9 | 0 | 2/8 |
| Spanish, six-body projection | 16 | 7 | 9 | 0 | 2/8 |

These are descriptive membership counts against the frozen topical intent, with no new threshold
or acceptance rule. Only the museum-time and unrelated query sets match completely. The broad
waterproofing query returns only the roof inspection in English and nothing in Spanish, omitting
other explicit building-weatherproofing discussions. Seal-work, contractor-phone and unresolved-date
queries return only one of the two related roof discussions, even though Related should not require
every result to contain the answer. Actual scores reproduce the existing floor, mean-gap and
within-top-margin guards. The missing contexts therefore identify a topical-coverage gap under the
current embedding/ranking combination; this does not show that changing one cutoff would repair it.
The per-missing-context native scores and failed guards are retained without fitting new values.

Ask remains a separate observation. In each English context, the built requests include 7 of 13
intended useful-context memberships and omit 6, with no other passages. Spanish likewise includes
7 and omits 6, but also includes the sensor-calibration passage for the waterproofing and title-only
queries. Keyword and semantic result flags, retrieval order and exact request excerpts are retained
per query. Japanese can build lexical requests despite having no stored semantic vectors, so a built
request is not proof of semantic coverage. **No provider was invoked and no answer exists**:
missing-phone abstention, unresolved-date handling, factual accuracy and citations were not tested.

All earlier failed screens and no-go decisions below retain their original corpus, criteria and
scope. The new observations neither reinterpret those outcomes nor establish general quality,
additional-language support, native application integration or physical-device acceptance.

## Decision, October 26, 2026

**No-go for the proposed four-language model integration.** The current app still uses Apple's
existing on-device embeddings and keyword fallback. Passage-vector reuse and per-conversation
language hints are already implemented; the language expansion in [#223](https://github.com/tomqwu/ListenToMe/issues/223)
remains open. No application code, dependency, settings, model selection or release version changed
in this investigation. The downloaded public research models are outside the app and are not bundled.

This continues the October 25 Apple contextual-embedding and multilingual E5 experiments. Repeating
those variants is not additional acceptance. The new work tests a different sentence-model family,
validates tokenizer compatibility and uses a new held-out corpus after calibration.

## October 27 calibration follow-up

The [live #223 evaluation log](https://github.com/tomqwu/ListenToMe/issues/223) records subsequent author-reference rerankers, query/language confidence calibration, translation and a bounded contextual-whitening screen. Every previously observed corpus is calibration for these later methods; earlier frozen holdout outcomes above remain historical evidence. No later method passed the unchanged four-language gate, and no additional app language, dependency, provider or privacy behavior changed. The whitening screen rejects only five frozen methods on stored 16-anchor/three-topic vectors per language, not whitening generally or current Apple model quality. Its eight evaluator/guard checks, immutable plans, scores/transforms and independent review are external evidence; they are not native integration or physical resource acceptance. The language expansion remains open.

## Reproduction and privacy

App source inspected: `b9cf9ce1accfccc69b0fd2a8a994d629e9df33e2`. The isolated Swift package pins
`swift-embeddings` 0.0.23 and `swift-transformers` 1.1.9. Models run locally through MLTensor with
the authors' pooling and token limits. All passages and questions are synthetic; no microphone,
private conversation, audible playback, remote embedding request or production setting was used.
Only public model assets were downloaded. SHA-256 manifests preserve the exact assets, datasets,
probe source, executable, logs and scores. An initial generic-tokenizer/BPE abort occurred before
inference and is a probe compatibility error, **not a product BDD red or model-quality result**.

The generic `PreTrainedTokenizerFast` metadata selected BPE despite actual Unigram tokenizer data.
The probe uses the registered Unigram class in memory without changing the original downloaded
assets. Swift and the reference tokenizer matched **80/80 strings exactly** for MiniLM and MPNet.
Token parity does not establish embedding-vector parity or application correctness; those would
need separate reference and native integration checks before adoption.

Public model sources:

- [Multilingual MiniLM](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2),
  revision `e8f8c211226b894fcb81acc59f3b34ba3efd5f42`; Bert adapter, 128 tokens, mean pooling, no prefixes.
- [Multilingual E5-base](https://huggingface.co/intfloat/multilingual-e5-base), using the preserved
  October 25 asset hashes, XLM-RoBERTa, mean pooling and required query/passage prefixes.
- [Multilingual MPNet](https://huggingface.co/sentence-transformers/paraphrase-multilingual-mpnet-base-v2),
  revision `4328cf26390c98c5e3c738b4460a05b95f4911f5`; XLM-RoBERTa adapter, 128 tokens, mean pooling, no prefixes.
  Its six selected public assets total **1,126,353,221 bytes**; this is a substantial optional download.

## Results and separation of calibration from holdout

The first fresh corpus has eight topics in German, Spanish, Japanese and Korean: 32 positive
paraphrases and 16 unrelated queries. Dataset and ranking rules were written and hashed before
inference. Under unchanged current relevance thresholds, MiniLM retrieved **18/32** expected
matches, ranked **30/32** correctly and rejected **16/16** unrelated queries. It fails the frozen
per-language quality requirements. MPNet with the same rule retrieved **28/32**, ranked **31/32**
correctly and rejected **16/16** negatives; it also failed per-language requirements.

E5-base was separately rechecked with its previously calibrated rule (floor .79, minimum gap .035,
within-top margin .01), unchanged. It retrieved **28/32**, ranked **30/32** correctly and rejected
**15/16** unrelated queries. The Japanese false positive and raw ranking errors prevent adoption.

All four observed MPNet datasets were then explicitly reclassified as **calibration**, not retained
as unseen evidence. A parameter sweep selected floor **.45**, minimum gap **.10**, margin **.08**
(and conservative small-library floor **.55**): 97/104 expected matches, 40/40 unrelated queries
rejected, no incorrect returned conversation. Per-language recall was at least 24/26. This is tuning
evidence and cannot establish acceptance on its own.

The selected rule and unchanged acceptance criteria were frozen before a second, newly written
corpus: ten new topics per language, 40 positive paraphrases and 16 unrelated queries. Require at
least **80% expected-match recall**, **90% raw top-rank accuracy** per language, every unrelated
query rejected, and no additional incorrect related conversation. Dataset SHA-256:
`d5f4b97db631f0e2a428b489ebeea0e91dd1b186ffcee73cb4f76b8e7ad4cf3e`. Observed ordering is plan freeze → corpus creation → inference.

| Language | Correct raw top rank | Expected match retrieved | Unrelated rejected | Incorrect extra hits | Frozen gate |
| --- | --- | --- | --- | --- | --- |
| de | 10/10 | 10/10 | 4/4 | 0 | pass |
| es | 10/10 | 7/10 | 4/4 | 0 | fail |
| ja | 9/10 | 9/10 | 4/4 | 0 | pass |
| ko | 10/10 | 10/10 | 4/4 | 0 | pass |

**Overall gate: fail.** Spanish recall is 70%, below the required 80%. Correct raw rankings and
rejected negatives do not compensate for that failure. Do not retune against these three misses
and call the same data unseen. Independent read-only review confirmed the evaluator applies the
frozen rule and criteria consistently and that the failure must remain a no-go.

## What this evidence does not establish

These small synthetic corpora are diagnostics, not external benchmarks, all-language accuracy,
physical iPhone/iPad latency, battery or memory acceptance. The proposal still needs reference-vector
checks, actual HistoryIndex/native adapter tests, truncation and multi-passage/multi-conversation
cases, small libraries and model-specific ranking behavior. Any integrated model also needs explicit
asset-download consent, progress/cancellation/removal, integrity and protected backup-excluded
storage, bounded asynchronous inference and actual device compatibility/resource checks. None of
these requirements is waived by a tokenizer match or successful model execution.

The connected iPhone 12 Pro Max and iPad Pro 12.9-inch (4th generation) were inventoried separately:
both report Developer Mode enabled and no passcode required. Simulator Watch entries do not prove
that a physical paired Watch is connected. This is setup evidence, not physical feature acceptance.

Full reproducible evidence is preserved outside the worktree under
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-semantic223/`: frozen plans/corpora,
`minilm-local-probe.swift`, `e5-local-probe.swift`, `mpnet-local-probe.swift`, pinned package lock,
asset/hash manifests, tokenizer parity, raw scores, calibration grid, `run-heldout.py`, final
evaluation and execution logs. Earlier October 25 evidence remains intact. No new binary release
or TestFlight upload is needed for this documentation-only evaluation record.
