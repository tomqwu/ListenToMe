# Quick evaluator benchmark — September 12, 2026

The automatic evaluator retains **GLM 5.3 Flash** as its default. DeepSeek 4.1 Flash is faster and remains selectable, but GLM passed more checks in this small test. Existing saved selections are preserved. The scheduler is deterministic Swift code on the device; a model evaluates meaning, never owns timers or executes Summary/Deep automatically.

## Latest catalog and method

The authenticated Ollama Cloud `/api/tags` catalog identified `deepseek-v4.1-flash` (modified September 10) and `glm-5.3-flash` (August 26) as the latest Flash variant per family. The older `deepseek-v4-flash:0731` was excluded. These are catalog timestamps, not independently verified release dates.

Seven synthetic cases, repeated three times per model: greeting, explicit decision, repetition, bilingual correction, unresolved tradeoff, an instruction embedded in speech, and a corrected transcript segment. Requests alternate models sequentially, using the shipping prompt, streaming API, thinking disabled, temperature zero, 1,600 output tokens and the app's 15-second/16-KiB limits. Timing includes network and generation through the complete response. This is a workload benchmark, not general model accuracy or a statistically conclusive ranking.

| Final prompt / model | Valid protocol | All case checks | Median valid response | Slowest valid response | Over 5 seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| GLM 5.3 Flash | 21/21 | 21/21 | 3.13 s | 5.53 s | 1/21 |
| DeepSeek 4.1 Flash | 20/21 | 20/21 | 0.70 s | 5.18 s | 1/21 |

DeepSeek's rejected response occurred on a bilingual correction. The application retains the previous summary and retries invalid responses. An earlier prompt omitted Summary recommendations despite correct Quick bullets (GLM 15/21, DeepSeek 12/21 overall). Making explicit that Summary is a separate full meeting record fixed those omissions in the final sample.

## Apple Intelligence experiment

Foundation Models was available on this Mac. Under the earlier common JSON contract, 13/21 responses were valid and none passed every case check. A follow-up with native guided generation produced valid structure for all seven cases, but published greetings/repetition and accepted a transcript instruction changing a budget to 999. A Chinese correction preserved the correct facts but failed the English lexical rubric; that failure alone should not be read as a factual error. These results do not measure an iPhone's latency or battery usage, and Apple was not rerun against the final Cloud prompt.

For this release, Apple Intelligence remains available for manual summaries. Continuous evaluation requires an explicitly selected Ollama Cloud provider and pauses with an explanation for Apple; there is no automatic switch to Cloud. Native event scheduling needs no AI model.

## Reproduction and evidence

Run `python3 scripts/benchmark-quick-summary.py --output dist/quick-benchmark --repeats 3`. It obtains the existing Ollama credential from Keychain without emitting it and saves catalog, prompt, per-case checks and timings. Optional Apple runner: compile `scripts/benchmark-quick-apple.swift` with `swiftc -parse-as-library`, then pass its path with `--apple-runner`.

Local evidence: `dist/ios-1.8.0-build16-evidence/benchmark-final/` for the final Cloud run and `benchmark/` for the earlier common-contract and guided Apple experiments. Native application tests separately validate scheduling, state preservation, controls, and the real Cloud transport. Synthetic transcription is not physical microphone acceptance.
