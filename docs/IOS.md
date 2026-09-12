# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`, version 1.3.1 (8).

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

Summaries render headings, bullets, bold, italics and inline code, including streamed responses. Fenced code remains monospaced. Saved conversations and Markdown exports keep the original output.

## Conversation actions

History shows a trash button for each conversation and supports swipe-to-delete. Deletion asks for
confirmation and removes that conversation's transcript, notes, original attachments and all three AI outputs. Deleting
an active conversation creates an empty active snapshot so the deleted content does not reappear
on restart. Other conversations are preserved.

The **Live** tab shows the transcript above a full-width **Quick Summary**. **Deep Think** has its own tab with room for longer analysis. Landscape and accessibility text use a scrollable page. Start/Stop remains available in either tab. **More → Full summary** also offers **Summary**, **Quick Summary** (up to five concise bullets) and **Deep Think**
(a deeper analysis of decisions, tradeoffs, risks and unresolved questions). Each result is stored
separately, restored with its conversation and included when sharing. These are distinct prompts;
Deep Think does not promise a provider-specific reasoning mode. Requests use the selected provider
and preserve previous completed output on failure or cancellation.

## Photos, files and Apple Notes

Open **Notes** from the main toolbar. Take a photo, choose an image from Photo library, or use
**Add files** to copy a document into the current conversation. Each conversation supports up to
20 attachments, each nonempty and no larger than 20 MB. Tap a filename to preview it; its menu
shares the original, removes it, or copies selectable text into Notes. Text extraction supports
PDF, UTF-8 TXT, Markdown, CSV and JSON; scanned images need OCR elsewhere. Summaries receive only
notes and transcript text, never the original photo/file. The main Share action exports Markdown
and attachment names; use **Share original** to export an attachment's bytes.

For Apple Notes, choose **Share → Send Copy → ListenToMe → Import**, then return to ListenToMe.
This creates a new local conversation while preserving the current one. The share extension also
accepts compatible text, images and files from other apps. It queues imports in the signed App Group
`group.com.tomwu.ListenToMe.ios`; repeated delivery of the same batch does not duplicate conversations.
It does not browse or synchronize your Apple Notes library. Paste text or add an exported PDF if a
source app does not offer a compatible share representation. Apple Notes rich formatting may be
flattened; verify that any scans or embedded documents you need were included.

## Ollama Cloud

Open **More → Settings → Summary provider → Ollama Cloud**. Enter your key and tap **Save API key**,
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
Ollama; microphone audio continues to be transcribed on-device. Quick Summary has an opt-in **Auto** toggle (off initially; your choice is remembered across launches). While listening, it checks every 30 seconds and generates a new Quick Summary if the source changed and contains at least 80 characters. Enabling Auto with Ollama selected sends those snapshots to Ollama. Deep Think stays on-demand. Existing output remains visible while the next response streams; failures keep the last completed result.
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

Follow [the TestFlight release runbook](IOS-RELEASING.md) for exact archive, export, upload, account-recovery and tester-verification steps. A connected device is not required to upload an authorized beta; physical-device acceptance remains a separate production-readiness gate.

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
7. Camera permission denial/retry, photo capture, photo library, Files and Apple Notes Send Copy imports. Preview, share originals, extract document text, remove attachments and delete/reopen conversations.
8. Portrait/landscape iPhone and iPad layouts, large text and VoiceOver controls.

iOS distribution uses an Xcode archive/export and App Store Connect/TestFlight, not a DMG or macOS
notarization. A Mac Developer ID certificate cannot distribute an iPhone app. TestFlight needs an
App Store Connect app record and matching iOS distribution provisioning. A development IPA only
installs on devices in its provisioning profile; a simulator `.app` is not an iPhone installation.
Keep iOS tags (`ios-v…`) separate and never overwrite the latest macOS GitHub release with an iOS
preview. Publish a production iOS release only after device validation and successful distribution.
If provisioning or upload authentication fails, preserve the archive and report the exact error. Missing physical-device acceptance blocks a production-ready claim, not an authorized TestFlight beta upload.

Apple references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
[Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[ReplayKit](https://developer.apple.com/documentation/replaykit).
