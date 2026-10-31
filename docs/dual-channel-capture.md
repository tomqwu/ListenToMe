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

Independent static review cleared the ordering and recovery corrections. Full automated validation
passed on `95aaeaf` (exit 0, 929 unchanged tracked inputs), and all three hosted checks passed on
that source. [The audited receipt](releases/mac-candidate-95aaeaf-validation.json) records counts and
limits. Rendered delayed-channel edit/playback, remaining physical audio acceptance and merge
remain pending gates. No new release or production submission is established by this work.

The first full `086d89e` aggregate failed in an unrelated largest-text translation UI scrolling
harness after Core/iOS execution; Mac/Watch/server stages did not run. The separately reproduced
and corrected [test-harness visibility issue](translation-validation.md) does not change audio
implementation or supply any outstanding physical audio acceptance. The complete `95aaeaf` rerun
passed, including all four translation UI methods; the earlier failure remains preserved.

A later route attempt remained at Starting with idle channels; no fixture was played. Stop returned
Ready. The app reported microphone and speech access Not set after prior Dev cleanup, but the
startup cause was not established. The completed Dev app was closed and moved to Trash and only
its `.dev` permissions reset. Provider/engine/speaker preferences were restored; the former listener
model was absent from the Cloud picker after refresh and could not be restored through the UI.
That Dev-setting exception is recorded in the external `route-acceptance/cleanup.json`; user history,
API keys and production permissions were preserved. This attempt is not an audio acceptance pass.

The later `02528bf` signed sandbox session accepted the corrected transcript gestures, selection,
Save/Cancel and narrow/wide reflow on an existing synthetic conversation. It started neither capture
nor playback. [The bounded installed receipt](releases/mac-candidate-02528bf-installed.json) therefore
does not close independent near-end, overlap/repeated speech, headphones/physical routes, Stop during
recovery or delayed-row audio playback. Its full integrated validation failed in a separate Settings
UI test; [the recovery record](validation-pipeline-recovery.md) preserves that outcome and the make
failure-propagation correction. Earlier acoustic evidence is not promoted to the new source.

## Local saved-audio ordering follow-up — October 30, 2026

History's separate **Play from a line** list still enumerated canonical arrival order. The local
`d36b212c8288cbca26c03c721a7b54686699641e` follow-up uses the existing recording-aware projection
while retaining each original array index for playback. Stable ties, explicit recording blocks,
untimed boundaries and legacy arrival order keep the same policy. Restored duplicate segment IDs
remain distinct rows with their original audio parts and offsets. Saved transcripts, audio files
and retention choices do not change. iOS playback lookup is outside this Mac change. Its normal
phone/Watch recordings do not use the index-anchored manifests affected here; a separate iOS
duplicate-ID playback failure has not been established.

`AUDIOVIEW-002` binds three `MacSavedAudioOrderTests` methods. They host the actual production
section with an isolated library and generated silent audio, expand its native disclosure, read
the actual rendered row positions, click the rows, verify the real playback source/offset, and
verify Stop on leaving plus unchanged archive/manifest/audio bytes. The injected owner avoids
the shared settings/retention initializer. These are component checks, not installed-app or acoustic
acceptance.

- The first native attempt on `5fef840` failed on directory-URL equality and a title-center click
  that did not expand the disclosure. It is preserved as a harness failure, not a product red.
- Corrected test-only source `eec9a112` produced genuine red: two methods failed six ordering
  assertions; the untimed/legacy control passed. Native images showed `0:20` before `0:17`,
  `0:48` before `0:43`, and restored second-run `0:06` before `0:03`. Other source/offset,
  actual-click, Stop and byte-preservation assertions completed without failure.
- Applying the reviewed two-file fix gave **three native passes, zero failures/skips** on
  `d36b212`. The tests, fixtures and assertions were byte-identical to red. Original-resolution
  green images show stable `0:17, 0:17, 0:20` and separate `0:43, 0:48` rows; duplicate-ID rows
  retain the correct recording boundaries. The untimed/legacy control image is byte-identical.
- Sixteen existing Core suites passed **145 tests, zero failures/skips**: presentation/cache,
  recording timelines/timestamps, readable/JSON/golden exports, vault output, summary/selection
  paths and saved-audio seeks. `make bdd-check BDD_BASE=9a39a12f230b353fe400a2b17dc41f95a023497c`
  validated 248 scenarios; scoped strict SwiftLint and `git diff --check` passed.

Evidence is preserved under
`/Users/tomwu/Documents/Codex/2026-10-30/listentome-mac336-saved-audio-order/` in
`native-red-stacked-candidate`, `native-red-stacked-retry1` and `native-green-stacked`.
Each native command selects only the three bound methods of `ListenToMeMacUnitTests/MacSavedAudioOrderTests`
on `platform=macOS`; exact argument arrays are in `execution/command.json`. The Core command and
16-suite filter are in `native-green-stacked/core-execution/command.json`. Both green commands
ended exit 0/reaped within their 600-second bounds. All 1,083 frozen inputs and recorded Xcode/SDK
metadata stayed unchanged. Original result bundles, logs, unmodified PNGs, test binaries and
generated inputs are retained. The green receipt SHA-256 is
`35282f484a3d47af5b4ce3810dd9f044544c4188adf453567d9ff8243fe9c4c0`.

The focused results above used the earlier #334 candidate `9a39a12`. This branch now integrates
merged Watch main `0177431`; all four saved-audio runtime/test/catalog files remain byte-identical
to focused candidate `bf0f2ae`. The integration passed 255 BDD scenarios and diff checks;
combined full validation and PR/merge are next. No integrated native pass
is claimed yet. Source-matched installed History playback and a fresh
full-app README screenshot remain pending while the Mac is locked; the native component images
are QA evidence only. Independent near-end speech, overlap, genuinely repeated speech, headphones
and physical route recovery remain separate #336 acceptance gates. This slice does not close #336.
