# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`, version 1.0.0 (1).

## Included

- Foreground microphone transcription using Apple's on-device SpeechAnalyzer. Language assets
  download on first use. Unsupported device/language and permission errors are shown in the app.
- Partial and final transcript text. Everyone picked up by the microphone is labeled **Microphone**;
  this version does not infer who is speaking. Unfinalized text is retained and labeled accordingly.
- Editable titles and notes; atomic local saves after finalized utterances/notes, explicit Save,
  save-before-New, local History, restoration on launch and Markdown through the share sheet.
- Optional Apple Intelligence summaries with availability checks and surfaced generation failures.
  Inputs above 8,000 characters are rejected explicitly, not silently truncated. AI output needs review.
- Recording stops/saves on backgrounding, audio interruption or microphone disconnection. The screen
  stays awake during active recording. No raw audio is saved.
- Version/build information in Settings.

System/call audio, background recording, Mac sync, calendar import, audio-file import, WhisperKit,
per-person speaker identification and Ollama/cloud routing are not included. Notes and saved
transcripts remain usable when the speech model or Apple Intelligence is unavailable.
App data is local to the sandbox; normal OS backup policy applies. Sharing explicitly exports text.

## Build and run

Use Xcode 26+, XcodeGen and an installed iOS 26 simulator runtime:

```sh
make ios-build
make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

Open `ListenToMe.xcodeproj`, choose **ListenToMeIOS**, then a simulator or connected iPhone/iPad.
For a physical device, trust the Mac, enable Developer Mode and select your development team under
Signing & Capabilities if building with a different account. `make ios-archive` creates a signed
Release archive with automatic provisioning using the configured team.

The shared Swift package supports iOS 18+ for reuse; the actual app requires iOS 26 for SpeechAnalyzer
and Foundation Models. iOS does not depend on the Mac WhisperKit or FluidAudio binaries.

## Validation and release

Run lint, shared core tests/coverage, the iOS build and UI tests, and a macOS build to protect the
existing product. The UI tests verify microphone denial/retry, saving notes, New, History and restoration across app restart.
Hosted CI builds both apps. Before marking iOS production-ready, test on a physical iPhone/iPad:

1. First-use microphone denial, retry after granting, and unsupported language/model errors.
2. Model installation, then at least two minutes of real speech with live/final transcript text.
3. Stop finalizes the last phrase; interrupted/unfinalized text remains visible after save/relaunch.
4. Background, incoming call, Bluetooth disconnection, and repeated Start/Stop do not leave the mic active.
5. New preserves the old conversation; History and sharing include notes, transcript and summary.
6. On an Apple Intelligence eligible device, generate a factual summary and verify unavailable,
   oversized-input and failure states keep the transcript and previous summary.
7. Portrait/landscape iPhone and iPad layouts, large text and VoiceOver controls.

iOS distribution uses an Xcode archive/export and App Store Connect/TestFlight, not a DMG or macOS
notarization. A Mac Developer ID certificate cannot distribute an iPhone app. TestFlight needs an
App Store Connect app record and matching iOS distribution provisioning. A development IPA only
installs on devices in its provisioning profile; a simulator `.app` is not an iPhone installation.
Keep iOS tags (`ios-v…`) separate and never overwrite the latest macOS GitHub release with an iOS
preview. Publish a production iOS release only after device validation and successful distribution.
If provisioning or a connected device blocks that step, preserve the archive and report the blocker.

Apple references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
[Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[ReplayKit](https://developer.apple.com/documentation/replaykit).
