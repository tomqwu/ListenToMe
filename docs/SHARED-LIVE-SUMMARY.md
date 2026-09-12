# Shared live-summary scheduler and provider policy

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

Ollama is the default provider on both platforms. Existing explicit provider/model choices are
preserved. macOS retains its local versus Cloud privacy setting; iOS uses the configured Ollama
Cloud connection. Apple Intelligence is available for manual summaries on supported devices.
Selecting Apple pauses Auto with an explanation; it never silently routes speech to Cloud.

The native Auto experiment failed the quality gate (3/7 cases, including failures on repetition,
a bilingual correction and transcript instructions). It is isolated in
`scripts/ExperimentalAppleQuickProvider.swift`, outside both app targets. The benchmark runner
`scripts/benchmark-quick-apple.swift` uses that experiment for reproducibility. Shipping native
transport rejects automatic evaluation. This does not change the common scheduler's behavior
based on hardware capability.

## Validation and release evidence

Target versions are macOS 1.4.0 (10) and iOS 1.9.0 (17). Candidate checks and native benchmark
results are in `dist/shared-summary-evidence/`; per-release upload and artifact evidence live in
the respective versioned `dist/` directories. A candidate or simulator pass alone is not a
production acceptance claim. Physical iPhone/iPad acceptance remains separate from TestFlight.
