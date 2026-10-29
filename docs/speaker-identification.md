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
rejects late results. Ending a run fences queued work; model voice/prediction state
is reset when outstanding inference drains. Cleanup from an old run cannot reset a new one.

## Screen lock continuity (#339)

[TestFlight 1.20.1 (41)](releases/ios-1.20.1-build41.json) keeps the established microphone recording and speaker run
through screen lock/background. It pauses optional speaker preparation/passes and fences old
completions without resetting speaker identities. Active return may continue labeling from the
bounded last ten minutes; earlier background lines can remain Microphone. This does not promise to
relabel an entire long background interval or establish voice quality, battery use or native speech
continuity on physical devices. These changes are separate from the older published speaker fixes.

Save audio recordings remains opt-in; this rolling memory buffer creates no hidden saved recording
and changes no file protection. See [recording continuity and pending device acceptance](recording-continuity.md)
and [language replay/recovery](language-replay-progress.md).

Foreground preparation loads both the live model and the separate existing offline import models.
An import cannot start their download or mutate the live stream. A partial preparation failure stays
unavailable until retry; retry reaches both pipelines. No SwiftPM dependency version changed.

## Renaming from the transcript

On iPhone/iPad, long-press an identified transcript line and choose **Rename speaker**.
This works in the compact reader, expanded transcript and Duo. On Mac, double-click the
speaker label or use the row's **Rename speaker** context menu. The editor has explicit Save
and Cancel actions; blank names and device labels cannot replace a participant. Names are
normalized to one line and limited to 80 characters, matching the existing Notes editor.

Save changes every line carrying that identity in the current conversation. Other identities
remain separate, even if they have the same display name. This names an already identified
speaker; it does not split an incorrectly merged voice or create a reusable voice profile.
Unidentified Microphone/Apple Watch lines have no rename action. Existing Notes/Speakers
editing remains available. The BDD shortcuts are `SPEAKER-017` and `SPEAKER-018` in
[the rename contract](../Behaviors/speaker-renaming.json); installed Mac sheet/save and
VoiceOver acceptance are separate from native callback tests. `SPEAKER-019` additionally checks
cold fixture readiness and true Duo before renaming. The current integrated fixture has two-method
red→green and a six-method related simulator pass, tied to base `6705543` plus retained dirty inputs;
[the bounded receipt](releases/speaker-rename-6705543-readiness.json) records exact hashes and limits.
This does not prove real speaker inference, disk persistence across relaunch or installed Mac use.

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
