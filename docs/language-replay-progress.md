# Automatic language continuity (#339)

The tester reported a natural change of spoken language, not a picker change. Automatic uses a local
WhisperKit multilingual tiny model; configured chat/summary providers are not polled to identify the
speaker's language. Model/tokenizer and Apple speech assets can download; the detection path does
not upload audio. The picker remains disabled during recording.

The replay regression was reproduced in the actual iOS session with an injected recorder/model:
after switching, an utterance starting before the replay cut continued beyond it. Its partial stayed
hidden, its final stayed staged, and later checks remained gated. The correction displays crossing
partials while preserving finalized originals, then commits the crossing final exactly once and
releases the replay gate. Undo follows the same rule. Existing Stop/Undo and language suites remain
part of validation; injected events do not prove physical SpeechAnalyzer behavior or language accuracy.

Inactive/background scenes suspend auxiliary language preparation/checks and fence old completions
with a separate generation. Capture identity, Undo and the trailing audio buffer survive. Foreground
can retry with recent retained audio if the opening window has expired. Cancellation cannot start a
queued model preparation, trigger another inference after a held preparation, publish a held detection
from an older generation, or replace the native analyzer after its preparatory awaits. A replacement
that has already committed publishes matching language/Undo state synchronously before later context
work can suspend. A cancelled optional check must not stop the existing microphone/transcriber.
Already executing uncooperative native work cannot be forcibly terminated; its late results are fenced.
Undo also owns a separate request/task. Context and native preparation completed after inactivity,
Stop or New cannot replace the recognizer, pin a different conversation or publish a stale error.
Once native Undo commits, the locale and fixed-language choice commit in that same actor turn;
a later context await has no additional pin/restore effect. Stop preserves an Undo already requested
by the user and applies it after final words drain; inactivity cancels uncommitted Undo without
applying it. The explicit stopping-time Undo action also remains queueable. Native cancellation checks run before
starting a replacement analyzer and again before replacing the current one.

A replay with no usable recognition progress no longer permanently gates Automatic. After 30 seconds
of accepted audio activity since its last advancing result, one same-locale restart continues at live
audio without replaying the stalled span. Thirty seconds matches the existing maximum identification
window; it is a recovery budget, not a changed language confidence/cadence threshold. The cheap
activity detector is not ground-truth speech classification: sustained music/noise can count. Silence
never triggers recovery, advancing result times reset the budget, and there is one attempt per replay.
The native restart cancels/fences the superseded analyzer generation while the microphone and its
timeline continue. Available finalized replay text merges conservatively; uncovered originals and the
saved-audio choice survive. The notice truthfully says some speech may be missing. If restart fails,
originals and capture remain, stale replay text is filtered, later language checks are allowed, and a
warning recommends Stop/Listen if output does not resume. There is no blind restart loop. Stop,
background suspension, a newer replay or recognition catching up cancels a pending restart. Undo is
not offered during an in-flight native replacement and is available again once it settles. This does
not impose timeouts on every model load or claim native recovery can repair arbitrary audio/model errors.

The existing 120-second audio retention limit (plus at most one 10-second storage block), 60-second
recheck cadence, 20-second confirmation, 90-second minimum dwell, confidence threshold and four-switch
cap remain unchanged. Language detection pauses while inactive/background; the current single-language
Apple recognizer can continue in its existing locale. This is not seamless background bilingual
transcription or proof of fast mixed-language movie accuracy.

Evidence lives outside the repository at
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-language-continuity341/` (the folder label predates
assignment of issue #339):

- `replay-red`: native exit 65, three methods, eight assertion failures across the two crossing/Undo
  methods; the no-result Stop/preservation method was an already-passing baseline, not a claimed red.
- `replay-green`: native exit 0/reaped, all 45 selected language methods passed before background fencing.
- `inactive-red`: held preparation completed after inactive and incorrectly detected/switched (two failures).
- `retained-window-red`: a long suspension requested expired opening audio rather than recent speech
  (one failure).
- `queued-preparation-red`: a cancelled queued preparation still entered model preparation (one failure).
- `language-green2`: invalid combined attempt, a neighboring test's optional-Bool assertion did not compile;
  it supplies no product regression evidence.
- `language-green3`: exit 0/reaped, all 50 selected language methods passed, including inactive/foreground,
  long-retention, held detection and stale-error coverage.
- `recovery-red`: three native methods, nine assertion failures: no bounded restart, warning or release
  of future checks. Silence/progress and preservation assertions also run in those methods.
- `undo-red`: four native methods, ten assertion failures: late context/native-preparation Undo,
  stale Stop/New error pinning, and native post-commit metadata/pinning did not respect lifecycle.
- `recovery-green`: exit 0/reaped in 48.60s, all 55 selected native language methods passed (13 new
  methods plus 42baselines), with all recorded language/recorder input hashes unchanged. Includes
  held recovery cancelled by Stop or advancing recognition; those are added coverage, not claimed reds.
- `stop-undo-red`: one native method, two failures: held Undo prevented a stopping-time Undo from
  being queued/applied while finalization waited.
- `undo-green`: 60 methods completed with two failures in the existing
  `MobileLanguageUndoTests/testAnUndoCancelledByStopIsAppliedAfterStop`. This implementation
  regression caught loss of the already-requested Undo intent; it is not a historical product red.
- `undo-green2`: exit 0/reaped in 32.26s, all 60 native methods passed (18 new plus 42baselines),
  including the unchanged Undo-on-Stop guarantee. All 249 recorded iOS/shared/test/project hashes
  matched, including the generated 1.20.1(41) project. Five Undo lifecycle methods moved unchanged to
  `MobileLanguageUndoContinuityTests` to satisfy lint; the stale Stop/New assertion checks that a
  fresh conversation's explicit language choice survives, while honoring the queued Undo on Stop.
- `bdd-undo-final.log` and `lint-undo-final2.log`: both commands exited 0; BDD 147 passed. All 13
  available result bundles were copied outside the checkout under `native-results/`;
  `native-results.json` and `language-evidence-summary.json` retain provenance.

Initial native runs use device `B5291F6B-B0B7-4A53-A8B2-3BC75536140B`; Undo follow-ups use
`F2C51D15-D112-4385-83FA-5161B21BAFC7`. Their shared command is `xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS
-configuration Debug -destination 'platform=iOS Simulator,id=<the owned device listed above>'
-derivedDataPath .build/language-replay-tests -onlyUsePackageVersionsFromResolvedFile
CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO
-collect-test-diagnostics never` with `-only-testing:ListenToMeIOSUnitTests/` selectors recorded in its
log and an owned bounded supervisor receipt. Final combined validation and physical continuous
bilingual capture, background/foreground, Stop and Undo acceptance remain required before completion.
