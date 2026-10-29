# Saved-audio converter tail retention (#348)

Status: implemented candidate with focused native regression checks; not merged or released.
Full validation and hosted CI for the changed source remain pending. No version or published
1.20.2 (42) bundled notes are changed by this fix.

The shared file feed used by saved-audio re-transcription and Watch audio imports released its
AVAudioConverter at source-file EOF without signaling permanent EOF and draining retained output.
A generated mono 16 kHz, signed 16-bit WAV contained 500,900 frames. Direct AVAudioFile reads returned
all 500,900; the old converted feed returned 500,096, losing 804 frames including its distinctive
final samples. This is PCM delivery evidence, not a measured recognition or speaker-quality result.

The initial Float32-on-disk fixture passed all four Mac tests on unchanged production code. That
attempt is a baseline pass, despite its historical `mac-red` folder name. The faithful Int16-on-disk
case then failed one conservation method with 65 assertions (frame count plus all 64 final samples),
while the other three methods passed. The exact same four methods passed after the production fix.
No earlier pass was relabeled as red.

The feed now retains its converter until terminal endOfStream, supplies permanent EOF, emits
positive tail buffers through the existing timeline accounting and then advances to the next file.
Conversion errors and non-progress fail explicitly. It keeps the same-format bypass, converter
priming defaults and Stop locking; it adds no padding, trimming, model or provider change.

Supplemental coverage then exercised Int16 and Float32 on-disk timeline/Stop cases and an exact-sample
Float32 same-format bypass. All four methods passed on native Mac and all four on the iOS simulator.
These are supplemental passes, not newly claimed historical regressions. The four AUDIOFEED contracts
bind `AudioChunkFeedTests` and `MacAudioChunkFeedTests` to a shared generated-PCM assertion helper:

- AUDIOFEED-001: exact frame count, distinctive tail, stable EOF and unchanged source bytes.
- AUDIOFEED-002: tail delivery before the next chunk, one anchor per chunk, overlap clamp and real gaps.
- AUDIOFEED-003: Stop with observable final audio still undelivered, no later output, unchanged source
  and first-error retention. This does not interrupt a converter call mid-execution.
- AUDIOFEED-004: empty input and missing/invalid files, explicit failure without advancing past bad audio.

The existing iOS `MobileFileTranscriberTests/testFeedNeverStepsTimeBackward` AAC timing test also
passed (one test, zero failures). This is a separate baseline compatibility check.

[Independent source-bound focused audit](releases/audio-file-feed-tail-focused-validation.json)
records all five PCM runs and their raw-evidence hashes.

The new fixtures use generated local PCM and never invoke SpeechAnalyzer, a speech/model download,
microphone, playback or external provider. These results do not establish resampling behavior for
all formats, physical device acceptance, real speech recognition, or actual Mac OTHERS acceptance.
The original #236 vocabulary experiment and its failure evidence remain separate; fixing this feed
does not complete vocabulary biasing acceptance.

At the next authorized train, copy the affected user-facing notes from the en-US
[audio-tail draft](../metadata/ios/en-US/whats-new-audio-tail-unreleased.txt) into the selected version's
metadata and bundled release notes. Existing published binaries and notes remain unchanged.
