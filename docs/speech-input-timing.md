# Mac live SpeechAnalyzer input timing (#333, unreleased)

Installed sandbox acceptance on October 27 reproduced a real SpeechAnalyzer failure while both
audio channels were active: **Audio input timestamp overlaps or precedes prior audio input**.
No synthetic audio had been played. Stop returned both channels to Stopped. This is separate from
the Store package's direct-launch provisioning failure and does not establish a permission problem.

The previous adapter stamped every converted PCM buffer with its raw host capture time rounded to
microseconds. That time could precede the previous converted buffer's end. Scalar capture-timeline
tests did not exercise this native `AnalyzerInput` boundary.

## Corrected boundary

Each pipeline owns its converter and two clocks. The raw boundary is the preceding capture start
plus its original sample count/rate; it detects local discontinuities without confusing accumulated
host/sample-clock drift with a rewind. The converted boundary is exact `CMTime` from the actual
output frame count and negotiated sample rate.

The first capture offset anchors the analyzer. Later buffers follow the converted end, with real
raw-clock gaps carried onto that sample timeline. Local overlap tolerance is at most one millisecond,
capped at a quarter of the shorter adjacent original buffer. Duplicate/grossly backward input fails
with restart guidance before conversion. Every accepted converted frame stays in order. This is
sample-continuous, capture-anchored timing with gap preservation, **not a zero host-clock-drift claim**.
Original capture timestamps, saved-audio writes and recognized result-range forwarding are unchanged.

Invalid timestamps/rates, empty input and incompatible current-runtime formats do not enqueue invalid
framework inputs. Valid sub-frame inputs can produce zero output; they advance the consumed raw boundary and retain
the pending sample anchor without enqueuing an empty framework buffer. When a real gap precedes
the first complete output frame, that pending anchor advances by the gap once. This quantizes
sub-frame carry to the output frame boundary: an incomplete pre-gap contribution belongs to the
first post-gap output. It does not preserve that contribution's original sub-frame position. The
two-frame 48 kHz regression checks a one-16 kHz-frame bound; no universal format bound is claimed.
Output scheduling commits when the native stream accepts the buffer. Stop,
terminated output and a failed conversion discard the converter; cancellation during conversion also
discards its advanced state. Cancellation before work remains a no-op. A new pipeline starts fresh.
The signed-16-bit constructor guard applies to macOS 27; older runtimes retain their negotiated format.

## Evidence and limits

`MACAUDIO-001` binds nine native methods in `MacAnalyzerInputTests` to the production converter,
actual `AnalyzerInput` objects and actual native stream delivery. Cases cover awkward 44.1/48 → 16 kHz
resampling, four 2,000-buffer sequences with ±200 ppm drift, a later 0.75-second gap, exact frame
accounting/source order, independent sources, first offsets, invalid/duplicate/backward input,
cancellation before/during conversion, stop, termination, a fresh pipeline and backpressure.

The valid Int16 native regression failed eleven nonoverlap assertions before the timing fix.
A new tiny-input regression then failed with conversionFailed: native resampling consumed valid
input but emitted zero frames. It now retains that converter state until a complete frame exists.
The tiny-input gap case is additional coverage, not a claimed historical red. Restoring
the earlier post-conversion cancellation guard separately reproduced two failures: a reused converter
and late queued input. The initial Float32 fixture hit macOS 27's constructor precondition; later
iterator-isolation compilation and temporary-buffer pointer-lifetime failures were test-harness defects.
All are preserved separately and are not relabeled as timestamp-regression reds.

Local evidence is under
`/Users/tomwu/Documents/Codex/2026-10-27/listentome-mac318-acceptance/`.
Native buffer tests do not run recognition or establish physical recording quality. Fresh full local
validation, corrected installed microphone/OTHERS acceptance and production-distributed installation
remain separate gates; no new upload or public availability is established by this record.

## Prepared-channel finalization (#335, unreleased)

The next installed sandbox import exposed a separate lifecycle defect: a 12.47-second synthetic
file stayed at Finalizing transcript, then Stopping after Cancel, with Start/New disabled. Imports
prepare two native speech channels but feed only the selected source. Normal finalization of the
unused channel can leave its result stream open.

The transcriber now records actual successful native input delivery, closes all input streams
before awaiting any channel, cancels unused analyzers and result consumers, and finalizes/drains
channels with audio. Cancellation covers both finalization and the result drain. A pipeline created
after Stop is also cancelled before accepting audio. No timeout is treated as successful completion.

`MACAUDIO-002` binds actual native analyzer tests for empty prepared channels, single-source silence,
cancelled preparation and authored speech imported as both sources. The first three methods failed
four completion deadlines on the unchanged implementation; the real speech case failed two deadlines
and one final-word assertion. After the fix all four methods passed, including the recording's
first/final words, selected source and final audio time. The fixture and its provenance are checked
in under `macOSTests/Fixtures/Imports`. Installed Start/New recovery, full validation and merge remain
separate gates. Evidence is in the same external acceptance directory under `speech-fixed/import-*`.
