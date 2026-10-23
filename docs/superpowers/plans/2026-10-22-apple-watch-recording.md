# Apple Watch Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A watchOS companion to ListenToMeIOS that remote-controls the iPhone recorder (Slice 1) and
records on the watch microphone, hands the audio to the iPhone, and turns it into a normal
conversation transcribed on-device (Slices 2–3), for [#181](https://github.com/tomqwu/ListenToMe/issues/181).

**Architecture:** One embedded watchOS application target (`ListenToMeWatch`, no extension target)
that compiles two Foundation-only files from `ListenToMeCore` for its wire protocol and capture
rules. The iPhone side wraps `WCSession` in `PhoneWatchLink`, files incoming chunks synchronously
into a `WatchInbox`, and drains that inbox in the foreground through `MobileFileTranscriber`
(`SpeechAnalyzer` over ordered files) into `SessionArchive`, exactly like a recorded conversation.
Until the release train that ships slices 1–3, the watch app is built on every `make ios-build` but
**embedded in the iOS app only when `WATCH_EMBED=YES`**, so no unrelated iOS train ships it early.

**Tech Stack:** Swift 6, SwiftUI (iOS 26 / watchOS 26), WatchConnectivity, AVFoundation
(`AVAudioEngine`, `AVAudioFile` AAC), Speech (`SpeechAnalyzer`, `SpeechTranscriber`), XcodeGen 2.46,
XCTest (`swift test` for Core, `ListenToMeIOSUnitTests` app-hosted), Python `unittest` for the
TestFlight helper.

**Spec:** [docs/superpowers/specs/2026-10-22-apple-watch-recording-design.md](../specs/2026-10-22-apple-watch-recording-design.md).
Its §3 platform facts (F1–F19, U1–U8) and §9 decisions are referenced by number below.

## Global Constraints

- Watch audio and commands travel **only** over WatchConnectivity to the paired iPhone. The watch
  app makes no network request: no `URLSession`, analytics or crash reporter.
- The iPhone stays foreground-only: `iOS/Info.plist` keeps **no** `UIBackgroundModes`. A watch
  message that wakes the phone app in the background never activates the audio session and never
  starts transcription.
- The phone never starts the watch microphone. Recording starts only from a user action on the
  device that records, with the app in the foreground (F5, F9).
- Watch `UIBackgroundModes: [audio]` on the watch target only (decision 2), added in Slice 3.
- Raw audio is transient: the watch deletes a chunk only after `didFinish` reports success; the
  phone deletes a chunk only after its segments are saved to the archive. No "keep the audio"
  option (decision 3). A failed chunk is never deleted silently.
- Limits (decision 5): no start below 20% battery or 200,000,000 bytes free; stop and save at 10%
  battery; hard cap 3 hours (10,800 s); chunk length 300 s.
- Chunk wire format: AAC-LC, mono, 16 kHz, about 32 kbps, `.m4a`. Metadata
  `{ v: 1, recordingID, index, startOffset, duration, isLast, startedAt, watchBuild }`. The phone
  rejects `index > 999`, `duration <= 0` or `>= 600`, and files over 10,000,000 bytes, and names
  stored files itself as `<recordingID>/<index>.m4a`.
- `WatchLink.protocolVersion = 1`, independent of the build number.
- Bundle ids: app `com.tomwu.ListenToMe.ios`, share `com.tomwu.ListenToMe.ios.share`, watch
  `com.tomwu.ListenToMe.ios.watchkitapp`. `WKCompanionAppBundleIdentifier = com.tomwu.ListenToMe.ios`.
  `WKRunsIndependentlyOfCompanionApp = false`. Team `T32FW7PZ3S`.
- Versions: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are identical across `ListenToMeIOS`,
  `ListenToMeShare` and `ListenToMeWatch`, and every iOS version bump changes all three.
- Deployment target watchOS 26.0 (decision 10). Watch code must compile with the watchOS **26.5**
  SDK that CI's default Xcode 26.6 ships (F16), not only with the local Xcode 27 SDK.
- Watch free-space checks use `volumeAvailableCapacityKey`; `volumeAvailableCapacityForImportantUsage`
  does not exist on watchOS (F18).
- Watch conversations: `sourceImportID = "watch:<recordingID>"`, title
  `"Apple Watch · " + startedAt.formatted(date: .abbreviated, time: .shortened)`, segments
  `source: .you`, `speakerName: "Apple Watch"`. They land in History with a status message and never
  switch the open conversation (decision 6). Transcription language is the phone's current
  `MobileSession.language` when the drain runs (decision 7). No notifications (decision 8).
  `MobileFileTranscriber` is internal; no user-facing audio-file import (decision 9).
- Release: slices 1–3 merge to `main` **unreleased** and ship together on one train after Slice 3
  passes physical-device acceptance (decision 4). `CHANGELOG.md` gets an iOS Unreleased entry per
  slice. `docs/IOS.md`, `docs/ios-privacy.md`, `docs/ios-support.md`, `README.md` and What to Test
  change only in Task 21.
- Do not edit `docs/IOS.md` before Task 21.
- Copy fixed by this plan (use verbatim):
  - "iPhone not reachable"
  - "Open ListenToMe on your iPhone to record"
  - "Generating a summary on iPhone" / "Stopping on iPhone"
  - "Update ListenToMe on your iPhone and Apple Watch"
  - "iPhone is recording · <elapsed>" / "Apple Watch is recording · <elapsed>"
  - "Stopped: ListenToMe left the foreground on iPhone"
  - "<N> recording(s) waiting for iPhone"
  - "Part of this recording (about <N> min) did not arrive from Apple Watch."
  - "This Apple Watch recording ended unexpectedly. The last few minutes may be missing."
  - "Apple Watch recording added to History."
  - Consent (first watch recording): "Only record people who have agreed to be recorded. The audio
    goes only to your iPhone, which transcribes it on-device and then deletes it."
  - Watch `NSMicrophoneUsageDescription`: "ListenToMe records on your Apple Watch and sends the audio
    only to your paired iPhone, where it is transcribed on-device."

## Review Focus

1. **Phone app woken in the background by a watch Start.** A WatchConnectivity message can launch
   the iOS app in the background, before any scene exists and while `MobileSession.isForeground`
   still holds its default `true`. Expected: the reply is `openPhoneApp` and the microphone is never
   touched. Task 6 decides "active" from `UIApplication.shared.applicationState == .active` through
   an injectable closure, and a link with no attached session answers `openPhoneApp`; both are
   tested there (`testStartFromWatchWhileNotActiveNeverCreatesARecorder`,
   `testLinkWithoutAnAttachedSessionAnswersOpenPhoneApp`).
2. **The watch conversation is the one open on the phone when more chunks arrive** (after Continue,
   or a resumed drain). Expected: the new text appears in the open conversation and nothing is lost
   when it next saves. Task 12 routes writes for the open record through the live session and tests
   it (`testAppendsToTheOpenConversationWhenItIsTheWatchRecording`).
3. **The user starts a live recording while a drain is transcribing.** Expected: the drain stops
   before the recorder prepares (F14), no audio is deleted that is not saved as text, and the drain
   resumes later with no duplicated words. Task 12 tests the ordering and the resume.
4. **Chunks arrive out of order, twice, after the recording was already finished, or never.**
   Expected: duplicates are no-ops, transcription waits for a missing chunk for 24 hours and then
   continues with a visible note, a chunk after a finished recording reopens the same conversation,
   and a recording whose watch never sends an end still finishes after 24 hours. Task 9 tests each
   ledger case and Task 12 tests the reopen.
5. **Battery level unknown (`-1`) or free space unreadable on the watch.** Expected: neither blocks
   nor stops a recording by itself. A write failure still ends the recording with a reason. Task 16
   tests the unknown inputs.

---

## File structure

**Created**

| Path | Responsibility | Task |
| --- | --- | --- |
| `watch-embed.yml` | XcodeGen include that embeds `ListenToMeWatch` in `ListenToMeIOS`; enabled by `WATCH_EMBED=YES` until Task 21 | 2 |
| `Watch/Info.plist`, `Watch/Assets.xcassets/` | Watch app identity, icon | 2, 19 |
| `Watch/ListenToMeWatchApp.swift` | `@main`, `WCSession` background task | 2, 7 |
| `Watch/WatchLinkClient.swift` | Watch side of `WCSession`: commands, phone status, file transfers | 7, 18 |
| `Watch/RemoteControlView.swift` | Slice 1 screen | 7 |
| `Watch/WatchRecorder.swift` | Audio session, engine tap, AAC chunk rotation, limits, interruptions | 17 |
| `Watch/WatchOutbox.swift` | Finalized chunks on disk, queueing, reconcile, delete-on-success | 18 |
| `Watch/WatchRootView.swift`, `Watch/WatchRecordingView.swift` | Slice 3 UI | 19 |
| `Sources/ListenToMeCore/WatchLink.swift` | Wire protocol and watch display text (compiled into the watch) | 4, 8, 16 |
| `Sources/ListenToMeCore/RemoteRecorderPolicy.swift` | Which watch command the phone accepts | 5 |
| `Sources/ListenToMeCore/WatchCaptureLedger.swift` | Phone inbox manifest per recording | 9 |
| `Sources/ListenToMeCore/WatchCapturePolicy.swift` | Watch limits, rotation, outbox reconcile, retry delay (compiled into the watch) | 16 |
| `iOS/PhoneWatchLink.swift` | Phone side of `WCSession`; `WatchLinking` protocol | 6, 10, 20 |
| `iOS/MobileSession+Watch.swift` | Remote commands and status publication | 6, 20 |
| `iOS/WatchInbox.swift` | Synchronous receive path and manifest persistence (not main-actor) | 10 |
| `iOS/MobileSpeechModel.swift` | Shared "supported locale + assets + format" preparation | 11 |
| `iOS/MobileFileTranscriber.swift` | One `SpeechAnalyzer` session over ordered `.m4a` chunks | 11 |
| `iOS/MobileSession+WatchInbox.swift` | Foreground drain into a conversation | 12, 13 |
| `Tests/ListenToMeCoreTests/WatchLinkTests.swift`, `RemoteRecorderPolicyTests.swift`, `WatchCaptureLedgerTests.swift`, `WatchCapturePolicyTests.swift` | Core tests | 4, 5, 8, 9, 16 |
| `iOSUnitTests/MobileWatchRemoteTests.swift`, `WatchInboxTests.swift`, `MobileFileTranscriberTests.swift`, `MobileWatchDrainTests.swift`, `WatchTestDoubles.swift` | App-hosted tests | 6, 10–13 |
| `iOSUnitTests/Fixtures/watch-chunk-0.m4a`, `watch-chunk-1.m4a` | Speech fixtures | 11 |

**Modified:** `project.yml`, `Makefile`, `.swiftlint.yml`, `scripts/ios-testflight.sh`,
`scripts/test-ios-testflight.py`, `iOS/MobileSession.swift`, `iOS/MobileRecorder.swift`,
`iOS/ListenToMeIOSApp.swift`, `iOS/MobileHistoryView.swift`, `iOS/MobileMeetingView.swift`,
`docs/IOS-RELEASING.md`, `CHANGELOG.md`; in Task 21 also `docs/IOS.md`, `docs/ios-privacy.md`,
`docs/ios-support.md`, `README.md`, `metadata/ios/en-CA/what-to-test-<version>.txt`.

## CI and build impact

- **SDK on the runner:** the `macos-26` image (20261013) defaults to Xcode 26.6, which ships the
  watchOS 26.5 SDK and watchOS 26.5 Simulator SDK (F16). Building needs only the SDK: a scratch
  project built an embedded watch app and a standalone watch scheme with **no watchOS simulator
  runtime installed** (F19). No workflow change is needed.
- **If a future image drops the SDK** (the build fails with "watchOS … is not installed" or "unable
  to find a destination matching … watchOS Simulator"): add one step before `make ios-build` in the
  `ios` job of `.github/workflows/ci.yml`, `xcodebuild -downloadPlatform watchOS`, or pin an
  installed Xcode with `sudo xcode-select -s /Applications/Xcode_<version>.app`. Keep the job name
  `iOS 26 app build`: the branch ruleset requires it by name.
- **What builds where:** `make ios-build` gains a second `xcodebuild` for the `ListenToMeWatch`
  scheme (`generic/platform=watchOS Simulator`), so CI's `ios` job compiles the watch app with no
  workflow edit. `make ios-archive` stays unchanged and embeds nothing unless `WATCH_EMBED=YES`.
  Task 21 makes the embed permanent; the scheme then builds the watch app as a dependency and the
  second invocation is removed.
- **SDK skew:** local builds use Xcode 27 (watchOS 27.0 SDK). CI catches use of API newer than
  watchOS 26.5; treat a CI-only watch compile failure as that.
- **Tests:** Core logic runs under `swift test` and the 95% coverage floor in the `core` job. There
  is no watchOS test target: the maintainer's Mac has no watchOS simulator runtime, and the watch
  files hold no logic that Core does not already test.
- **Time:** expect the `ios` job to grow by the watch compile, roughly a minute or two.

---

## Prerequisite

### Task 1: Rebase on `main` after #180 merges

#180 (iOS speaker labels, PR #186) also edits `project.yml` (adds `FluidAudio` to `ListenToMeIOS`),
`iOS/MobileRecorder.swift` (adds `attachSpeakerAudio(_:)` to `MobileRecording`) and
`iOS/MobileSession.swift`, and adds `iOS/MobileSession+Speakers.swift`. Start no other task until
this one is done.

- [ ] **Step 1: Confirm #186 is merged.** Run `gh pr view 186 --json state,mergedAt`. Expected:
  `"state":"MERGED"`. If not, stop and wait.
- [ ] **Step 2: Branch from fresh `main`.** `git fetch origin && git checkout -b feat/181-watch-slice-1 origin/main`
  (or `git rebase origin/main` on an existing branch).
- [ ] **Step 3: Re-read what #180 changed.** Note the current `MobileRecording` requirements and the
  `MobileSpeakers` API (`beginRun(offset:existing:) -> SpeakerAudioBuffer?` at the time of
  writing). Task 6 test doubles and Task 14 depend on them; adjust their names to what merged.
- [ ] **Step 4: Baseline is green.** Run `swift test` and `make ios-build`. Expected: both succeed.

---

## Slice 1: target, link, remote control

### Task 2: Watch target, gated embed and build wiring

**Files:**
- Create: `watch-embed.yml`, `Watch/Info.plist`, `Watch/ListenToMeWatchApp.swift`,
  `Watch/Assets.xcassets/Contents.json`, `Watch/Assets.xcassets/AppIcon.appiconset/{Contents.json,AppIcon.png}`
- Modify: `project.yml`, `Makefile:66-71`, `.swiftlint.yml`

**Interfaces:**
- Produces: target and scheme `ListenToMeWatch`; `make watch-build`; env toggle `WATCH_EMBED=YES`.

- [ ] **Step 1: Add the target and scheme to `project.yml`.**

```yaml
  ListenToMeWatch:
    type: application
    platform: watchOS
    deploymentTarget: "26.0"
    sources:
      - Watch
      - path: Sources/ListenToMeCore/WatchLink.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tomwu.ListenToMe.ios.watchkitapp
        PRODUCT_NAME: ListenToMeWatch
        MARKETING_VERSION: "<same literal as ListenToMeIOS>"
        CURRENT_PROJECT_VERSION: "<same literal as ListenToMeIOS>"
        INFOPLIST_FILE: Watch/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        DEVELOPMENT_TEAM: T32FW7PZ3S
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

  Under `schemes:` add `ListenToMeWatch: { build: { targets: { ListenToMeWatch: all } } }`. At the
  top add:

```yaml
include:
  - path: watch-embed.yml
    enable: ${WATCH_EMBED}
```

  `watch-embed.yml` holds only `targets: ListenToMeIOS: dependencies: [{ target: ListenToMeWatch, embed: true }]`.
  XcodeGen appends that dependency to the existing list (verified in a scratch project: the base
  dependencies stay, and "Embed Watch Content" appears only with `WATCH_EMBED=YES`). Add a comment
  in `project.yml` above `include:` pointing to decision 4 and Task 21.
- [ ] **Step 2: `Watch/Info.plist`.** Same `CFBundle*` keys as `iOS/Info.plist` (version and build from
  `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`), plus `CFBundleDisplayName` "ListenToMe",
  `WKApplication` true, `WKCompanionAppBundleIdentifier` `com.tomwu.ListenToMe.ios`,
  `WKRunsIndependentlyOfCompanionApp` false. No microphone key and no background modes yet (Task 19).
- [ ] **Step 3: Icon and app entry.** Copy `iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; the
  set's `Contents.json` has one image with `"idiom": "universal"`, `"platform": "watchos"`,
  `"size": "1024x1024"`. `ListenToMeWatchApp.swift` is a `@main` SwiftUI app showing `Text("ListenToMe")`.
- [ ] **Step 4: Makefile and lint.** Add
  `watch-build: gen` → `xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/ios $(IOS_SIGN_FLAGS) build`,
  and make `ios-build` run it after the iOS build (`$(MAKE) watch-build` as its last line, or list
  it as a second command). Add `.PHONY: watch-build`. Add `- Watch` to `.swiftlint.yml` `included`.
- [ ] **Step 5: Verify the default build does not embed.** Run `make ios-build`. Expected:
  `** BUILD SUCCEEDED **` twice; `.build/ios/Build/Products/Debug-watchsimulator/ListenToMeWatch.app`
  exists; `ls .build/ios/Build/Products/Debug-iphonesimulator/ListenToMeIOS.app/Watch` fails (no
  such directory).
- [ ] **Step 6: Verify the gated embed.** Run `WATCH_EMBED=YES make ios-build`. Expected: success and
  `.build/ios/Build/Products/Debug-iphonesimulator/ListenToMeIOS.app/Watch/ListenToMeWatch.app/Info.plist`
  exists. Then run `make gen` without the variable again so the working project is back to default.
- [ ] **Step 7: Spike the signed archive (settles the §5.1 U).** Run
  `WATCH_EMBED=YES make ios-archive`. Expected: `** ARCHIVE SUCCEEDED **`, automatic signing creates
  the `com.tomwu.ListenToMe.ios.watchkitapp` profile, and
  `dist/ListenToMe-iOS.xcarchive/Products/Applications/ListenToMeIOS.app/Watch/ListenToMeWatch.app`
  exists. Record the outcome in the PR. Do **not** upload this archive. If the archive needs a
  WatchKit extension target, stop and raise it on #181 before continuing.
- [ ] **Step 8: Lint and commit.** `make lint` (expected: no output), then commit
  `feat(watch): add the ListenToMeWatch target behind WATCH_EMBED (#181)`.

### Task 3: TestFlight helper guards the watch bundle

**Files:**
- Modify: `scripts/ios-testflight.sh:16-29`, `scripts/test-ios-testflight.py`, `docs/IOS-RELEASING.md`

**Interfaces:**
- Produces: a helper that **rejects** any archive containing `ListenToMeIOS.app/Watch/` until Task 21
  flips the rule to "required and matching".

- [ ] **Step 1: Write the failing test.**

```python
    def test_embedded_watch_app_is_rejected_until_watch_release(self):
        watch = self.root / 'fixture.xcarchive/Products/Applications/ListenToMeIOS.app/Watch/ListenToMeWatch.app'
        watch.mkdir(parents=True)
        (watch / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.tomwu.ListenToMe.ios.watchkitapp',
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
            'WKCompanionAppBundleIdentifier': 'com.tomwu.ListenToMe.ios'}))
        result = self.run_upload(flags=['--dry-run'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Watch app', result.stderr + result.stdout)
        self.assertFalse(self.evidence.exists())
```

- [ ] **Step 2: Run it.** `python3 scripts/test-ios-testflight.py -k embedded_watch`. Expected: FAIL
  (exit 0 from the helper).
- [ ] **Step 3: Implement.** In the helper's Python block, after the extension checks:
  `assert not (root / 'Watch').exists(), 'Watch app embedded before the watch release train (#181 decision 4)'`.
- [ ] **Step 4: Run all helper tests.** `python3 scripts/test-ios-testflight.py`. Expected: OK.
- [ ] **Step 5: Docs.** In `docs/IOS-RELEASING.md` add the watch bundle row
  (`com.tomwu.ListenToMe.ios.watchkitapp`, "not shipped until the #181 train") to the identity table,
  and one sentence by the version paragraph: the watch target keeps the same version and build as
  the app and share extension, and `make ios-archive` must run **without** `WATCH_EMBED` until the
  #181 train. Commit `build(ios): refuse to upload an archive with the unreleased watch app (#181)`.

### Task 4: Core `WatchLink`: commands, replies, phone status, display text

**Files:**
- Create: `Sources/ListenToMeCore/WatchLink.swift`, `Tests/ListenToMeCoreTests/WatchLinkTests.swift`

**Interfaces:**
- Produces (all `public`, `Sendable`, Foundation only, so the watch can compile the file):
  - `enum WatchLink { static let protocolVersion = 1 }`
  - `enum WatchCommand: String, CaseIterable { case start, stop, status }`
  - `enum PhoneRecorderState: String { case idle, preparing, recording, stopping }`
  - `enum PhoneStopReason: String { case user, interruption, routeLost, background }`
  - `struct PhoneRecorderStatus: Equatable { var state: PhoneRecorderState; var startedAt: Date?; var title: String; var lastStopReason: PhoneStopReason? }`
  - `enum WatchReply: Equatable { case accepted(PhoneRecorderStatus), openPhoneApp, busy(String), unsupportedVersion }`
  - `enum WatchLinkError: Error, Equatable { case unsupportedVersion(Int?), malformed(String) }`
  - `WatchLink.message(for: WatchCommand) -> [String: Any]` and `WatchLink.command(from: [String: Any]) throws -> WatchCommand`
  - `WatchLink.message(for: WatchReply) -> [String: Any]` and `WatchLink.reply(from: [String: Any]) throws -> WatchReply`
  - `WatchLink.context(for: PhoneRecorderStatus) -> [String: Any]` and `WatchLink.phoneStatus(fromContext: [String: Any]) -> PhoneRecorderStatus?`
  - `WatchLink.elapsedText(_ seconds: TimeInterval) -> String`
  - `enum WatchRemoteText { static func line(status: PhoneRecorderStatus?, reachable: Bool, lastReply: WatchReply?, now: Date) -> String }`

  Keys: `"v"` (Int), `"cmd"`, `"reply"`, `"status"`, `"busy"`, `"phone"`; status dictionary keys
  `"state"`, `"startedAt"` (Double, seconds since 1970), `"title"`, `"stopReason"`. Only
  property-list types cross the link. No transcript text ever crosses.

- [ ] **Step 1: Write the failing tests.**

```swift
func testCommandRoundTripsAndCarriesTheProtocolVersion() throws {
    for command in WatchCommand.allCases {
        let message = WatchLink.message(for: command)
        XCTAssertEqual(message["v"] as? Int, 1)
        XCTAssertEqual(try WatchLink.command(from: message), command)
    }
}
func testUnknownVersionAndMalformedMessagesAreRejected() {
    XCTAssertThrowsError(try WatchLink.command(from: ["v": 2, "cmd": "start"])) {
        XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(2)) }
    XCTAssertThrowsError(try WatchLink.command(from: ["cmd": "start"])) {
        XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(nil)) }
    XCTAssertThrowsError(try WatchLink.command(from: ["v": 1, "cmd": "erase"]))
    XCTAssertThrowsError(try WatchLink.command(from: ["v": 1]))
}
func testEveryReplyRoundTrips() throws {
    let status = PhoneRecorderStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                     title: "Standup", lastStopReason: nil)
    for reply in [WatchReply.accepted(status), .openPhoneApp, .busy("Stopping on iPhone"), .unsupportedVersion] {
        XCTAssertEqual(try WatchLink.reply(from: WatchLink.message(for: reply)), reply)
    }
}
func testPhoneStatusContextRoundTripsAndIgnoresOtherVersions() {
    let status = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "A", lastStopReason: .background)
    XCTAssertEqual(WatchLink.phoneStatus(fromContext: WatchLink.context(for: status)), status)
    XCTAssertNil(WatchLink.phoneStatus(fromContext: ["v": 2, "phone": [:]]))
    XCTAssertNil(WatchLink.phoneStatus(fromContext: [:]))
}
func testElapsedText() {
    XCTAssertEqual(WatchLink.elapsedText(0), "00:00")
    XCTAssertEqual(WatchLink.elapsedText(65.9), "01:05")
    XCTAssertEqual(WatchLink.elapsedText(3_725), "1:02:05")
    XCTAssertEqual(WatchLink.elapsedText(-3), "00:00")
}
func testRemoteTextPrecedence() {
    let now = Date(timeIntervalSince1970: 1_065)
    let recording = PhoneRecorderStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                        title: "A", lastStopReason: nil)
    XCTAssertEqual(WatchRemoteText.line(status: recording, reachable: true, lastReply: nil, now: now),
                   "iPhone is recording · 01:05")
    XCTAssertEqual(WatchRemoteText.line(status: recording, reachable: false, lastReply: nil, now: now),
                   "iPhone not reachable")
    XCTAssertEqual(WatchRemoteText.line(status: nil, reachable: true, lastReply: .openPhoneApp, now: now),
                   "Open ListenToMe on your iPhone to record")
    XCTAssertEqual(WatchRemoteText.line(status: nil, reachable: true, lastReply: .unsupportedVersion, now: now),
                   "Update ListenToMe on your iPhone and Apple Watch")
    let stopped = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "A", lastStopReason: .background)
    XCTAssertEqual(WatchRemoteText.line(status: stopped, reachable: true, lastReply: nil, now: now),
                   "Stopped: ListenToMe left the foreground on iPhone")
}
```

- [ ] **Step 2: Run them.** `swift test --filter WatchLinkTests`. Expected: FAIL (types undefined).
- [ ] **Step 3: Implement** in `WatchLink.swift`, importing only Foundation. `WatchRemoteText.line`
  precedence: unreachable → "iPhone not reachable"; then `lastReply` (`openPhoneApp`,
  `unsupportedVersion`, `busy(text)` → text); then status: `recording` → "iPhone is recording · …",
  `preparing` → "Starting on iPhone…", `stopping` → "Stopping on iPhone", `idle` with
  `.background` → the foreground message, other `idle` → "Ready"; `nil` status → "Ready".
- [ ] **Step 4: Run.** `swift test --filter WatchLinkTests` passes, then `./scripts/check-coverage.sh 95`
  passes.
- [ ] **Step 5: Commit** `feat(core): WatchLink protocol for the watch remote (#181)`.

### Task 5: Core `RemoteRecorderPolicy`

**Files:**
- Create: `Sources/ListenToMeCore/RemoteRecorderPolicy.swift`, `Tests/ListenToMeCoreTests/RemoteRecorderPolicyTests.swift`

**Interfaces:**
- Consumes: `WatchCommand`, `PhoneRecorderState`, `WatchReply` (Task 4).
- Produces: `public enum RemoteRecorderDecision: Equatable, Sendable { case start, stop, report, reply(WatchReply) }`
  and `public enum RemoteRecorderPolicy { static func decide(_ command: WatchCommand, state: PhoneRecorderState, isActive: Bool, isSummarizing: Bool) -> RemoteRecorderDecision }`.

The table the tests pin (every cell):

| Command | Not active | idle | idle + summarizing | preparing / recording | stopping |
| --- | --- | --- | --- | --- | --- |
| `start` | `reply(.openPhoneApp)` | `start` | `reply(.busy("Generating a summary on iPhone"))` | `report` | `reply(.busy("Stopping on iPhone"))` |
| `stop` | `report` unless recording/preparing → `stop` | `report` | `report` | `stop` | `report` |
| `status` | `report` | `report` | `report` | `report` | `report` |

- [ ] **Step 1: Write the failing test** `testEveryCommandStateAndForegroundCell` that loops over
  `WatchCommand.allCases × [idle, preparing, recording, stopping] × [true, false] × [true, false]`
  and asserts the table above, plus `testInactiveStartNeverStarts` asserting no input with
  `isActive: false` returns `.start`.
- [ ] **Step 2: Run** `swift test --filter RemoteRecorderPolicyTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `decide` as a `switch` over `(command, state)` with the `isActive` guard
  first for `start`.
- [ ] **Step 4: Run** the filter and `./scripts/check-coverage.sh 95`. Expected: pass.
- [ ] **Step 5: Commit** `feat(core): policy for watch remote commands (#181)`.

### Task 6: iPhone link and remote handling in `MobileSession`

**Files:**
- Create: `iOS/PhoneWatchLink.swift`, `iOS/MobileSession+Watch.swift`, `iOSUnitTests/WatchTestDoubles.swift`,
  `iOSUnitTests/MobileWatchRemoteTests.swift`
- Modify: `iOS/MobileSession.swift` (stored properties and `state` `didSet`), `iOS/ListenToMeIOSApp.swift`

**Interfaces:**
- Consumes: Task 4 types, `RemoteRecorderPolicy.decide` (Task 5).
- Produces:
  - `@MainActor protocol WatchLinking: AnyObject { func publish(_ status: PhoneRecorderStatus) }`
  - `final class PhoneWatchLink: NSObject, WCSessionDelegate, WatchLinking` with
    `static func activateIfSupported() -> PhoneWatchLink?` (returns nil when
    `WCSession.isSupported()` is false, e.g. iPad, U6; Task 10 adds an `inbox:` parameter),
    `var commandHandler: (@MainActor (WatchCommand) async -> WatchReply)?`, and the testable core of
    its message handler,
    `static func replyMessage(to message: [String: Any], handler: (@MainActor (WatchCommand) async -> WatchReply)?) async -> [String: Any]`
  - On `MobileSession`: `var watchLink: (any WatchLinking)?`,
    `var applicationIsActive: @MainActor () -> Bool` (default
    `{ UIApplication.shared.applicationState == .active }`), `private(set) var recordingStartedAt: Date?`,
    `var phoneRecorderStatus: PhoneRecorderStatus`, `func handleWatchCommand(_: WatchCommand) async -> WatchReply`,
    `func publishWatchStatus()`.
  - Test double `FakeWatchLink: WatchLinking` with `published: [PhoneRecorderStatus]`, in
    `WatchTestDoubles.swift`.

- [ ] **Step 1: Write the failing tests** in `MobileWatchRemoteTests.swift`. Use the existing
  `LifecycleTestRecorder` (or #180's `SpeakerTestRecorder`) for `makeRecorder`, counting how often
  the factory is called; do not add another recorder fake.

```swift
func testStartFromWatchWhileNotActiveNeverCreatesARecorder() async {
    var made = 0
    let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
    session.applicationIsActive = { false }
    let reply = await session.handleWatchCommand(.start)
    XCTAssertEqual(reply, .openPhoneApp)
    XCTAssertEqual(made, 0)
    XCTAssertEqual(session.state, .idle)
}
func testStartFromWatchWhileActiveStartsAndPublishesRecording() async throws  // reply is .accepted with state .preparing; after the fake recorder starts, the last published status is .recording with startedAt set
func testStopFromWatchStopsAndPublishesIdle() async throws
func testStartWhileSummarizingRepliesBusy() async  // reply == .busy("Generating a summary on iPhone")
func testBackgroundStopPublishesTheBackgroundReason() async throws  // start, handleScenePhase(.background): last published is .idle with lastStopReason .background
func testStatusCommandReportsWithoutTouchingTheRecorder() async
func testLinkWithoutAnAttachedSessionAnswersOpenPhoneApp() async {
    let reply = await PhoneWatchLink.replyMessage(to: WatchLink.message(for: .start), handler: nil)
    XCTAssertEqual(try WatchLink.reply(from: reply), .openPhoneApp)
}
func testUnknownProtocolVersionAnswersUnsupportedVersion() async {
    let reply = await PhoneWatchLink.replyMessage(to: ["v": 2, "cmd": "start"], handler: { _ in .openPhoneApp })
    XCTAssertEqual(try WatchLink.reply(from: reply), .unsupportedVersion)
}
```

- [ ] **Step 2: Run** `make ios-test` (or
  `xcodebuild … -only-testing:ListenToMeIOSUnitTests/MobileWatchRemoteTests test` with the
  Makefile's flags). Expected: FAIL to compile.
- [ ] **Step 3: Implement.**
  - `MobileSession.swift`: the stored properties above; `state`'s `didSet` also sets
    `recordingStartedAt` (now on entering `.recording`, nil on `.idle`) and calls
    `publishWatchStatus()`. `stopReason` maps to `PhoneStopReason` by name.
  - `MobileSession+Watch.swift`: `handleWatchCommand` calls
    `RemoteRecorderPolicy.decide(command, state:, isActive: applicationIsActive(), isSummarizing:)`;
    `.start` → `start()`, `.stop` → `await stop()`, then `.accepted(phoneRecorderStatus)`; a `reply`
    decision returns it unchanged. `publishWatchStatus()` calls `watchLink?.publish(phoneRecorderStatus)`.
  - `PhoneWatchLink.swift`: activates `WCSession.default` with itself as delegate; implements the
    iOS-only `sessionDidBecomeInactive` and `sessionDidDeactivate` (reactivate in the latter).
    `publish` calls `updateApplicationContext(WatchLink.context(for:))` and ignores errors when no
    watch app is installed. `session(_:didReceiveMessage:replyHandler:)` hops to the main actor
    and replies with `replyMessage(to:handler: commandHandler)`, which decodes with
    `WatchLink.command(from:)`, answers `.unsupportedVersion` for a version error, and otherwise
    returns `handler?(command) ?? .openPhoneApp`. Delegate methods
    are `nonisolated`; wrap the non-`Sendable` reply handler in a small `@unchecked Sendable` box.
  - `ListenToMeIOSApp.swift`: create the link in `init()` (it must be active before any scene
    exists so background-launched messages are answered), and in `.task` attach it:
    `link.commandHandler = { await session.handleWatchCommand($0) }`, `session.watchLink = link`,
    `session.publishWatchStatus()`.
- [ ] **Step 4: Run** the new tests and the whole `ListenToMeIOSUnitTests`. Expected: PASS, no
  regressions.
- [ ] **Step 5: Commit** `feat(ios): answer Apple Watch start, stop and status (#181)`.

### Task 7: Watch remote-control app, Slice 1 acceptance

**Files:**
- Create: `Watch/WatchLinkClient.swift`, `Watch/RemoteControlView.swift`
- Modify: `Watch/ListenToMeWatchApp.swift`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `WatchLink`, `WatchRemoteText` (Task 4).
- Produces: `@MainActor @Observable final class WatchLinkClient: NSObject, WCSessionDelegate` with
  `private(set) var phoneStatus: PhoneRecorderStatus?`, `private(set) var isReachable: Bool`,
  `private(set) var lastReply: WatchReply?`, `private(set) var isSending: Bool`,
  `func activate()`, `func send(_ command: WatchCommand) async`. Task 18 extends this class.

- [ ] **Step 1: `WatchLinkClient`.** `send` uses `sendMessage(_:replyHandler:errorHandler:)` only; it
  never queues a command (`transferUserInfo` is not used for commands, so a stale Start can never
  fire later). On error: `isReachable = false`, `lastReply = nil`. A new application context
  clears `lastReply`. Read `receivedApplicationContext` at activation so the screen shows the truth
  when it opens.
- [ ] **Step 2: `RemoteControlView`.** `TimelineView(.periodic(from: .now, by: 1))` showing
  `WatchRemoteText.line(...)`; one button, "Start" when the phone is idle and "Stop" when it is
  preparing or recording, disabled while `isSending`.
- [ ] **Step 3: App wiring.** `@State private var link = WatchLinkClient()`, `.task { link.activate() }`,
  and `.backgroundTask(.watchConnectivity) { }` on the `WindowGroup` scene, so every
  `WKWatchConnectivityRefreshBackgroundTask` is completed when the closure returns (F11).
- [ ] **Step 4: Build.** `make ios-build` and `make lint`. Expected: both succeed.
- [ ] **Step 5: Physical-device acceptance, spec §6 steps 1–4.** Install with `WATCH_EMBED=YES make gen`,
  then run `ListenToMeIOS` from Xcode on the paired iPhone (the watch app installs with it). Run
  steps 1–4 and record each outcome in the PR. Regenerate with `make gen` afterwards.
- [ ] **Step 6: Changelog.** Add an iOS Unreleased section to `CHANGELOG.md` (create
  `## iOS (unreleased since 1.10.5 (27))`, or whatever iOS build is current, if absent, mirroring the
  macOS one) with "Apple Watch companion, remote Start/Stop for the iPhone recorder (not yet shipped;
  ships with watch recording). (#181)".
- [ ] **Step 7: Commit** `feat(watch): remote control for the iPhone recorder (#181)`. Open the Slice 1
  PR ("Part of #181"); merge when the three checks are green. Do not release.

---

## Slice 2: iPhone watch inbox and file transcription

### Task 8: Core chunk metadata and end marker

**Files:**
- Modify: `Sources/ListenToMeCore/WatchLink.swift`, `Tests/ListenToMeCoreTests/WatchLinkTests.swift`

**Interfaces:**
- Produces:
  - `public struct WatchChunkMetadata: Equatable, Sendable, Codable { let recordingID: UUID; let index: Int; let startOffset: TimeInterval; let duration: TimeInterval; let isLast: Bool; let startedAt: Date; let watchBuild: String }`
    with `static let maximumIndex = 999`, `static let maximumDuration: TimeInterval = 600`,
    `static let maximumFileBytes = 10_000_000`, `var transferMetadata: [String: Any]`,
    `init(transferMetadata: [String: Any]) throws`.
  - `public struct WatchRecordingEnd: Equatable, Sendable { let recordingID: UUID; let startedAt: Date; let lastIndex: Int; let unexpected: Bool }`
    with `var userInfo: [String: Any]` and `init(userInfo: [String: Any]) throws`. Sent with
    `transferUserInfo` only when a recording ended without an `isLast` chunk (Task 18).

- [ ] **Step 1: Write the failing tests:** `testChunkMetadataRoundTrips`;
  `testChunkMetadataRejectsOutOfRangeValues` (index 1000, duration 0, duration 600, negative or
  non-finite `startOffset`, `recordingID` not a UUID, `v` 2 → `.unsupportedVersion(2)`);
  `testChunkMetadataIgnoresPathLikeKeys` (a dictionary with an extra `"path": "../../x"` decodes, and
  the type has no field that could carry it); `testRecordingEndRoundTripsAndRejectsVersion2`.
- [ ] **Step 2: Run** `swift test --filter WatchLinkTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Keys `v`, `recordingID` (String), `index`, `startOffset`, `duration`,
  `isLast`, `startedAt` (Double since 1970), `watchBuild`; end marker adds `end` = `recordingID`,
  `lastIndex`, `unexpected`.
- [ ] **Step 4: Run** the filter and coverage. Expected: pass.
- [ ] **Step 5: Commit** `feat(core): watch chunk metadata and end marker (#181)`.

### Task 9: Core `WatchCaptureLedger`

**Files:**
- Create: `Sources/ListenToMeCore/WatchCaptureLedger.swift`, `Tests/ListenToMeCoreTests/WatchCaptureLedgerTests.swift`

**Interfaces:**
- Consumes: `WatchChunkMetadata`, `WatchRecordingEnd` (Task 8).
- Produces:

```swift
public struct WatchCaptureLedger: Codable, Equatable, Sendable {
    public enum ChunkState: String, Codable, Sendable { case received, transcribed }
    public struct Chunk: Codable, Equatable, Sendable {
        public let index: Int; public let startOffset: TimeInterval; public let duration: TimeInterval
        public var state: ChunkState
        public var end: TimeInterval { get }
    }
    public static let gapTimeout: TimeInterval = 86_400
    public let recordingID: UUID
    public let startedAt: Date
    public private(set) var chunks: [Chunk]            // sorted by index
    public private(set) var lastIndex: Int?
    public private(set) var endedUnexpectedly: Bool
    public private(set) var transcribedThrough: TimeInterval
    public private(set) var lastActivity: Date
    public private(set) var failure: String?
    public private(set) var notedGaps: [ClosedRange<Int>]
    public init(recordingID: UUID, startedAt: Date, at: Date)
    @discardableResult public mutating func receive(_ chunk: WatchChunkMetadata, at: Date) -> Bool   // false = duplicate
    public mutating func receiveEnd(_ end: WatchRecordingEnd, at: Date)
    public func nextBatch(now: Date) -> WatchLedgerBatch
    public mutating func noteGaps(_ gaps: [ClosedRange<Int>])
    public mutating func markTranscribed(through time: TimeInterval) -> [Int]   // indices whose audio may now be deleted
    public mutating func markFailed(_ reason: String)
    public mutating func clearFailure()
    public var isFinished: Bool { get }
    public func gapMinutes(_ gap: ClosedRange<Int>) -> Int
}
public struct WatchLedgerBatch: Equatable, Sendable {
    public let indices: [Int]; public let newGaps: [ClosedRange<Int>]; public let finishes: Bool
}
```

`nextBatch` is the one algorithm the tests do not fully determine: start at the lowest index not
`transcribed`; take consecutive `received` indices; at a missing index, if
`now - lastActivity >= gapTimeout` record the missing run as a new gap and continue after it,
otherwise stop. `finishes` is true when, after this batch, no index up to `lastIndex` (or up to the
highest index seen, once `gapTimeout` has passed with no `lastIndex`) is left untranscribed. A
ledger with `failure != nil` returns an empty, non-finishing batch. A chunk with `index > lastIndex`
(Continue after an interruption) clears `isFinished` and extends `lastIndex` only if it is `isLast`.
`markTranscribed(through:)` advances `transcribedThrough` monotonically and marks every received
chunk with `end <= through + 0.05` as transcribed. `gapMinutes` is
`max(1, round((next.startOffset - previous.end) / 60))`, falling back to `count × 5`.

- [ ] **Step 1: Write the failing tests:**
  `testDuplicateChunkIsANoOp`, `testOutOfOrderArrivalTranscribesOnlyTheContiguousPrefix` (0 and 2 →
  `[0]`), `testMissingChunkWaits24HoursThenIsSkippedWithAGap` (at +23 h `[0]`, at +24 h `[0, 2]` with
  `newGaps == [1...1]` and `finishes`), `testFinishesWhenLastArrivesAndEverythingIsTranscribed`,
  `testRecordingWithNoEndFinishesAfterTheTimeout`, `testUnexpectedEndFinishesAndIsMarked`,
  `testChunkAfterAFinishedRecordingExtendsIt` (Continue), `testMarkTranscribedReturnsOnlyWhollyCoveredChunks`
  (chunks 0–300 and 300–600, through 310 → `[0]`), `testTranscribedThroughNeverMovesBack`,
  `testFailedLedgerYieldsNothingUntilCleared`, `testGapMinutes`, `testCodableRoundTrip`.
- [ ] **Step 2: Run** `swift test --filter WatchCaptureLedgerTests`. Expected: FAIL.
- [ ] **Step 3: Implement** as specified, Foundation only.
- [ ] **Step 4: Run** the filter and `./scripts/check-coverage.sh 95`. Expected: pass.
- [ ] **Step 5: Commit** `feat(core): ledger for watch recordings waiting on iPhone (#181)`.

### Task 10: iPhone receive path (`WatchInbox`)

**Files:**
- Create: `iOS/WatchInbox.swift`, `iOSUnitTests/WatchInboxTests.swift`
- Modify: `iOS/PhoneWatchLink.swift`, `iOS/MobileSession.swift` (`applyBackupExclusion`), `iOS/ListenToMeIOSApp.swift`

**Interfaces:**
- Consumes: `WatchChunkMetadata`, `WatchRecordingEnd`, `WatchCaptureLedger`.
- Produces (`struct WatchInbox: Sendable`, not main-actor: it runs on the WCSession delegate queue):
  - `init(root: URL)`; `static var defaultRoot: URL` = Application Support `/WatchInbox`
  - `enum Acceptance: Equatable { case stored, duplicate, rejected(String) }`
  - `func accept(fileAt url: URL, metadata: [String: Any], now: Date) -> Acceptance`
  - `func acceptEnd(userInfo: [String: Any], now: Date)`
  - `func ledgers() -> [WatchCaptureLedger]` (sorted by `startedAt`; unreadable manifests skipped)
  - `func save(_ ledger: WatchCaptureLedger) throws`
  - `func chunkURL(recordingID: UUID, index: Int) -> URL` (`<root>/<id>/<index>.m4a`)
  - `func deleteChunks(_ indices: [Int], of recordingID: UUID)`, `func removeRecording(_ id: UUID) throws`
  - `func applyBackupExclusion(_ excluded: Bool)`
  - `PhoneWatchLink.activateIfSupported(inbox: WatchInbox) -> PhoneWatchLink?` (replaces Task 6's
    no-argument form) and `PhoneWatchLink.onInboxChanged: (@MainActor () -> Void)?`

- [ ] **Step 1: Write the failing tests:** `testAcceptMovesTheFileSynchronously` (the source is
  gone and `<root>/<id>/0.m4a` exists when `accept` returns; manifest lists index 0);
  `testDuplicateDeliveryIsANoOp`; `testOversizedFileOrBadMetadataIsRejectedAndNothingStored`;
  `testStoredNameNeverComesFromMetadata`; `testEndMarkerBeforeAnyChunkCreatesTheLedger`;
  `testInboxFollowsTheBackupExclusionSetting` (with the setting on, `PrivateStorage.isExcludedFromBackup`
  is true for the recording folder); `testStoredChunkUsesTheArchiveProtectionClass` (the file's
  `.protectionKey` equals `PrivateStorage.directoryAttributes[.protectionKey]`).
- [ ] **Step 2: Run** them. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** `accept` validates with `WatchChunkMetadata(transferMetadata:)` and the
  file size, creates the folder with `PrivateStorage.createDirectory`, **moves** the file with
  `FileManager.moveItem` (F8: before returning), sets the protection attribute, applies the backup
  flag read from `UserDefaults.standard.bool(forKey: MobileSession.excludeBackupKey)` (the app may
  be running without a session), then updates `manifest.json` with
  `PrivateStorage.writingOptions`. In `PhoneWatchLink`, `session(_:didReceive file:)` calls
  `inbox.accept(fileAt: file.fileURL, metadata: file.metadata ?? [:], now: Date())` synchronously,
  then hops to the main actor to call `onInboxChanged`; `session(_:didReceiveUserInfo:)` calls
  `acceptEnd`. `MobileSession.applyBackupExclusion()` also calls
  `WatchInbox(root:).applyBackupExclusion(_:)`. The app passes `WatchInbox(root: WatchInbox.defaultRoot)`
  to `PhoneWatchLink.activateIfSupported(inbox:)`.
- [ ] **Step 4: Run** the tests and the full unit suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ios): file Apple Watch audio into a private inbox (#181)`.

### Task 11: `MobileFileTranscriber`

**Files:**
- Create: `iOS/MobileSpeechModel.swift`, `iOS/MobileFileTranscriber.swift`,
  `iOSUnitTests/MobileFileTranscriberTests.swift`, `iOSUnitTests/Fixtures/watch-chunk-0.m4a`,
  `iOSUnitTests/Fixtures/watch-chunk-1.m4a`
- Modify: `iOS/MobileRecorder.swift` (use the shared preparation; no behavior change)

**Interfaces:**
- Produces:
  - `struct WatchAudioChunk: Sendable, Equatable { let index: Int; let url: URL; let startOffset: TimeInterval; let duration: TimeInterval }`
  - `@MainActor protocol WatchAudioTranscribing: AnyObject { func transcribe(_ chunks: [WatchAudioChunk], locale: Locale, onFinal: @escaping @MainActor (TranscriptSegment) throws -> Void) async throws }`
    Contract: chunks are fed in order into **one** `SpeechAnalyzer`; each final result is delivered
    with times relative to the recording start; the call returns only after everything fed is
    finalized; cancellation stops it promptly and throws `CancellationError`.
  - `enum MobileSpeechModel { static func prepare(locale: Locale, volatileResults: Bool) async throws -> (SpeechTranscriber, AVAudioFormat) }`

- [ ] **Step 1: Make the fixtures.**
  `say -o iOSUnitTests/Fixtures/watch-chunk-0.m4a --file-format=m4af --data-format=aac@16000 "The budget review moves to Friday."`
  and `… watch-chunk-1.m4a … "Sarah will send the numbers."`. Expected per `afinfo`: 1 ch, 16000 Hz,
  aac, about 2 s.
- [ ] **Step 2: Write the failing test** `testTranscribesOrderedChunksWithRecordingRelativeTimes`:
  skip with `XCTSkip` when `targetEnvironment(simulator)` (speech is device-only, like live
  recording); otherwise transcribe both fixtures (chunk 1's `startOffset` = chunk 0's duration) with
  `Locale(identifier: "en_US")` and assert the joined text contains "budget" and "Sarah", and every
  segment containing "Sarah" starts at or after chunk 0's duration minus 0.5 s. Also
  `testCancellationThrowsAndDeliversNothingAfterIt` (device only).
- [ ] **Step 3: Run** on a device: `make ios-test IOS_DESTINATION='platform=iOS,name=<device>'`.
  Expected: FAIL (types undefined). In the simulator both tests are skipped.
- [ ] **Step 4: Implement.** Move the "supported locale, asset installation, best format" block of
  `MobileRecorder.start` into `MobileSpeechModel.prepare` and call it from both. The transcriber uses
  `reportingOptions: []` (finals only) and `attributeOptions: [.audioTimeRange]`, reads each chunk
  with `AVAudioFile(forReading:)` in about 1-second frames, converts with `AVAudioConverter` to the
  analyzer format, yields `AnalyzerInput(buffer:bufferStartTime:)` with
  `CMTime(seconds: chunk.startOffset, preferredTimescale: 48_000)` on each chunk's first buffer, and
  ends with `finalizeAndFinish(through:)` at the last chunk's end. In the simulator it throws the
  same "unavailable in the simulator" message as `MobileRecorder`.
- [ ] **Step 5: Run** the device tests (PASS) and the whole suite in the simulator (no regressions in
  the recorder tests).
- [ ] **Step 6: Commit** `feat(ios): transcribe ordered audio files on-device (#181)`.

### Task 12: Foreground drain into a conversation

**Files:**
- Create: `iOS/MobileSession+WatchInbox.swift`, `iOSUnitTests/MobileWatchDrainTests.swift`
- Modify: `iOS/MobileSession.swift`, `iOS/ListenToMeIOSApp.swift`, `iOSUnitTests/WatchTestDoubles.swift`

**Interfaces:**
- Consumes: `WatchInbox` (Task 10), `WatchAudioTranscribing` (Task 11), `WatchCaptureLedger` (Task 9).
- Produces:
  - `MobileSession.init(…, watchInbox: WatchInbox? = nil, makeWatchTranscriber: @escaping () -> any WatchAudioTranscribing = { MobileFileTranscriber() })`;
    default inbox `WatchInbox(root: storageDirectory.appendingPathComponent("WatchInbox"))`.
  - `func importWatchInbox(now: Date = Date())` (starts `watchDrainTask` when allowed)
  - `private(set) var watchDrainTask: Task<Void, Never>?`
  - `static func transcriptText(for segments: [TranscriptSegment]) -> String`, extracted from
    `save()` and used by both paths.
  - `FakeWatchTranscriber` in `WatchTestDoubles.swift`: scripted segments per chunk index, an
    optional gate that suspends before a given chunk, a `locales: [Locale]` log, and an `events` log
    shared with a fake recorder for ordering assertions.

Rules the tests pin:
- Runs only when `applicationIsActive()`, `state == .idle`, `!isSummarizing` and no drain is
  running. It never starts audio.
- For each ledger (oldest first): find the record whose `sourceImportID == "watch:<id>"` in
  `history`, or create one (title, date = `startedAt`, `isComplete: false`). Record each new gap from
  the batch in the ledger and append the gap note to the record's `notes` on its own line.
- Each final segment: drop it if `segment.start < ledger.transcribedThrough - 0.05` (already saved
  before a resume); otherwise append it as `source: .you`, `speakerName: "Apple Watch"`, persist the
  record, then `markTranscribed(through: segment.end)`, delete the returned chunk files and save the
  ledger. **Audio is deleted only after the text is persisted.**
- After `transcribe` returns: `markTranscribed(through: last chunk end)`, delete, save the ledger.
  If the batch `finishes`: set `isComplete`, add the unexpected-end note when flagged, persist,
  `removeRecording`, `message = "Apple Watch recording added to History."`
- Persisting: if the record is the open conversation (`record.id == id`), update `segments` and
  `notes` and call `save(announce: false)`; otherwise `archive.save(record)` and `remember(record)`
  (relax both from `private` to internal). The open conversation is never switched.
- Errors: `CancellationError` → stop quietly. `MobileSession.isTransient(error)` → leave the ledger
  for the next foreground. Anything else → `markFailed(error.localizedDescription)`, save the ledger,
  and set `message` to "Could not transcribe an Apple Watch recording: <reason> It is kept in
  History, where you can retry or delete it."
- `start()` cancels `watchDrainTask` and its `startTask` awaits that task before `recorder.start`.
  `background()` cancels it and awaits it.
- Triggers: `handleScenePhase(.active)` after `importSharedInbox()`; the App's
  `.onChange(of: session.busy)` when it becomes false; and `PhoneWatchLink.onInboxChanged`.

- [ ] **Step 1: Write the failing tests:**
  `testDrainCreatesAConversationInHistoryWithoutSwitchingTheOpenOne`,
  `testRedeliveredChunkReopensTheSameConversation`,
  `testChunkAudioIsDeletedOnlyAfterItsTextIsSaved` (the transcriber throws a non-transient error
  after chunk 0's segments: chunk 0 is gone, chunk 1 remains, the ledger is failed, the text is in
  the archive),
  `testDrainNeverRunsWhileRecordingSummarizingOrInactive`,
  `testStartingALiveRecordingCancelsTheDrainFirstAndItResumesWithoutDuplicates` (event order is
  `drainCancelled` before `recorderStart`; after `stop()`, the drain resumes at the first chunk not
  transcribed and the transcript holds each sentence once),
  `testAppendsToTheOpenConversationWhenItIsTheWatchRecording`,
  `testGapNoteAppearsAfter24Hours`, `testUnexpectedEndAddsItsNote`,
  `testUsesTheCurrentTranscriptionLanguage` (`session.language = "fr_FR"` → the fake saw `fr_FR`),
  `testTransientFileErrorLeavesTheRecordingForLater`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** per the rules above.
- [ ] **Step 4: Run** the new tests, the whole unit suite and `make ios-build`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ios): turn Apple Watch recordings into conversations (#181)`.

### Task 13: History rows for waiting and failed watch recordings

**Files:**
- Modify: `iOS/MobileSession+WatchInbox.swift`, `iOS/MobileHistoryView.swift`, `iOSUnitTests/MobileWatchDrainTests.swift`

**Interfaces:**
- Produces: `struct WatchInboxRow: Identifiable, Equatable { let id: UUID; let startedAt: Date; let waitingParts: Int; let failure: String? }`;
  `var watchInboxRows: [WatchInboxRow]`; `func retryWatchRecording(_ id: UUID)`;
  `func deleteWatchRecording(_ id: UUID)`; `static func isFromAppleWatch(_ record: SessionRecord) -> Bool`
  (`sourceImportID?.hasPrefix("watch:")`).

- [ ] **Step 1: Write the failing tests:** `testRowsListWaitingAndFailedRecordings`,
  `testRetryClearsTheFailureAndDrains`, `testDeleteRemovesOnlyTheAudioAndKeepsTheConversation`,
  `testRecordsFromTheWatchAreFlagged`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** History gets a "Waiting from Apple Watch" section above the list, shown
  only when rows exist: "Apple Watch · <time>", "<N> parts waiting" or the failure text, and Retry
  (failed rows) and Delete (confirmation: "Delete this Apple Watch audio? Text already transcribed
  stays in History."). Records from the watch show the caption "From Apple Watch". Refresh rows on
  `onInboxChanged` and after each drain.
- [ ] **Step 4: Run** the tests and `make ios-build`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ios): show Apple Watch recordings waiting in History (#181)`.

### Task 14: Speaker labels on watch conversations (after #180)

The spec (§5.5 step 4) says #180's speaker identification runs on watch recordings like any other.
At the time of writing, #180 labels the **open** conversation from a live `SpeakerAudioBuffer`, and
the drain deletes chunk audio as it goes, so this needs explicit wiring.

**Files:**
- Modify: `iOS/MobileFileTranscriber.swift`, `iOS/MobileSession+WatchInbox.swift`, `iOSUnitTests/MobileWatchDrainTests.swift`

**Interfaces:**
- Consumes: #180's `MobileSpeakers` API as merged (Task 1 Step 3).
- Produces: `WatchAudioTranscribing.transcribe(_:locale:speakerAudio:onFinal:)` with
  `speakerAudio: SpeakerAudioBuffer?` receiving every converted buffer.

- [ ] **Step 1: Write the failing test**
  `testSpeakerIdentificationLabelsAWatchConversationWhenEnabled`, using #180's diarizer test double:
  with identification on, the finished watch record's segments carry #180's speaker ids and names;
  with it off, they keep `speakerName: "Apple Watch"`.
- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement.** When identification is on, the drain obtains a buffer the way #180 does
  for a live run, passes it to the transcriber, and when the batch finishes runs #180's pass and
  applies its labels to the watch record (through the open session when it is open, otherwise to the
  archived record). If #180 cannot label a record that is not open without restructuring, stop and
  raise it on #181 rather than restructuring #180's code here.
- [ ] **Step 4: Run** the unit suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ios): speaker labels for Apple Watch conversations (#181)`. Add the
  Slice 2 line to `CHANGELOG.md` (iOS Unreleased): "iPhone transcribes recordings received from Apple
  Watch on-device and deletes the audio afterwards (not yet shipped). (#181)". Open the Slice 2 PR
  ("Part of #181"); merge when green. Do not release.

---

## Slice 3: watch microphone capture and transfer

### Task 15: Device spike: go or no-go on the recorder

Throwaway code on a `spike/181-watch-audio` branch that is never merged. Needs a paired iPhone and
Apple Watch on watchOS 26.

- [ ] **Step 1:** Write a minimal recorder: `.record` session, `AVAudioEngine` input tap,
  `AVAudioFile(forWriting:settings:)` with `AVFormatIDKey: kAudioFormatMPEG4AAC`,
  `AVSampleRateKey: 16_000`, `AVNumberOfChannelsKey: 1`, `AVEncoderBitRateKey: 32_000`
  (these compile for watchOS, F18), rotating every 300 s, and `UIBackgroundModes: [audio]`.
- [ ] **Step 2: Measure and record on #181:** (U3) the chunks play back and `afinfo` shows AAC 16 kHz
  mono; (F5) 30+ minutes with the wrist down continues, and the session icon shows on the watch face;
  (U4) free space via `volumeAvailableCapacityKey` and whether a file created with
  `FileProtectionType.completeUntilFirstUserAuthentication` keeps that attribute; (U2) battery drop
  per 30 min and `transferFile` time for one 300 s chunk.
- [ ] **Step 3: Decide.** Go: continue with Task 16. No-go on AAC from the tap: switch Task 17 to
  `AVAudioRecorder` with the same settings and accept a short gap at each rotation. No-go on
  background recording: stop and raise it on #181 before writing Slice 3 code.

### Task 16: Core `WatchCapturePolicy` and watch status

**Files:**
- Create: `Sources/ListenToMeCore/WatchCapturePolicy.swift`, `Tests/ListenToMeCoreTests/WatchCapturePolicyTests.swift`
- Modify: `Sources/ListenToMeCore/WatchLink.swift`, `Tests/ListenToMeCoreTests/WatchLinkTests.swift`,
  `project.yml` (watch sources gain `Sources/ListenToMeCore/WatchCapturePolicy.swift`)

**Interfaces:**
- Produces:

```swift
public enum WatchCapturePolicy {
    public static let chunkDuration: TimeInterval = 300
    public static let maximumDuration: TimeInterval = 10_800
    public static let minimumStartBattery: Float = 0.20
    public static let stopBattery: Float = 0.10
    public static let minimumFreeBytes: Int64 = 200_000_000
    public enum StartBlock: Equatable, Sendable { case lowBattery, lowStorage }
    public enum StopTrigger: Equatable, Sendable { case lowBattery, durationCap }
    public static func startBlock(battery: Float, freeBytes: Int64?) -> StartBlock?
    public static func stopTrigger(battery: Float, elapsed: TimeInterval) -> StopTrigger?
    public static func shouldRotate(chunkElapsed: TimeInterval) -> Bool
    public static func retryDelay(attempt: Int) -> TimeInterval        // 30 × 2^attempt, capped at 1800
    public static func chunksToQueue(finalized: [URL], outstanding: Set<URL>) -> [URL]
    public static func text(for block: StartBlock) -> String
    public static func text(for trigger: StopTrigger) -> String
}
public enum WatchCaptureState: String, Sendable { case idle, recording }
public struct WatchCaptureStatus: Equatable, Sendable { var state: WatchCaptureState; var startedAt: Date?; var waitingRecordings: Int }
// WatchLink: context(for: WatchCaptureStatus) (key "watch") and watchStatus(fromContext:) -> WatchCaptureStatus?
// WatchRemoteText: watchRecordingLine(_ status: WatchCaptureStatus?, now: Date) -> String?  ("Apple Watch is recording · mm:ss" or nil)
// WatchRemoteText: waitingText(_ count: Int) -> String?  (nil for 0, "1 recording waiting for iPhone", "3 recordings waiting for iPhone")
```

Copy: low battery start "Charge Apple Watch above 20% to record."; low storage "Free up space on Apple
Watch to record. 200 MB is needed."; low battery stop "Recording stopped: Apple Watch battery is at
10%. What was recorded is being sent to iPhone."; cap "Recording stopped at the 3-hour limit. What was
recorded is being sent to iPhone."

- [ ] **Step 1: Write the failing tests:** start blocked at 0.19 and allowed at 0.20; storage blocked
  at 199,999,999 bytes; `startBlock(battery: -1, freeBytes: nil) == nil` (unknown never blocks);
  `stopTrigger` at 0.10 and at 10,800 s, nil at battery -1 and 10,799 s; rotation at 300 s;
  `retryDelay` 30, 60, … capped at 1800; `chunksToQueue` returns finalized URLs not outstanding;
  watch status context round trip; `watchRecordingLine` and `waitingText` copy.
- [ ] **Step 2: Run** `swift test --filter "WatchCapturePolicyTests|WatchLinkTests"`. Expected: FAIL.
- [ ] **Step 3: Implement**, Foundation only.
- [ ] **Step 4: Run** the filter, coverage, and `make ios-build` (the watch now compiles the new file).
- [ ] **Step 5: Commit** `feat(core): limits and transfer rules for watch recording (#181)`.

### Task 17: `WatchRecorder`

**Files:**
- Create: `Watch/WatchRecorder.swift`

**Interfaces:**
- Consumes: `WatchCapturePolicy`, `WatchChunkMetadata` (Task 8).
- Produces: `@MainActor @Observable final class WatchRecorder` with
  `enum Phase: Equatable { case idle, recording(startedAt: Date), stopped(reason: String?, canContinue: Bool) }`,
  `private(set) var phase`, `func start() async throws`, `func stop()`,
  `func continueRecording() async throws`, and `var onChunkFinalized: ((URL, WatchChunkMetadata) -> Void)?`
  for Task 18.

- [ ] **Step 1: Implement.** Start checks `WatchCapturePolicy.startBlock` with
  `WKInterfaceDevice.current().batteryLevel` (monitoring enabled) and `volumeAvailableCapacity`, asks
  `AVAudioApplication.requestRecordPermission()`, sets the session category `.record` and activates
  it, all in the foreground (F5). The tap converts to 16 kHz mono and writes AAC into
  `Application Support/Recording/<recordingID>/<index>.m4a` on a serial queue off the main actor; at
  `shouldRotate` it closes the file between buffers (no gap), and hands it to `onChunkFinalized`
  with metadata (`watchBuild` = `CFBundleVersion`). Check `stopTrigger` at most every 30 s. A stop,
  a limit, or `AVAudioSession.interruptionNotification` (`.began`) closes the current chunk with
  `isLast: true`; an interruption sets `stopped(reason: "Recording stopped by a call or Siri. Tap
  Continue to keep recording.", canContinue: true)`. `continueRecording()` keeps the recording ID,
  continues the index, and sets `startOffset` to the wall-clock seconds since `startedAt`. A write
  error ends the recording with its reason.
- [ ] **Step 2: Build.** `make ios-build` and `make lint`. Expected: success. Device behavior is
  accepted in Task 20.
- [ ] **Step 3: Commit** `feat(watch): record the watch microphone in AAC chunks (#181)`.

### Task 18: Watch outbox and transfer

**Files:**
- Create: `Watch/WatchOutbox.swift`
- Modify: `Watch/WatchLinkClient.swift`

**Interfaces:**
- Consumes: `WatchRecorder.onChunkFinalized` (Task 17), `WatchCapturePolicy.chunksToQueue` and
  `retryDelay` (Task 16), `WatchRecordingEnd` (Task 8).
- Produces: `@MainActor final class WatchOutbox` with `func add(_ url: URL, _ metadata: WatchChunkMetadata) throws`,
  `func reconcileAtLaunch(outstanding: [WCSessionFileTransfer])`,
  `func transferFinished(_ transfer: WCSessionFileTransfer, error: Error?)`,
  `private(set) var waitingRecordings: Int`, `func deleteWaiting()`.

- [ ] **Step 1: Implement.** `add` moves the finalized chunk to `Application Support/Outbox/<id>/<index>.m4a`
  with a `<index>.json` sidecar (the metadata) and calls `transferFile(url, metadata: metadata.transferMetadata)`.
  `transferFinished` deletes the chunk and sidecar only when `error == nil`; on error it re-queues
  after `retryDelay(attempt:)`. `reconcileAtLaunch` re-queues `chunksToQueue(finalized:outstanding:)`.
  At launch, anything left in `Recording/` is a chunk that was never finalized: delete it, and if that
  recording has finalized chunks but none with `isLast`, send
  `WatchRecordingEnd(…, unexpected: true)` with `transferUserInfo`. Directories are created with
  `FileProtectionType.completeUntilFirstUserAuthentication` (as settled by Task 15). Wire
  `session(_:didFinish:error:)` in `WatchLinkClient` to `transferFinished`.
- [ ] **Step 2: Build.** `make ios-build`, `make lint`. Expected: success.
- [ ] **Step 3: Commit** `feat(watch): send recordings to iPhone and delete them once delivered (#181)`.

### Task 19: Watch recording UI, permission and background mode

**Files:**
- Create: `Watch/WatchRootView.swift`, `Watch/WatchRecordingView.swift`
- Modify: `Watch/ListenToMeWatchApp.swift`, `Watch/Info.plist`, `Watch/WatchLinkClient.swift`

- [ ] **Step 1: Info.plist.** Add `NSMicrophoneUsageDescription` (copy from Global Constraints) and
  `UIBackgroundModes` = `[audio]`.
- [ ] **Step 2: UI.** `WatchRootView`: a primary "Record" button, the start-block text when blocked,
  `WatchRemoteText.waitingText` with a Delete action (confirmation "Delete recordings that have not
  reached iPhone?") and the Slice 1 `RemoteControlView` below as "iPhone". `WatchRecordingView`
  (full-screen while recording): red dot, elapsed time (`WatchLink.elapsedText`), Stop; after an
  interruption, the reason and Continue. Haptics: `.start` on start, `.stop` on stop, `.failure` on
  a limit stop. The first Record shows the consent text once (`UserDefaults` key
  `watchRecordingConsentShown`). Microphone denied: "Microphone access is off. Allow ListenToMe in
  Settings on Apple Watch → Privacy & Security → Microphone."
- [ ] **Step 3: Publish watch status.** On every recorder phase change and outbox count change, call
  `updateApplicationContext(WatchLink.context(for: WatchCaptureStatus(...)))`.
- [ ] **Step 4: Build.** `make ios-build`, `make lint`. Expected: success.
- [ ] **Step 5: Commit** `feat(watch): recording screen, consent and background audio (#181)`.

### Task 20: iPhone shows watch recording, physical-device acceptance

**Files:**
- Modify: `iOS/PhoneWatchLink.swift`, `iOS/MobileSession+Watch.swift`, `iOS/MobileMeetingView.swift`,
  `iOSUnitTests/MobileWatchRemoteTests.swift`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `WatchLink.watchStatus(fromContext:)`, `WatchRemoteText.watchRecordingLine` (Task 16).
- Produces: `MobileSession.watchCaptureStatus: WatchCaptureStatus?` and
  `func receiveWatchContext(_ context: [String: Any])`.

- [ ] **Step 1: Write the failing test** `testWatchContextSetsTheRecordingLine`: after
  `receiveWatchContext(WatchLink.context(for: recordingStatus))`, `session.watchCaptureStatus` equals
  it; a context with `v: 2` leaves it unchanged.
- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement.** `PhoneWatchLink.session(_:didReceiveApplicationContext:)` hops to the
  main actor and calls `receiveWatchContext`. `MobileMeetingView` shows
  `WatchRemoteText.watchRecordingLine` in its status area, refreshed each second with a
  `TimelineView`. The phone records nothing in this mode.
- [ ] **Step 4: Run** the unit suite and `make ios-build`. Expected: PASS.
- [ ] **Step 5: Physical-device acceptance, spec §6 steps 5–11** with `WATCH_EMBED=YES make gen` and
  Xcode installs on the paired devices. Record each outcome, the 1-hour battery drop and transfer
  time (step 10) in the PR. Also re-run steps 1–4. Regenerate with `make gen` afterwards.
- [ ] **Step 6: Commit** `feat(ios): show when Apple Watch is recording (#181)`, add the Slice 3 line to
  `CHANGELOG.md` (iOS Unreleased): "Record on Apple Watch with the iPhone elsewhere; the iPhone
  transcribes the audio on-device and deletes it (not yet shipped). (#181)". Open the Slice 3 PR
  ("Part of #181"); merge when green. Do not release.

---

## Release

### Task 21: Release prep for the train that ships the watch

Only after Task 20's acceptance passed on `main`'s code. This is the train's candidate change; the
AGENTS.md ladder (candidate → verified → published) and downloaded-asset verification apply.

**Files:**
- Modify: `project.yml`, `Makefile`, `scripts/ios-testflight.sh`, `scripts/test-ios-testflight.py`,
  `docs/IOS-RELEASING.md`, `docs/IOS.md`, `docs/ios-privacy.md`, `docs/ios-support.md`, `README.md`,
  `CHANGELOG.md`, `iOS/MobileReleaseNotes.swift`, `metadata/ios/en-CA/what-to-test-<version>.txt`
- Delete: `watch-embed.yml`

- [ ] **Step 1: Write the failing helper tests:** replace the Task 3 test with
  `test_missing_watch_app_is_rejected`, `test_watch_bundle_id_and_companion_are_checked` and
  `test_watch_version_must_match_the_app`; the fixture in `setUp` now includes a matching
  `Watch/ListenToMeWatch.app/Info.plist`.
- [ ] **Step 2: Run** `python3 scripts/test-ios-testflight.py`. Expected: FAIL.
- [ ] **Step 3: Implement.** The helper requires `Watch/ListenToMeWatch.app/Info.plist` with
  `CFBundleIdentifier == com.tomwu.ListenToMe.ios.watchkitapp`,
  `WKCompanionAppBundleIdentifier == com.tomwu.ListenToMe.ios`, and version and build equal to the
  app's ("App/watch mismatch"). Move the embed dependency into `ListenToMeIOS` in `project.yml`,
  delete the `include:` block and `watch-embed.yml`, and drop the extra `watch-build` call from
  `ios-build` (the scheme now builds the watch). Bump the version and build on all three targets.
- [ ] **Step 4: Verify.** `python3 scripts/test-ios-testflight.py` (OK), `make ios-build` (watch app
  present under `ListenToMeIOS.app/Watch/`), `make validate-local`, and `make ios-archive` followed
  by `IOS_RELEASE_FLAGS=--dry-run make ios-testflight …` (identity checks pass).
- [ ] **Step 5: Docs.** `docs/IOS.md`: an Apple Watch section or tier row (the watch records in the
  background with the system indicator; the iPhone still does not), the version policy ("the app,
  share-extension and watch targets keep identical values"), and acceptance steps 1–11.
  `docs/ios-privacy.md`: watch audio is held on the watch and the iPhone until transcribed, then
  deleted (decision 3). `docs/ios-support.md`, `README.md`, the release's CHANGELOG section (move the
  Unreleased lines), `MobileReleaseNotes.swift`, What to Test, and `docs/IOS-RELEASING.md` (the watch
  row is now shipped; checks listed). Re-check the App Store privacy answers in App Store Connect
  (still "no data collected").
- [ ] **Step 6: Commit and PR** with "Closes #181", listing every command above and its outcome.
  Publishing follows AGENTS.md; do not call it released until the train publishes it.
