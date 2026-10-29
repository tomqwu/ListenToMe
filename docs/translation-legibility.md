# Translation text legibility (#346, unreleased)

Essential translation explanations, availability/setup status and recovery captions now use the
stronger native primary foreground. Caption sizes, wording, layout, translation state, language-pack
consent, providers and originals are unchanged. This is a local implementation pending full
validation, required CI, review and merge; it is not included in published TestFlight 42.

## Contract and focused evidence

`TRANSLATIONLEGIBILITY-001` checks actual Summary guidance/setup text after native taps;
`002` checks the production status view across eight iOS trait/text conditions; `003` checks that
same status on Mac card/rail surfaces in supported Aqua/Dark Aqua appearances. Actual text rasters,
opaque native backgrounds and resolved environment/RGBA evidence are required. A color-token test
alone cannot satisfy these checks. The 4.5:1 small-text benchmark is a bounded legibility regression
check, not a claim of whole-app accessibility conformance.

The native trait matrices render the initial “Record speech to translate” availability message;
they do not establish every translation state. The UI checks separately exercise Summary guidance,
missing-pack setup, cancellation and late output through the production controls.

Retained evidence is under `listentome-translation346-plan`: each phase keeps its exact
`command.json`, `result.json`, frozen input hashes, native result bundle and attachments. The tested
base was `de2f72b0a4adfdcc301cc90ea74e3df9a777ec94` plus the recorded changes: 1,001 input files for
iOS red/green, 1,002 for the Mac supplement. The corrected iOS red/green differs only in the two
shared production view files; the same two methods and criteria were retained.

| Phase | Observed outcome |
| --- | --- |
| Initial iOS (`ios-red`) | Native unit contrast failed; UI stopped at a scroll-owner harness guard. This is not four contrast failures. |
| Corrected iOS red (`ios-red-corrected-scroll`) | Two methods, four actual contrast assertions failed at 3.438876789:1; exit 65/reaped. |
| Same iOS methods green (`ios-green`) | Two passed; exit 0/reaped, 33.863s. Native light minimum 21:1, dark minimum 16.685807:1; actual Summary guidance/setup crops 21:1. |
| Initial Mac (`mac-supplemental`) | Four appearance-propagation assertions failed; requested high-contrast names still yielded standard SwiftUI contrast. No high-contrast measurement or Mac product red is claimed. |
| Supported Mac (`mac-supported-surfaces`) | One method/four native renders passed; exit 0/reaped, 7.390s. Measured card/rail ratios 12.197–14.938:1. |
| Existing iPhone (`iphone-compatibility`) | Five existing UI methods passed; exit 0/reaped, 137.309s. Portrait/Duo, Summary/originals, cancellation/late reply and setup/largest-text controls. |
| iPad (`ipad-compatibility`) | Three selected UI methods passed; exit 0/reaped, 92.859s. Actual wide workspace, Summary contrast and largest-text original/control access. |

The UI harness was corrected to reveal the whole owning Summary scroll viewport before measuring.
Mac now checks only established native Aqua/Dark Aqua behavior, waits at most 3 seconds in 20 ms
steps for actual environment/bounds, and verifies the caption fits. The failed high-contrast attempt
remains preserved. It did not establish Mac increased-contrast propagation; no user accessibility
preference was changed and no forced environment is presented as native coverage.

After the focused runs, four long diagnostic strings were wrapped without changing their content
or assertions to satisfy lint. Lint then passed (989 warnings, zero errors). Full validation of the
final committed source remains required. All seven raw result bundles are retained externally;
496 files were hashed before deleting only the two owned simulators.

The first combined full run on `dafe4fa` later failed an offscreen speaker-renaming test, before its
editor opened. Its original evidence remains failed. That inspection also found and reproduced a
saved-audio AX5 layout defect, repaired with separate native red/green and final phone/iPad checks.
See [combined validation recovery](saved-audio-accessibility.md); a fresh full pass is still required.

## Reproducing the focused checks

Use a dedicated owned simulator UUID in `SIM`; set `IOS_RESULT` and `MAC_RESULT` to new,
nonexistent owned result-bundle paths and preserve separate logs for each run.
The retained command files contain the exact destinations, output paths and source input hashes.

```sh
xcrun simctl ui "$SIM" appearance light
xcrun xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath .build/ios \
  -onlyUsePackageVersionsFromResolvedFile -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ListenToMeIOSUnitTests/TranslationLegibilityTests/testActualStatusRenderAndNativeEnvironmentContrastMatrix \
  -only-testing:ListenToMeIOSUITests/MobileTranslationUITests/testSummaryGuidanceAndSetupStatusMeetSmallTextContrast \
  -resultBundlePath "$IOS_RESULT" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
xcrun xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeMacTests \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/mac-native-tests \
  -onlyUsePackageVersionsFromResolvedFile -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ListenToMeMacUnitTests/MacLanguageControlsTests/testActualTranslationStatusMeetsContrastOnMacSurfacesAndAppearances \
  -resultBundlePath "$MAC_RESULT" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Run `make bdd-check` and the full local/hosted gates before merge. These focused results do not prove
all-device layouts, VoiceOver, physical-device translation, Mac increased contrast, engine accuracy,
installed-app acceptance or screenshot publication. Physical acceptance is unverified and is separate from authorized visual-beta eligibility. Native
screenshots use synthetic fixtures and are QA evidence, not listing publication. Historical
#343 inference/recovery and published 42 receipts remain separate; see [translation](translation.md)
and [the BDD workflow](BDD.md).
