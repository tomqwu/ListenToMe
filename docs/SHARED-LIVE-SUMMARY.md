# Shared live-summary scheduler and provider policy

macOS and iOS use `ListenToMeCore.LiveSummaryScheduler`, `QuickSummaryContext` and
`QuickSummaryReader`. Platform adapters report live and finalized transcript, note, recording,
provider and manual-review events, execute the planned wake/cancel/read actions, and persist
accepted output. The scheduler never branches on platform or Apple Intelligence capability.

The common contract batches pending speech for five seconds. Non-final hypotheses become eligible
at 24 trimmed characters; shorter fragments wait for more speech or final recognition. Unchanged
input does not poll. Failed reads keep previous output and retry with bounded backoff.
A valid evaluation keeps or replaces Quick and recommends Summary/Deep with qualitative
confidence. Medium/high recommendations enqueue the corresponding full review while Auto is on; low confidence stays manual. Transcript revisions replace previous
wording. Duplicate final segment IDs use their latest revision. Stop, Auto off and provider
changes cancel obsolete work. Auto is opt-in on both platforms.

`LLMRequest.Purpose.quickEvaluation` gives both apps identical Ollama generation controls:
thinking disabled, temperature zero and 3072 output tokens. The shared reader validates the
same final decision shape and applies a 30-second/16-KiB response limit. Local Ollama and
Ollama Cloud use that contract; a device does not need Apple Intelligence for either.

macOS defaults to Ollama with its local versus Cloud privacy setting. iOS defaults a fresh install to
on-device Apple Intelligence and falls back to Ollama only where Apple Intelligence cannot run, so
Auto starts paused there until Ollama is selected. Existing explicit provider/model choices are
preserved on both platforms. iOS uses the configured Ollama connection — Ollama Cloud, or a server
the user entered. Apple Intelligence is available for manual summaries on supported devices.
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

## Backlog progress and concise recaps (1.4.1 / iOS 1.9.1)

A successful Quick update is visible immediately while remaining batches continue. Catching up labels the partial coverage; full review suggestions still wait for complete context. Automatic responses allow at most three bullets and 480 characters. iOS manual Quick uses the same validated response contract and never displays model planning or JSON.

## Live speech events (1.4.2 / iOS 1.9.3)

Previously, transcript text could remain non-final throughout a recording and never reach Quick. Both adapters now include eligible provisional text, using one stable source ID per speaker. Append-only speech can extend a pending read without invalidating the prefix already evaluated; wording revisions invalidate stale responses. Final recognition explicitly replaces the provisional source.

iOS Status details shows received speech callbacks, final callbacks, fired scheduler checks, model checks and completed reads. These diagnostics help distinguish recognition, scheduling, provider and response failures on a real device. Tests reproduce the old failure, exercise non-final speech through the visible iOS controls and macOS session, and verify final correction and no polling during silence. Physical iPhone acceptance remains unverified until tested on a device.

## First takeaway (1.4.3 / iOS 1.9.4)

Physical-device diagnostics showed three completed reads, no unread input and no error despite an empty recap. A live GLM-5.3-flash replay reproduced the old prompt withholding both “test for Azure Cloud” and “Help me understand the APM management.” The revised shared prompt treats a named topic or substantive question as sufficient for the first recap, without requiring a decision. It summarizes questions without answering them or expanding ambiguous acronyms. Pure greetings and generic subject-free microphone tests can still return keep; repetition already covered by the recap remains unchanged. Empty successful reads now have an explicit “No takeaway yet” status.

## Automatic full reviews (iOS 1.10.0)

`AutomaticReviewCoordinator` is shared by both platforms. The macOS binary release is deferred at the maintainer’s request. After a completed Quick evaluation catches up with input, medium/high recommendations enqueue Summary for meaningful context and Deep for substantive questions, risks or tradeoffs. Each uses its selected model. Auto remains opt-in and manual Generate remains available.

Full reviews run serially while Quick can continue evaluating new speech. Summary has a 30-second minimum between starts, Deep 60 seconds; the first eligible review starts immediately. Pending work coalesces to the latest context. These are one-shot deadlines for queued work, never periodic model polling. Unchanged input cannot regenerate a completed review.

Stop, Auto off, provider changes and conversation changes cancel automatic work. Manual generation takes priority and suppresses older queued work it covers. Appended speech can follow an in-flight snapshot; wording revisions invalidate stale output. Complete valid responses replace previous output atomically. Failures preserve previous output and retry at most three attempts, with 5/10-second backoff. Requests time out after 60 seconds; input is capped at 60,000 normalized characters and output at 100,000 characters. Provider unavailability is shown without silently switching models.

The panels report waiting, queued, updating, up-to-date or failure status. The visible Auto label now describes all summaries, and explanatory text correctly describes speech-triggered evaluation with brief batching.

Live GLM testing exposed planning text despite `think: false`, exhausting the former 1,600-token budget halfway through valid final JSON. Quick now allows 3,072 generated tokens and a 30-second deadline while retaining the 16-KiB response cap and three-bullet/480-character display limit. Planning is never displayed; truncated JSON remains rejected. This budget change prevents the observed truncation without using unsupported Cloud structured-output options.
