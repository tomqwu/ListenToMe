# Shared live-summary implementation (candidate)

macOS and iOS use `ListenToMeCore.LiveSummaryScheduler`, `QuickSummaryContext` and
`QuickSummaryReader`. Platform adapters report finalized transcript, note, recording,
provider and manual-review events, execute the planned wake/cancel/read actions, and persist
accepted output. The scheduler never branches on platform or Apple Intelligence capability.

The common contract batches pending finalized speech for five seconds, ignores partials and
unchanged input, keeps the previous output on failure, and retries with bounded backoff.
A valid evaluation keeps or replaces Quick and recommends Summary/Deep with qualitative
confidence. Those reviews require a manual action. Transcript revisions replace previous
wording. Duplicate final segment IDs use their latest revision. Stop, Auto off and provider
changes cancel obsolete work. Auto is opt-in on both platforms.

`LLMRequest.Purpose.quickEvaluation` gives both apps identical Ollama generation controls:
thinking disabled, temperature zero and 1600 output tokens. The shared reader validates the
same final decision shape and applies a 15-second/16-KiB response limit. Local Ollama and
Ollama Cloud use that contract; a device does not need Apple Intelligence for either.

`SharedPlatform/AppleIntelligenceProvider.swift` is compiled into both apps. It adapts the
same incremental input to Foundation Models guided generation, then returns the common
decision shape for validation. Manual Apple summaries use ordinary native generation.
Unavailable native models report their availability reason and do not silently select Cloud.

## Release gate

This candidate is not released. Shared scheduling tests pass, but the live Apple evaluator
still fails factual/semantic quality cases, including greetings, repetition, a bilingual
correction and an instruction embedded in speech. Guided structure does not establish factual
correctness. Current tests do not justify claiming Apple Auto is equivalent in quality to
Ollama. The pending product decision is whether this release uses a chosen Ollama model on
all devices, or must also meet the quality gate using Apple's on-device model for Auto.

The existing iOS1.8.0(16) release is unchanged. Evidence for this candidate is kept separately
in `dist/shared-summary-evidence/`. Do not upload the candidate or call it production-ready
until the provider policy, quality gate and platform acceptance are resolved.
