# Live speaker identification — #310

The fix described here is published in [iPhone/iPad TestFlight 1.18.1 (36)](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.1-build36).
The earlier 1.18.0 (35) used the offline/clustering pipeline. Current physical-device and original-recording acceptance remain pending. Mac capture and Watch/file
imports retain that pipeline; this change does not claim to improve their model accuracy.

## What failed and why the former tests missed it

The tester reported distinct people all labeled Speaker 1. With the actual old production adapter,
a 20-second synthetic dialogue with two known voices also became one cluster. Its complete
39-second version produced two clusters but assigned two returning turns to the other person.
Changing offline clustering parameters did not fix the brief case. Separate model comparisons also
rejected variants that produced two IDs while still assigning the wrong person to known turns.

Existing simulator tests injected predefined diarizer IDs and silent audio. They proved transcript
alignment, renaming, persistence and cancellation for those supplied IDs. UI fixtures heard no
voices. Neither exercised actual acoustic separation. `SHARED-001` now explicitly says it starts
with already-diarized groups; it cannot establish model accuracy.

## Changed behavior

Live microphone analysis uses FluidAudio 0.15.4's **LS-EEND DIHARD II, 500 ms step** model. It
maintains streaming state within each recording, appends only unseen samples from overlapping
windows, and returns speaker segments relative to the requested window. It does not force a
two-person answer. The model supports ten speaker slots, not a guarantee of ten accurate speakers.

Each model epoch owns an opaque scope. The tracker maps `(scope, slot)` to the recording's speaker
identity and edited name, bypassing the older time/embedding matching heuristics. A lost audio gap
or model reset creates a fresh scope. New recordings never inherit an old person's name merely
because the model reuses a slot number. A later recording in the same conversation continues the
display numbering after the people already in its transcript.

Confirmed model time limits the timeline interval that a pass may replace. Labels beyond delayed
output survive until their own interval is analyzed. Open speech is included through confirmed time;
200 ms onset/offset padding covers low-confidence edges and is clipped to captured/confirmed time.
Stop drains delayed model output once, including when no new audio arrived since the periodic pass.
Repeated final requests are idempotent, and late additional audio cannot reopen a finalized run.

The raw speaker buffer remains bounded by the existing ten-minute policy. The model retains at
most 6,000 probability frames (ten minutes at 10 Hz), without rewinding its absolute clock or
resetting voice identities. The Settings switch permits opt-out while recording; re-enabling waits
until Stop so a fresh run starts with its own capture buffer. Turning identification off releases
its raw buffer immediately and
rejects late results. Ending/backgrounding a run fences queued work; model voice/prediction state
is reset when outstanding inference drains. Cleanup from an old run cannot reset a new one.

Foreground preparation loads both the live model and the separate existing offline import models.
An import cannot start their download or mutate the live stream. A partial preparation failure stays
unavailable until retry; retry reaches both pipelines. No SwiftPM dependency version changed.

## Privacy and model provenance

Audio and inference remain on-device. Preparation downloads public weights from
[FluidInference's model repository](https://huggingface.co/FluidInference/ls-eend-coreml), never
conversation audio/text. Its model card identifies the upstream model/export as MIT-licensed;
the runtime's pinned software notices remain in `App/ThirdPartyNotices.txt`. Models are cached under
`FluidAudio/Models`, excluded from backups. Recurrent state, probabilities and temporary audio stay
in memory for that recording and are never saved as reusable voice profiles. Saved labels/names
remain part of the transcript. Opt-in saved audio has its existing independent retention policy.
See [the privacy policy](ios-privacy.md).

The pinned runtime revision is `b9d43724cbdb5a980e441fd54180964e94d470f7`. The selected downloaded
model and fixture hashes, exact source snapshot and native test logs belong with release evidence.
Cached public assets are reused; a first native quality run may download them. This is distinct
from simulator host tests, which substitute models and must not download them.

## Executable acceptance and its limits

`SPEAKER-001`–`SPEAKER-016` in [the BDD catalog](../Behaviors/speaker-identification.json) bind:

- Real CoreML inference through the actual production iOS factory: brief unequal turns, one voice
  with pauses, a second stock-voice pair, balanced eight-turn dialogue, full unequal-turn dialogue,
  returning voices and edited names.
- Successive overlapping windows, duplicate requests, final flush and padding bounds, rejected late
  audio, gaps/new recordings, old cleanup, preparation cancellation and separate file readiness.
- A recording longer than ten minutes: actual retained probability bounds, monotonic time, each
  known voice's original slot/name after silence, and zero retained history after ending.
- Core identity/authority rules and native iOS Stop/opt-out controls independently of model quality.

Run `make bdd-check`, `make mac-test`, the relevant iOS/Core suites, then `make validate-local`.
Preserve actual red/green evidence. Initial old-model quality runs failed; the expanded streaming
tests additionally caught a finalized-run reset and insufficient brief-turn coverage after long
silence. Independent review found the positive-gap reopening case and strengthened the long-run
assertions to reject exchanged identities. A later control audit caught that the actual Settings
switch was disabled while recording even though the native test could assign its property; a new
rendered UI test reproduced that failure before changing the control. Do not call compilation
failures a model regression.

Synthetic stock voices are repeatable regression fixtures, not universal accuracy certification.
The original private recording has **not** been tested. Physical iPhone/iPad speech alignment,
similar voices, overlapping speech, supported languages, speed, memory and battery remain separate
acceptance. Short/uncertain turns can remain Microphone; one transcript line still receives the
speaker with greatest covered duration once coverage reaches 30%. The model cannot reliably split
two people inside one combined recognition line. Simulator screenshots do not establish voice
accuracy. Record these limits on the beta release and use the
[physical smoke checklist](manual-smoke-test.md#iphoneipad-live-speaker-regression-310).

### Observed group-conversation limitation

An additional 26.53-second synthetic three-person sample (Daniel, Samantha and Karen, with roughly
equal speech time) merges Samantha and Karen into one group under both the earlier offline model
and the selected DIHARD II streaming model. DIHARD III also merges them; Sortformer emits three
IDs but exchanges Samantha's identity partway through. This is a preserved no-go diagnostic, not a
passing three-speaker contract. The balanced two-person sample passes. Ten slots describe model
capacity; reliable three-person separation has not been established. Keep this observed limitation
in What to Test and do not claim the original private recording is fixed without testing it.
