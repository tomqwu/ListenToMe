# Vocabulary biasing — #236 controlled evaluation, October 26, 2026

The [recorded measurements](evaluations/vocabulary-236-2026-10-26.json) preserve synthetic transcripts,
scoring plans, native context/model metadata and source/fixture hashes.

## Decision and remaining acceptance

Do not integrate custom Dictation models from these results. On the four fixed synthetic waveforms, contextual Dictation recovered 41/64 scored terms on both platforms; custom models recovered 42/64 on iPhone and 41/64 on Mac. Pronunciations added no measured benefit. This is an SDK experiment, not a changed production engine or completed manual read-aloud acceptance. The issue remains open. Further local testing/participant requests for the current release have been stopped at the maintainer's instruction; preserve the existing evidence rather than requesting it again.

## Scope and provenance

The exact Medical and Software/Cloud scripts from [the manual smoke test](manual-smoke-test.md#domain-vocabularies-and-my-terms-222) were synthesized in Daniel and Samantha voices to mono 16-kHz WAV files, without audible playback. File inference ran on a physical iPhone 12 Pro Max/iOS 27.0 and the local Mac/macOS 27.0.1. The original baseline copied the production file adapter, audio feed, context helper and prepared-transcriber wrapper from `baff54015310a7dae6f4caac36b6a63c3b86b0eb`, with source hashes. All five copied adapter hashes still match `main` at `0901588`. The custom comparison was an isolated SDK alternative, shared byte-identically between platforms. Neither the iPad nor Watch was tested for vocabulary quality.

The baseline plan preceded inference; its fixed target scoring plan was written before transcript inspection but after baseline execution started. The custom plan preceded that phase's outputs. Supplied-target eligibility below is supplemental post-output descriptive analysis, not a newly preregistered acceptance threshold.

## Observations

The original production-adapter baseline had eight observations per platform. Every paired vocabulary-off/on transcript was identical: 36/64 target presence in either condition. Its existing helper suppresses setContext errors, so this alone does not prove contextual strings were accepted. The diagnostic phase explicitly recorded successful setContext operations and 100 retained context terms through preparation; SpeechTranscriber still scored 36/64.

| SDK mode | iPhone all targets | Mac all targets | iPhone supplied targets | Mac supplied targets |
|---|---:|---:|---:|---:|
| SpeechTranscriber, context reapplied after preparation | 36/64 | 36/64 | 18/36 | 18/36 |
| DictationTranscriber, no vocabulary | 37/64 | 37/64 | 20/36 | 20/36 |
| DictationTranscriber, contextual strings | 41/64 | 41/64 | 24/36 | 24/36 |
| DictationTranscriber, phrase model | 42/64 | 41/64 | 25/36 | 24/36 |
| DictationTranscriber, phrase + pronunciation model | 42/64 | 41/64 | 25/36 | 24/36 |

Compare custom Dictation models with contextual Dictation: the SpeechTranscriber row uses a different
engine, so its lower score does not establish a custom-model benefit.

All-target scoring uses 15 Medical and 17 Cloud terms in each voice: 64 opportunities. It counts normalized substring presence (NFKC, casefold, non-alphanumeric removal), not occurrence alignment or domain WER. Only 7/15 Medical and 11/17 Cloud targets exactly match supplied terms within the 100-term cap: 36 exact-eligible opportunities across two voices. Partial overlap, such as metoprolol versus metoprolol tartrate, is excluded from that supplemental denominator. My terms were empty in these runs; they do not establish custom-model personalization quality.

Each diagnostic platform produced 35 observations: 20 domain cases (four waveforms in five modes) plus ten ordinary-speech cases and five silence cases. The two 35-word ordinary controls had zero word edits in all tested control modes; no scored target was spuriously inserted. That does not test every trained phrase. All silence outputs were empty. Context operations reported zero errors and retained 100 terms after preparation. One run per case is not repeatability or broad safety/accuracy evidence.

## Custom model construction, cost and privacy

Each model trained only the same capped 100 ActiveVocabulary phrases, PhraseCount 10 each, without full test paragraphs or reference audio; model weight used the OS default. There were phrase-only and phonetic variants for both domains. The pronunciation variant inserted only supported graphemes present in those terms; every X-SAMPA token was validated against the actual supported inventory. Token validity does not establish correct pronunciation. The compiled configuration was supplied through DictationTranscriber.ContentHint.customizedLanguage before input started.

| Platform | Observed preparation range (s), four models | Per-model files (bytes) |
|---|---:|---:|
| iPhone | 0.971–1.271 | 6,588,335–6,624,021 |
| Mac | 0.594–0.730 | 6,588,326–6,624,012 |

These are observed compile/preparation costs with already available native framework assets, not cold-start or battery benchmarks. Byte totals include training export, compiled language model and vocabulary files. Models used a UUID-scoped private Caches directory: Library/Caches/ListenToMeVocabulary236/<UUID> inside the isolated phone app container, and ~/Library/Caches/ListenToMeVocabulary236/<UUID> on Mac. The folders use 0700 and files/folders are explicitly excluded from backup; phone metadata records NSFileProtectionCompleteUntilFirstUserAuthentication. The native test asserts backup exclusion, existence, term cap, silence/nonempty outputs and unchanged microphone permission; protection values are recorded metadata, not an additional claimed assertion.

No microphone, conversation, production settings, API keys or cloud inference was used in this SDK experiment. The temporary phone app identity is com.tomwu.ListenToMe.vocabularyProbe. The Mac portion is a CLI, with no Mac Dev app or permission reset. Synthetic file inference is distinct from the later release recording/playback checks.

## Evidence and execution limits

Canonical results: phone-custom-result.json (native XCTAttachment), mac-custom-source-parity-result.json, phone-custom-summary.json (1 passed, 0 failures/skips), phone-custom-protection-fixed.xcresult, custom-comparison-evaluation.json and supplied-target-evaluation.json. Original source/fixture/adapter manifests, plans, scorers, native logs and preparation/cache metadata remain in
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-vocabulary236/`. The checked-in artifact retains the
full synthetic observation data and baseline pairs without personal device names, hardware identifiers,
or absolute compiled-model paths. The Mac source-parity rerun reused the same dataset; it is not independent quality evidence.

Initial FinderInfo signing, Bundle resource-root, async DirectoryEnumerator and FileManager argument-label failures were harness/build errors, not product BDD red. Failed logs are preserved. No production behavior was implemented from this experiment, so no product red/green result or binary
release is claimed. Offline recounts independently reproduced every reported aggregate, eligibility
count, identical baseline pair and ordinary/silence control result; no new native/device inference was
started for this documentation change.

The issue's actual app read-aloud off/on comparison remains unfulfilled, including mid-recording additions, language switches and ordinary conversation. A future implementation would need observable native BDD for supported/unavailable engines, My-terms priority, context errors, locale changes, model preparation/cancellation, cache deletion and user controls; do not silently switch engines or weaken those gates to close the issue.
