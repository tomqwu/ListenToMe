# iOS simulator correction — 2026-09-11

Candidate 1.0.1 (2). This corrects unsupported-environment reporting; it does not add simulator speech support.

## Investigation

The previous UI tests covered denial and persistence, not successful transcription. A positive
Start/Stop test failed on iPhone 17 Pro / iOS 26.5. SpeechTranscriber.isAvailable was false.
A legacy SFSpeechRecognizer experiment reported local en-US support but stopped immediately:
`Failed to initialize recognizer`. The system speech-service log confirmed its installed asset
could not open `mini.json`. The experiment was removed. No speech was successfully recognized.

## Change

Start listening now explains the simulator limitation before asking for microphone permission.
It stays idle and does not direct users to Privacy settings. Errors wrap fully and Start dismisses
the editing keyboard. Failed startup does not initialize an audio engine merely to stop it.
The device audio tap explicitly uses a Sendable callback to avoid inheriting main-actor execution.

## Local validation

- iPhone 17 Pro / iOS 26.5: two UI tests pass for simulator explanation/retry without a permission
  alert and notes/New/History/relaunch persistence. This is not a successful recording test.
- Shared core: 239 tests, two opt-in network tests skipped, zero failures; line coverage 96.74%.
- SwiftLint: zero errors; existing style warnings remain. macOS Debug build passes.
- iOS 1.0.1 (2) simulator build and unsigned device Release archive pass.
- Archive: `dist/ListenToMe-iOS-1.0.1-preview.xcarchive`; local logs in `dist/ios-1.0.1-evidence`.
- `devicectl list devices`: no devices found. No physical-device or TestFlight pass is claimed.
- Native UI inspection tool failed to start its connection during final validation; XCUITest
  exercised the app, but no additional manual screenshot inspection is claimed.

## Acceptance boundary

Simulator tests cannot establish physical-device recording quality, finalization, interruptions,
or microphone routing. A connected physical device and the checklist in docs/IOS.md are required
before production/TestFlight delivery. No production iOS release is claimed.
