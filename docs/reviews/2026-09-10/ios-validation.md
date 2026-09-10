# Initial iOS app validation — 2026-09-10

Version 1.0.0 (1), bundle `com.tomwu.ListenToMe.ios`. This is an initial implementation,
not a production/TestFlight release and not a claim of feature parity with macOS.

Verified locally:

- iOS simulator app compiles against the locked dependencies.
- iPhone 17 Pro / iOS 26.5: microphone denial returns to idle, retry does not reprompt or claim
  recording; notes survive Save, New, History and restart; an empty New remains empty on restart;
  version information exists in Settings. Two XCUITests passed.
- iPad Pro 11-inch (M5) / iOS 26.5: save/history/relaunch and Settings UI test passed.
- iPhone interface and Settings were inspected in Simulator.
- Core suite: 239 tests, two opt-in network tests skipped, no failures; line coverage 96.74%.
- SwiftLint: no errors (repository style warnings remain).
- The macOS Debug app still compiles with signing disabled.
- Device Release archive compiles with signing disabled. The icon is an opaque 1024px iOS asset.

Distribution blockers and remaining acceptance:

- No physical device is connected. Real speech/model installation, finalization, background/call/
  Bluetooth handling and Apple Intelligence generation still require the device checklist in
  [IOS.md](../../IOS.md#validation-and-release).
- Automatic device archiving selected the installed development identity and wildcard provisioning
  profile, then waited at the macOS Keychain authorization prompt. Computer Use cannot operate
  SecurityAgent; the maintainer must complete that system prompt.
- An unsigned archive is preserved under `dist/ListenToMe-iOS-1.0.0-candidate.xcarchive`. It cannot be
  installed on an iPhone. TestFlight upload and App Store Connect provisioning are not verified.
- Build/test logs and xcresult references are retained locally under `dist/ios-1.0.0-evidence` and
  `.build/ios/Logs/Test`. No production iOS artifact has been published.
