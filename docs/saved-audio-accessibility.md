# Saved-audio reader at accessibility text sizes (unreleased)

The iPhone/iPad player stacks **Saved audio** and **Share audio** at accessibility text sizes,
with Play and the position slider together and elapsed/duration on a separate line. This prevents
split words, truncated sharing text and a wrapped time display in the fixed transcript header.
Standard-size iOS and Mac retain the previous arrangement. Playback, sharing, retained files,
speaker identities and audio-saving consent are unchanged.

`AUDIOVIEW-001` binds the actual expanded reader at standard and AX5 text sizes to native UI tests.
They measure complete phrase/word bounds against native text metrics, single-line time, wholly
visible enabled controls and useful transcript space. The first identified speaker must remain
reachable by scrolling the reader without starting playback. `SPEAKER-017` then performs the actual
long-press/menu/editor journey and checks Cancel/Save above the keyboard and unchanged identity.
An intact accessibility label alone cannot prove that its visible words are not truncated.

## Preserved failure and recovery evidence

Evidence is retained under `listentome-translation346-plan`, with per-phase commands, input hashes,
native result bundles, screenshots and AX hierarchies. These checks began on committed base
`dafe4fa6bc2ee854f57d484e4a72379841aa8ba7` plus the recorded changes. Each new focused phase froze
1,008 inputs; all matched afterward. The unchanged single-method baseline froze 1,007 inputs.

| Phase | Outcome and scope |
| --- | --- |
| `full-validation` on clean `dafe4fa` | Aggregate failed (make 2 / iOS 65). Core and 509 iOS unit tests passed with their optional skips; one of 88 UI tests failed before the rename editor opened because the first label was offscreen. Mac/Watch/server stages were not reached. All 1,002 frozen inputs matched; 1,518 raw iOS result files were copied and byte-verified. This run remains failed. |
| `speaker-largest-unchanged` | Same test passed after XCTest retried implicit scrolling. This is an unchanged flaky baseline, not a product red/green. |
| `saved-audio-layout-red` | AX5 reproduced five real layout assertions. Two standard-size assertions incorrectly treated AX glyph bounds as the padded touch target; the first explicit reveal also failed while dragging the scrollbar strip. Those harness failures remain separate. |
| `saved-audio-layout-corrected-red` | Standard-size and actual rename/editor methods passed. AX5 failed six layout assertions, including full wrapped phrase height. The native result was 65/reaped. |
| `saved-audio-layout-green` | The same three methods passed, exit 0/reaped. Only `SharedPlatform/SavedAudioPlayer.swift` changed between this red and green. Six green native captures and the red were inspected independently. |
| `saved-audio-layout-ipad` | Standard and rename/editor passed; AX5 failed only a test calculation using the whole dimmed app instead of the smaller modal reader surface. Labels, time, controls and exact speaker access passed. This is a preserved metric-harness failure. |
| `saved-audio-layout-ipad-sheet` and `saved-audio-layout-phone-final` | The final test measures player/reader surface bounds, retaining the three-body-line minimum. All three methods passed on each device, exit 0/reaped, with the same frozen 1,008 inputs and unchanged production code. |

The explicit rename reveal captures the original `transcript-speaker-*` identity before scrolling,
uses bounded drags inside the owning reader's content (outside the scroll-indicator strip), and
requires that same label to be wholly visible and hittable before the real gesture. It never selects
a more convenient later speaker or removes editor/keyboard assertions. The production bottom-follow
behavior is unchanged. The initial failed helper is retained rather than relabeled as passing.

The tests deliberately make no 44-point hit-region claim from AX glyph geometry. They also do not
establish physical playback/recording, sharing delivery, VoiceOver, all locales, long durations or
multiple recording parts. Full combined validation, hosted CI, installed acceptance and merge remain
separate gates. These changes are not included in published TestFlight build 42.

## Reproduce

Use a dedicated owned iPhone or iPad simulator UUID in `SIM` and a new result path in `RESULT`:

```sh
xcrun xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath .build/ios \
  -onlyUsePackageVersionsFromResolvedFile -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ListenToMeIOSUITests/MobileSavedAudioUITests/testSavedAudioHeaderAtDefaultTextKeepsTranscriptUsable \
  -only-testing:ListenToMeIOSUITests/MobileSavedAudioUITests/testSavedAudioHeaderAtLargestTextKeepsTranscriptUsable \
  -only-testing:ListenToMeIOSUITests/MobileSpeakerControlsUITests/testRenameEditorActionsAtLargestTextSize \
  -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Inspect the actual images as well as assertions, then run the normal BDD/full-validation gates.
The [translation legibility fix](translation-legibility.md) keeps its own genuine contrast red/green
and release status; this player layout was discovered while validating that combined candidate.
