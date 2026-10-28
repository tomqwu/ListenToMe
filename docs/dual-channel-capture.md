# Mac dual-channel echo and chronological transcript (#336)

The October 27 installed check reproduced the same synthetic Orion speech under both YOU and
OTHERS and delayed final results displayed out of timestamp order. Seeing OTHERS alone was not a
complete dual-channel acceptance: microphone pickup of playback was also present. YOU and OTHERS
identify capture channels, not individual people. Speaker diarization is a separate operation.

## Candidate behavior

Microphone capture enables native AVAudioEngine voice processing before reading the tap format.
Bypass and automatic gain are off; other-audio ducking is minimized. The app never plays captured
system audio back as a reference and never deletes lines by matching transcript text. A route that
cannot establish the required profile fails with recovery guidance rather than starting raw input.
This is local audio processing; the existing provider and audio-retention choices remain in force.

Engine work is serialized. Route, format and profile checks distinguish healthy configuration
notifications from real input changes. A real second failure within the recovery cooldown tears
down unsafe input and schedules one delayed retry. Stop is terminal, including during engine
startup and before a delayed retry. Tests with injected drivers prove lifecycle decisions; they do
not measure acoustic attenuation or prove every native route is compatible.

Each new Mac capture/import has an explicit recording ID. Display and readable exports order
valid timed lines stably within that run; unknown or untimed boundaries remain intact. Canonical
arrival order, segment IDs, timestamps, capture/summary ledgers and JSON segment order remain
unchanged. Editing, shifting, prompt shortening and iOS correction/undo preserve the run ID.
Known-run duration is the sum of each run's span, excluding gaps between runs. Legacy records
without IDs retain their existing timestamp-regression grouping and display order; the app does
not guess historical run boundaries or silently repair old duplicates.

## BDD and observed evidence

`MACAUDIO-003` covers chronological presentation, persistent identity, canonical storage, duration,
exports, edits and metadata preservation. `MACAUDIO-004` covers microphone setup, cleanup, recovery
and terminal Stop through the production controller and injected engine driver.

Evidence is retained locally in
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-dual-channel336/`:

- Ordering red2: five tests, 13 assertion failures. Focused green3: 74 tests, zero failures.
- Prompt-shortening metadata red: one test, four failures, then green.
- Duration red2: known-run regressions reproduced, then green. The initial duration test used an
  incorrect JSON key; that assertion is a harness error, not product evidence.
- Echo lifecycle red2: four tests, 19 failures. Cooldown red2: six tests, four failures.
  Echo green3: six tests, zero failures, including Stop during a blocked engine start.
- iOS correction/snapshot metadata: one test, three failures; green: ten tests, zero failures.
  The failed test completed its assertions but Xcode hung during result handling; the stale runner
  was terminated. The independently completed green run has an actual TEST SUCCEEDED result.
- Initial native green attempts hit ObjCBool and throwing-closure compiler errors. These are build
  repairs, not regression reds. Post-implementation race tests are additional coverage, not a
  claim of historical red evidence.

The signed sandboxed candidate (binary SHA-256
`e9d59d6e56a4301387d1c80228f23c7f099352ee0f8a0fda2ce544cd7a842d53`) captured all five Orion sentences
as OTHERS, with zero YOU finals, through the Studio Display XDR speakers and microphone. Both
channels were active before playback; Stop returned to Ready. This is a playback-only regression
pass on one route. It does not establish independent near-end voice, simultaneous voices, headphone
or physical route-change quality. Screenshots are local QA evidence, not store media; the transcript
also contains unrelated pre-playback system speech.

Independent static review cleared the ordering and recovery corrections. Full final validation,
rendered delayed-channel edit/playback checks, remaining physical audio acceptance, CI and merge
are separate pending gates. No new release or production submission is established by this work.
