# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`, version 1.2.0 (5).

## Included

- Foreground microphone transcription using Apple's on-device SpeechAnalyzer. Language assets
  download on first use. Unsupported device/language and permission errors are shown in the app.
- Partial and final transcript text. Everyone picked up by the microphone is labeled **Microphone**;
  this version does not infer who is speaking. Unfinalized text is retained and labeled accordingly.
- Editable titles and notes; atomic local saves after finalized utterances/notes, explicit Save,
  save-before-New, local History, restoration on launch and Markdown through the share sheet.
- Optional Apple Intelligence summaries, or Ollama Cloud summaries with streamed results and secure API-key storage.
  Apple Intelligence accepts up to 8,000 characters; Ollama accepts up to 60,000. Oversized input is rejected explicitly. AI output needs review.
- Recording stops/saves on backgrounding, audio interruption or microphone disconnection. The screen
  stays awake during active recording. No raw audio is saved.
- Version/build information in Settings.

System/call audio, background recording, Mac sync, calendar import, audio-file import, WhisperKit,
per-person speaker identification and local/LAN Ollama server connections are not included. Notes and saved
transcripts remain usable when the speech model or Apple Intelligence is unavailable.
App data is local to the sandbox; normal OS backup policy applies. Sharing explicitly exports text.

Summaries can run while recording: each request uses a snapshot of the notes and transcript at
that moment. Stop listening remains available during generation. A disabled summary action shows
its reason (empty text, model unavailability, microphone transition or an in-flight response).
Check again re-reads readiness. Apple model-not-ready status does not prove a download is active.

## Conversation actions

History shows a trash button for each conversation and supports swipe-to-delete. Deletion asks for
confirmation and removes that conversation's transcript, notes and all three AI outputs. Deleting
an active conversation creates an empty active snapshot so the deleted content does not reappear
on restart. Other conversations are preserved.

The Summary tab offers **Summary**, **Quick Summary** (up to five concise bullets) and **Deep Think**
(a deeper analysis of decisions, tradeoffs, risks and unresolved questions). Each result is stored
separately, restored with its conversation and included when sharing. These are distinct prompts;
Deep Think does not promise a provider-specific reasoning mode. Requests use the selected provider
and preserve previous completed output on failure or cancellation.

## Ollama Cloud

Open **Settings → Summary provider → Ollama Cloud**. Enter your key and tap **Save API key**,
then **Refresh models from API**, select a **Model role**, **Choose model**, and **Test connection**.
Each of the three roles has an independent model selection. When a new key is entered, the test
button becomes **Save key and test connection** and saves that key before sending the request. Keys are stored in
iOS Keychain with `WhenUnlockedThisDeviceOnly`, never in preferences, session exports or the app binary.
Enter the key separately on each device. Remove API key deletes it from this device.

Refresh calls `https://ollama.com/api/tags` with Bearer authentication and preserves exact returned
model IDs. The recent-family section picks the newest API modification time for each advertised
standard/Pro/Flash variant of DeepSeek, GLM, Qwen and Kimi. All API models remain available, including
other families. This is API update recency, not an independently verified release chronology.
No unavailable Flash/Pro name is invented. Refresh preserves your selected model; if it disappears,
choose another. Model refresh does not prove key validity: Test connection verifies a complete streamed
`/api/chat` response using only a synthetic prompt. Cloud models run remotely; `/api/pull` is not needed.

Selecting Ollama is opt-in. Generating any of the three AI outputs sends the current notes and transcript to
Ollama; microphone audio continues to be transcribed on-device. No automatic cloud summary runs.
The last complete summary is preserved on HTTP errors, incomplete streams and cancellation. Streamed
text is shown separately until completion. Backgrounding cancels an active summary request.

## Build and run

Use Xcode 26+, XcodeGen and an installed iOS 26 simulator runtime:

```sh
make ios-build
make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

Open `ListenToMe.xcodeproj`, choose **ListenToMeIOS**, then a simulator or connected iPhone/iPad.
For a physical device, trust the Mac, enable Developer Mode and select your development team under
Signing & Capabilities if building with a different account. For device tests, override
`IOS_SIGN_FLAGS=-allowProvisioningUpdates`; the default test signing is for simulators. `make ios-archive` creates a signed
Release archive with automatic provisioning using the configured team.

**Simulator limitation:** live speech transcription is unavailable in the tested iOS 26.5 simulator.
Start listening explains this before requesting microphone permission. Notes, History and export
remain usable. Granting permission or changing language cannot enable the missing speech engine.
Use a physical iPhone/iPad for recording acceptance. Simulator builds and UI tests do not validate
live speech. The legacy recognizer also failed to load its model despite reporting local support.

The shared Swift package supports iOS 18+ for reuse; the actual app requires iOS 26 for SpeechAnalyzer
and Foundation Models. iOS does not depend on the Mac WhisperKit or FluidAudio binaries.

## Validation and release

Maintain the [iOS listing metadata](../metadata/ios/README.md) alongside release changes. Apply the
Beta App Description and per-build What to Test in App Store Connect, and verify the uploaded app
icon and the installed Home Screen icon. Repository metadata files alone do not update the listing.

Run lint, shared core tests/coverage, the iOS build and UI tests, and a macOS build to protect the
existing product. The simulator UI tests verify the unsupported-speech explanation without a microphone prompt, retry, saving notes, New, History and restoration across app restart.
Hosted CI builds both apps and runs the iOS UI and app-hosted tests. Simulator builds use ad-hoc signing so Keychain tests exercise actual storage. The credential-dependent live cloud test is opt-in and skips on CI. Before marking iOS production-ready, test on a physical iPhone/iPad:

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
