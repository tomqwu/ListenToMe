# Event-driven live summary scheduler

## Roles

`MobileSummaryScheduler` is a deterministic event/action policy. `MobileQuickContext` prepares bounded
incremental input and acknowledges source revisions. `MobileQuickReader` runs one evaluator request,
validates the result and applies the scheduler's resulting actions. `MobileSession` connects these
components to the recorder, settings, persistence and manual review controls.

The scheduler itself does not need an AI model. Semantic evaluation uses the selected Ollama Cloud Quick model. Apple Intelligence remains available
for manual summaries; Auto pauses when Apple is selected because the local evaluator did not meet
this release's reliability checks. It does not silently change provider or send local
content to Cloud as a fallback.

## Events and actions

| Event | Planned action |
| --- | --- |
| New completed transcript or edited notes | Enqueue a coalesced Quick evaluation if Auto is enabled and recording. |
| Partial hypothesis | Display immediately; do not send it to the evaluator. |
| Source correction or Restore original | Enqueue the changed source, including its previous wording. |
| Five-second batch deadline | Evaluate if new source data is pending and the model is available. |
| New speech during an evaluation | Retain it for the next batch; never run a second Quick evaluation concurrently. |
| Valid `keep` result | Commit running context and acknowledged sources, preserving the visible summary exactly. |
| Valid `publish` result | Commit context and replace the complete Quick bullet list. |
| Summary/Deep recommendation | Show its grounded reason and qualitative confidence in the relevant panel; do not run it automatically. |
| Manual review completes | Clear the suggestion only if its source snapshot is still current; tell the next evaluator that review was performed. |
| Error, timeout, or malformed result | Keep output/context/source acknowledgements unchanged and retry unread data with backoff. |
| Auto off, Stop, background, or conversation change | Cancel the pending wake/evaluation; reject late results. |
| Quick provider/model/key change | Cancel the old evaluation and schedule with the newly selected settings. |
| Manual Quick refresh | Cancel automatic Quick work, perform the requested full snapshot summary, then resume pending evaluations while recording. |

Batch timing starts with the first pending source event; later events do not reset its deadline.
The normal cadence is five seconds between request starts. A slow request is followed by a catch-up
read once finished if its cooldown has elapsed. Speech correction gets up to two extra seconds relative
to the batch deadline, without indefinitely postponing Quick under continuous speech. There is no
repeating idle polling loop and no Cloud call for unchanged input. Summary and Deep requests have their
own manual slot and can run alongside the single automatic Quick evaluator.

Failures retry at 10, 20, 40, then at most 60 seconds with the default cadence. Each evaluator call has
a 15-second deadline and a 16 KiB streamed-response cap. New speech remains queued while retrying.
The actual completion time depends on the selected model and network; five seconds is a scheduling
window, not a latency guarantee.

## Evaluation contract

The model receives new/changed pieces with stable source IDs, their previous wording when edited,
one recent acknowledged speech piece, the visible summary, a compact running context, pending review
suggestions, and reviews completed since its previous read. Inputs are conversation data, not executable
instructions. An example response:

```json
{
  "action": "publish",
  "context": "Delivery Tuesday; Peter confirms. Source s3 supersedes s1.",
  "bullets": ["Delivery moved to Tuesday; Peter will confirm."],
  "reviews": [{"mode": "summary", "confidence": "high", "reason": "The delivery decision changed."}]
}
```

`keep` requires an empty bullet list; `publish` requires one to five bullets. Context is limited to
2,000 characters and bullets to 1,500 total characters. At most one recommendation is accepted per
review mode, with a reason of at most 160 characters. Confidence is low/medium/high, representing the
model's assessment of the recommendation, not a measured probability. Reviews are suggestions only.
Malformed or incomplete objects never reach the UI. Only a complete final object is decoded when a
Cloud model prepends reasoning; the preamble and protocol JSON are not displayed.

Long notes/transcripts are split into 600-character source pieces and evaluated in bounded batches
(up to 1,200 new/previous-text characters, at most eight pieces). No transcript is discarded. Intermediate
reconstruction output is held until that backlog has been read. Source edits arriving during a request
invalidate its result; later new pieces are kept pending without invalidating already-read pieces.

The original transcript and published summaries are saved as before. Working evaluation context and
recommendations are session-local; reopening a conversation rebuilds them from original finalized text
on the next recording. Stop preserves the last published Quick Summary and cancels pending reads;
manual Refresh can summarize the complete stopped transcript. Original audio is not retained.

## Verification

- Scheduler tests use an injected clock to prove batching, bounded correction grace, backoff, no idle
  polling, cancellation and catch-up after a slow response.
- Context/contract tests cover keep acknowledgements, bounded long Chinese input, source replacement,
  deletion, stale snapshots and malformed output.
- App-hosted loop tests drive Start/Stop with synthetic recorder events, including Auto off, corrections,
  slow providers, deadlines, duplicate prevention, separate Deep work and saved-output recovery.
- Native UI tests drive Start → accumulate → decision → repetition → revision → suggested review →
  Generate → Stop → History, plus cancellation, partial speech and visible failure/retry. The fixture
  substitutes only speech and model transport and is excluded from device Release builds.
- Credential-gated live tests use the real Cloud client with synthetic speech. They do not establish
  microphone recognition quality or physical-device latency.
- `scripts/benchmark-quick-summary.py` compares API-listed latest Flash variants with fixed synthetic
  scenarios; the optional compiled `benchmark-quick-apple.swift` runner evaluates the same contract on
  the current Mac. Mac measurements are not iPhone performance measurements.
