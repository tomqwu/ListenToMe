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
The JSON decision contract above therefore applies to Ollama-backed reads only. A manual Quick
Summary on Apple Intelligence uses `QuickSummaryContext.manualProseInstructions` and
`proseSummary(_:)` instead: the on-device model is asked for the displayed bullets in prose rather
than for the evaluator envelope it cannot be held to, and both platforms share one Apple transport
(`AppleIntelligenceProvider`), which refuses `quickEvaluation` and translates
`LanguageModelSession.GenerationError` into user-facing text on both platforms. Provider availability
stays locale-independent; iOS checks `supportsLocale` only against the conversation's own language,
where that language is known, so no device-locale check can disable the provider or change the default.

Providers declare their prompt window through `LLMProvider.maxPromptCharacters`. Ollama (local or
Cloud) declares none and keeps the provider-agnostic transcript and reference budgets unchanged.
Apple Intelligence declares `PromptBudget.appleIntelligenceCharacters` (8,000 — the same cap the iOS
manual summary path enforces), so macOS bounds every Listener/Quick/Deep prompt to that window and
reports the trim in the status line instead of failing with a context-window error.

The bound is on the *assembled* prompt, not on raw transcript text. `PromptBuilder.scaffoldCharacterCost`
measures the system prompt, persona/language directives, block headers and action instruction by
building the real prompt with placeholders, and `PromptBudget.allocate` divides what is left between
transcript, references, rolling summary and notes, holding back `answerReserve` for the reply.
Transcript characters are charged through `TranscriptSegment.promptCharacterCost`, which includes the
speaker label, so hundreds of short labeled lines cannot overrun the window. If a prompt still
arrives oversized, `AppleIntelligenceProvider` raises a clear error rather than silently answering
from a prompt whose front was cut away.

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

`AutomaticReviewCoordinator` is shared by both platforms. After a completed Quick evaluation catches up with input, medium/high recommendations enqueue Summary for meaningful context and Deep for substantive questions, risks or tradeoffs. Each uses its selected model. Auto remains opt-in and manual Generate remains available.

Full reviews run serially while Quick can continue evaluating new speech. Summary has a 30-second minimum between a completed review and the next automatic start, Deep 60 seconds; the first eligible review starts immediately, and a cancelled attempt does not spend that window. Pending work coalesces to the latest context. These are one-shot deadlines for queued work, never periodic model polling. Unchanged input cannot regenerate a completed review.

Stop, Auto off, provider changes and conversation changes cancel automatic work. Manual generation takes priority and suppresses older queued work it covers. Appended speech can follow an in-flight snapshot; wording revisions invalidate stale output. Complete valid responses replace previous output atomically. Failures preserve previous output and retry at most three attempts, with 5/10-second backoff. Input is capped at 60,000 normalized characters and output at 100,000 characters. Provider unavailability is shown without silently switching models. Deadlines, snapshot validity and the Quick pane's two kinds of output are described below.

The panels report waiting, queued, updating, up-to-date or failure status. The visible Auto label now describes all summaries, and explanatory text correctly describes speech-triggered evaluation with brief batching.

Live GLM testing exposed planning text despite `think: false`, exhausting the former 1,600-token budget halfway through valid final JSON. Quick now allows 3,072 generated tokens and a 30-second deadline while retaining the 16-KiB response cap and three-bullet/480-character display limit. Planning is never displayed; truncated JSON remains rejected. This budget change prevents the observed truncation without using unsupported Cloud structured-output options.

## Attributed input and user directives for automatic output (1.4.4 / iOS 1.10.2)

Automatic output previously read an anonymous wall of text and ignored the user's prompt settings,
so it could not say who committed to what, treated typed notes as speech, and overwrote a manual
answer in a different language.

### The shared attribution rule

Both platforms label every prompt line the way the manual prompts do:

- A transcript line is `"<speaker label>: <text>"`. The label is the diarized speaker name when
  there is one, otherwise `You` for the local speaker and `Others` for remote audio. iOS stamps
  `Microphone` as the *display* label for local speech; prompts map that back to `You`, because a
  device name is not a participant and the review prompts are told never to invent names. The iOS
  Markdown export keeps `Microphone`.
- The user's typed notes are one `"Notes: "` line. Blank notes produce no line. Both the evaluator
  prompt and the full-review prompts state that a `Notes: ` line is typed input, not speech.
- `QuickSummaryContext.pieces` repeats the label on **every** 600-character chunk, so a long
  utterance stays attributed past its first chunk.

Piece IDs are unchanged by attribution, so the acknowledged ledger, append-only live speech and
revision invalidation behave exactly as before; the label is a constant prefix, so appended words
still extend a piece already read. Renaming a speaker revises the affected pieces.

### Where the two sources still differ

The label format and the `Notes: ` marker are identical, but the two sources are assembled
differently and are *not* byte-identical for the same conversation:

| | macOS `automaticReviewSource` | iOS `summarySource` |
|---|---|---|
| Built from | `QuickSummaryContext.pieces` | the segment list, joined directly |
| Long utterances | split into 600-character chunks, each labelled | kept whole, labelled once |
| Provisional speech | only when 24+ trimmed characters, one source per speaker | the current partial is always included |
| Order | notes, then finals, then live | notes, then segments in order, partial last |

The Quick evaluator sees the same `pieces` on both platforms; only the full-review source differs.
Converging the two is tracked separately; nothing here depends on them matching byte for byte.

### User directives

`AutomaticReviewCoordinator.synchronize` takes an `AutomaticReviewDirectives` value carrying the
response language, the preset persona guidance and the attached reference material. The automatic
system prompt is built through `PromptBuilder.systemWithDirectives`, the same path the manual panes
use, so persona and language wording is identical. Automatic Deep also receives the attached
reference material in its user message, matching manual Deep; automatic Summary keeps the manual
listener contract of transcript evidence only.

`QuickSummaryContext.instructions(responseLanguage:)` carries the same setting into the Quick
evaluator by **replacing** the default follow-the-transcript rule, so the prompt never states two
contradictory language rules.

A queued or in-flight review keeps the directives it was created with, so a settings change
mid-request never relabels output produced from older context; the next review uses the new
settings. With no directives set, the review prompts and the Quick evaluator prompt are unchanged.
iOS exposes no response-language, persona or reference settings yet, so it passes none.

## Snapshot validity, review deadlines and the two kinds of Quick output (next release)

### Validity is decided per piece, not on the joined transcript

An automatic review used to stay valid only while the current joined input still had the dispatched
input as a **prefix**. The joined order is notes, finals, then `live:you`, `live:others`, so an
append only lands at the end when nothing before it moves. One keystroke in Notes, a mic partial
growing while system audio also had a partial, or one channel finalizing while the other was
mid-sentence all looked like a rewrite: the running review was cancelled, queued work was dropped,
and the mode's cooldown had already been spent.

Both platforms now hand `AutomaticReviewCoordinator.synchronize` the attributed `[Piece]` snapshot
alongside the prompt source, and `QuickSummaryContext.isContinuation(of:in:)` compares piece by
piece:

| Piece | Rule | Why |
|---|---|---|
| `notes:*` | never invalidates | Typed notes are the user's own context, not speech. A keystroke is new material for the next read, never a reason to cancel a 60-second review. |
| `live:*` | current text must still start with the text that was read; a piece that disappeared is accepted | Provisional speech only grows. Its disappearance means recognition finalized it, which republishes the wording as a final piece and enqueues its own work. |
| final | must still be present with identical text | A corrected or dropped final is a genuine transcript revision and does invalidate. |

`QuickSummaryContext.isCurrent` applies the same notes rule to Quick reads: a note edited during a
read no longer discards the completed evaluation (and model call); the newer note is simply read in
the next batch, with the acknowledged text as its `previousText`. It stays stricter than
`isContinuation` in one place — a `live:` piece that disappeared still invalidates a *read* — because
a read acknowledges wording into the incremental ledger, where accepting text that recognition has
since corrected would leave a superseded fact in memory; a full review is regenerated from the whole
transcript by the next review, so there the job may finish.

The same rule decides the bookkeeping *after* a review finishes on both platforms: when the current
input still continues the snapshot the review read, the mode is marked reviewed and the
recommendation is cleared. Comparing joined sources there would leave the recommendation outstanding
after a notes keystroke and re-run the identical model call. Only the transcript segments the
snapshot actually covered advance the listener ledger, so speech that arrived after the snapshot is
still summarized.

A mode's cooldown (Summary 30 s, Deep 60 s) now starts when a review **finishes**, not when it
starts, so a cancelled attempt never spends the window a completed review is entitled to.

### Deadlines scale with mode and input; a timeout is terminal for that input

A flat 60-second deadline failed long local reviews that the same model completes from the manual
pane, and the timeout was retried twice more with the identical request. The deadline is now

    deadline = min(base + base x characters / 20,000, 5 min) x (Deep ? 2 : 1)

The cap applies *before* doubling, so Deep is exactly twice Summary at every input size and no single
review runs longer than ten minutes. With the default 60-second base: 60 s for a short Summary, 195 s
for a 45,000-character Summary and 390 s for the same input as Deep. Exceeding *this* deadline is
terminal for that exact input: it is not retried, the pane says the review needed more than N seconds
on the selected model and suggests generating manually or choosing a faster model, and new speech (a
different input) tries again. Only the coordinator's own deadline counts — a provider's
`URLError.timedOut` (URLSession's idle timeout on a stalled connection) is an ordinary transient
failure, so it keeps the three-attempt 5/10-second backoff like any other.

### The automatic recap and manual Quick answers are separate

macOS Quick shows two different things: the automatic recap, and an answer the user asked for
("Draft reply", "Key terms", "Counterpoint"…). They used to share one property, so the next
automatic recap overwrote an answer the user was still reading, and the evaluator was told that
answer was the current recap (`visibleSummary`), which biased it toward `keep` and could flip the
recap's language.

`MeetingSession.quickRecap` now holds the automatic recap and is always what the evaluator receives
as `visibleSummary`. A completed manual answer is *fresh* for `ManualQuickAnswer.freshness`
(120 seconds on the session's injected clock, so expiry is testable); while it is fresh an automatic
recap updates `quickRecap` but not the pane, and the status reads "Recap updated · Showing your
generated answer". Freshness is measured on `MeetingSession`'s injected session clock, not a wall
clock of its own, so expiry is exercised in tests without waiting. The **Show recap** button is
offered whenever the pane differs from the current recap, *including after the window has elapsed* —
expiry releases the pane on the next automatic apply, and until then the user must still be able to
reach the newer recap. It is never offered while a manual answer is still streaming: a partial answer
differs from the recap by definition, and swapping it mid-stream would leave the recap spliced onto
the answer's remaining deltas, so `dismissQuickAnswer()` is a no-op then. Requesting another answer, clearing the conversation, renaming speakers or
the window elapsing ends the protection. Quick has no automatic review mode, so a manual Quick
answer is not registered as a completed review; it takes priority through `manualBusy` while it
streams and through this freshness window afterwards.

iOS needs no second state: its manual Quick refresh produces a recap under the same validated
decision contract, so `quickSummary` is both the recap and the manual result, and it remains the
evaluator's `visibleSummary`. Everything else above is shared core behaviour and is identical on
both platforms.

## Provisional speech in manual prompts, and one snapshot per live event

Live provisional text used to reach only the automatic Quick evaluator. The manual panes — the
"What should I answer?" hotkey, Clarify, Draft reply, Deep and the Listener refresh — were built
from finalized utterances alone, so on a recognizer that keeps a hypothesis volatile (Apple's
SpeechAnalyzer can keep one volatile for a whole recording) they answered the previous question, or
reported that none was asked (issue #113).

`ConversationStore.provisionalContext(maxChars:)` now exposes the current non-final speech, one line
per channel, for hypotheses of at least `provisionalMinimumCharacters` (24 trimmed characters — the
same threshold `QuickSummaryContext.pieces` applies to the live pipeline). Each line is tagged
`(provisional) ` so the model weighs it as unconfirmed wording rather than a quotation, and the
segments stay non-final. `ContextEngine.buildContext` and `MeetingSession`'s listener refresh append
those lines after the finalized window, and `PromptBuilder.provisionalNotice` — included in the Quick,
Deep and Listener user message whenever a non-final line is present — tells the model what the tag
means: unconfirmed, still-changing recognition that will be sent again once finalized, never to be
recorded as a decision, owner, deadline or action item, and never reported twice when the finalized
text repeats it.

They are charged to the same `PromptBudget` allocation as transcript text (with their speaker labels,
through `TranscriptSegment.promptCharacterCost`). Provisional text may *reserve* at most half the
transcript allowance and is then sized by what the finalized window actually spent, because
`recentContext` and the listener batch always keep at least one utterance however large: reading the
reservation alone could push the assembled prompt past Apple Intelligence's window. Because
provisional lines are never final, they do not enter the listener's `pendingSummaryIDs` ledger: the
same speech is still summarized once the recognizer finalizes it.

The Listener is the one pane that receives provisional speech **only when its ledger has caught up**
(`remaining` is empty). Its record is cumulative and is saved into `SessionRecord.summary`, so a
chained batch that re-sent the same unconfirmed wording each time would duplicate it in a saved
summary and never retract a hypothesis the recognizer later revised.

The live path also does its O(transcript) work once per event instead of several times (issue #116).
`MeetingSession.liveSnapshot()` memoizes the labeled pieces and the joined review source on
`(store.revision, partial texts, notes)`, and `handleLiveEvent` computes it once and passes it to the
review coordinator, the pending check and the scheduler. `AutomaticReviewCoordinator.synchronize`
skips normalization and the per-job prefix scan when the incoming pieces and source are unchanged.
On the macOS UI side, `checkpoint()` compares a cheap `SessionCheckpointKey`
(`revision` + title + outputs + notes + completion) before building a `SessionRecord`, the rail reads
`ConversationStore`'s incrementally maintained `youCount` / `othersCount` /
`transcriptCharacterCount` instead of rescanning every utterance per render, and `SessionSearchView`
loads the archive in `.task` rather than seeding `@State` in `init`, so the once-a-second elapsed
tick no longer re-reads and re-decodes every saved conversation on the main thread.
