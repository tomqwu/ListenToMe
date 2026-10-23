# Apple Watch recording — design

**Issue:** [#181](https://github.com/tomqwu/ListenToMe/issues/181), part of
[#98](https://github.com/tomqwu/ListenToMe/issues/98). **Status:** approved design. The
maintainer's answers are recorded in [§9 Decisions](#9-decisions). The implementation plan is
[2026-10-22-apple-watch-recording.md](../plans/2026-10-22-apple-watch-recording.md). No app code
exists yet, and nothing in [docs/IOS.md](../../IOS.md) changes until slices 1–3 ship together on one
release train (decision 4).

**Request (TestFlight feedback on iOS 1.10.5 (27)):** "use Apple Watch to record conversations."

**Goal:** a watchOS companion to the iPhone app that can (a) start, stop and show the status of a
recording on the phone, and (b) record on the watch's own microphone when the phone is not at hand,
then hand the audio to the iPhone, where it is transcribed on-device and saved as a normal
conversation. Everything in this document has to fit the product principles: on-device, private,
bring-your-own-model, free and open source. Audio may move from the watch to the paired iPhone and
nowhere else.

---

## 1. Decision summary

| Topic | Recommendation |
| --- | --- |
| Scope | Build **(c) both**, in order: remote control first, watch-mic capture second. |
| First slice | **Slice 1:** add the watch target, the WatchConnectivity link and remote **Start / Stop / status** for the iPhone recorder, which only works while ListenToMe is open on the iPhone. |
| The slice that answers the request | **Slice 3:** watch-mic capture, transferred in chunks, transcribed on the phone. It depends on Slice 2, the iPhone's file transcription and watch inbox. |
| On-watch transcription | **No.** `SpeechAnalyzer` and `SpeechTranscriber` are not available on watchOS (§3). The phone transcribes. |
| Watch background recording | Needed for Slice 3. Without it, lowering the wrist suspends the app and ends the recording. **Approved** (decision 2). |
| iPhone background recording | **Unchanged.** The iPhone never records in the background. It only *receives* files, and transcribes them while it is in the foreground. |
| Raw audio | Kept only until it is transcribed, then deleted from both devices. No "keep the audio" option. **Approved** (decision 3). The privacy page's "does not save raw microphone audio" changes in the release that ships watch-mic capture, not before. |
| Targets | One embedded watchOS app target (`ListenToMeWatch`). No separate WatchKit extension target (§5.1). |
| Shared code | The wire protocol and the chunk, ledger and retention rules go in `ListenToMeCore`, unit-tested by `swift test` under the 95% coverage floor. The watch target compiles only the files it needs. |
| Versioning | The watch app uses the iOS app's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, and the TestFlight helper checks all three bundles. |
| Release | Slices 1–3 merge to `main` unreleased and ship together on one release train once watch-mic capture works (decision 4). |
| Effort | Slice 1 takes about 3–4 days, Slice 2 about 3–4, Slice 3 about 5–7, plus 1–1.5 days of physical-device acceptance. Optional Slice 4 polish takes 2–3 days. |

---

## 2. Scope options compared

| | (a) Remote control for the phone recorder | (b) Record on the watch mic, transfer to phone | (c) Both |
| --- | --- | --- | --- |
| What the user gets | Start, Stop, elapsed time and state on the wrist while the iPhone app is open, for example with the phone on a table across the room | Recording with no phone in hand or in range, for example a hallway conversation or a lecture with the phone in a bag | Both |
| Answers "record conversations with the watch"? | Partly. The phone still has to be open, unlocked and in the foreground | **Yes** | Yes |
| Platform risk | Low. Messages only, no audio leaves the phone | Medium to high: watch background audio, battery, transfer timing, file-format support on watchOS | Same as (b) |
| Privacy change | **None.** The phone's existing foreground recording, its UI and the system microphone indicator are unchanged | New: background recording *on the watch* and transient raw audio on both devices | Same as (b) |
| New iPhone code | WCSession link and a command handler around `MobileSession.start()` / `stop()` | WCSession link, a watch inbox, file transcription with `SpeechAnalyzer` and import as a conversation | Union, with the link shared |
| Testability | High. The command state machine is pure | Medium. Transfers do not run in Simulator, so acceptance needs paired devices | — |
| Effort | 3–4 days | 8–11 days (Slices 2 and 3) | 11–15 days, plus optional polish |

**Recommendation: (c), with (a) as Slice 1.** Slice 1 is small, but it puts every piece of
infrastructure in place that (b) needs: the embedded target, XcodeGen, signing, CI, the TestFlight
helper, version tracking and the WatchConnectivity session. It does this without new recording
surface, without background recording and without stored audio. Each of those risks can then be
shaken out on its own before the audio path depends on it.

Slice 1 alone does **not** satisfy the TestFlight request, so it is not released alone: slices 1–3
merge to `main` unreleased and ship together on one train when watch-mic capture works
(decision 4). Slice 1 still de-risks embedding, signing, CI and the version helper, because each of
those is exercised on `main` and by a local archive long before the train.

Remote control has a hard limit: **a watch command can never make the iPhone record in the
background.** A watch message can wake the iPhone app in the background (§3, F9). But the app
declares no `UIBackgroundModes`, so it cannot capture audio there, and this design does not change
that. If the phone app is not in the foreground, the phone answers "Open ListenToMe on your iPhone
to record" and does not touch the microphone.

---

## 3. Platform facts that bound the design

These were checked against Apple's documentation on 2026-10-22, read through the
`developer.apple.com/tutorials/data/documentation/…` JSON that backs each page. **V** means
verified there. **F** means stated by an Apple Frameworks Engineer on the Developer Forums, not in
reference documentation. **U** means not verified. Every U item is a spike task in §7.

| # | Fact | Status | Source / note |
| --- | --- | --- | --- |
| F1 | `SpeechAnalyzer` and `SpeechTranscriber` are available on iOS, iPadOS, Mac Catalyst, macOS, tvOS and visionOS 26. **watchOS is not listed.** `SFSpeechRecognizer` does not list watchOS either. | V | [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer). On-watch transcription is therefore not possible with the engine the iPhone uses. |
| F2 | `AVAudioRecorder` (watchOS 4+), `AVAudioEngine` (watchOS 2+) and the `AVAudioSession` `.record` category (watchOS 2+) are available on watchOS. | V | Platform lists on each reference page. |
| F3 | A background audio session must be **started in the foreground**, then continues after the app moves to the background. While it runs, raising the wrist shows the app, and from the watch face "the system displays an icon above the status bar, indicating that the session is still active." | V | [Enabling Background Sessions](https://developer.apple.com/documentation/watchkit/enabling-background-sessions). This is the system's own recording indicator on the watch. |
| F4 | The documented use of the watchOS `audio` background mode is **playback** (long-form audio over a Bluetooth route). | V | [Playing Background Audio](https://developer.apple.com/documentation/watchkit/playing-background-audio). The reference docs do not describe recording. |
| F5 | Microphone recording **continues in the background on watchOS** once the user starts it in the foreground. It **cannot be started or resumed from the background**, including after an interruption such as a call or Siri. | F | Apple Frameworks Engineer, [thread 751866](https://developer.apple.com/forums/thread/751866) ("Audio recording must begin when the app is in the foreground") and [thread 750432](https://developer.apple.com/forums/thread/750432), 2024. Whether App Review accepts long user-initiated recordings under the audio mode was asked in that thread and left unanswered (U). |
| F6 | Extended runtime sessions come in a fixed set of types: self care (frontmost, 10 min), mindfulness (frontmost, 1 h), physical therapy (background, 1 h), smart alarm (background, schedulable, 30 min), and underwater depth. The type must match the app's purpose ("based on the app's intended use"). | V | [Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions), [`WKBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/wkbackgroundmodes). **None fits conversation recording**, so this design does not use them. |
| F7 | `WCSession.transferFile(_:metadata:)` is asynchronous and queued. The system "may throttle delivery speeds to accommodate performance and power concerns", and transfers continue while the app is suspended. `outstandingFileTransfers` lists undelivered files. **The Simulator does not support it.** | V | [transferFile](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)), [outstandingFileTransfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/outstandingfiletransfers). |
| F8 | On receipt, the file must be **moved synchronously** inside `session(_:didReceive:)`, or "the system deletes the file when the method returns". The Simulator never calls this method. | V | [session(_:didReceive:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:)). |
| F9 | `sendMessage` from an active watch app **wakes the iOS app in the background**. From iOS it does **not** wake the watch app. Both sides must be reachable. | V | [sendMessage](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)), [isReachable](https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable). The phone therefore cannot start a watch recording, which is the property we want. |
| F10 | `updateApplicationContext` is latest-value-wins and can be sent while the counterpart is unreachable. `transferUserInfo` is queued and guaranteed in order. | V | [updateApplicationContext](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)), [transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)). |
| F11 | The watch app's bundle identifier must be based on the iOS app's: `<ios id>.watchkitapp`, and `WKCompanionAppBundleIdentifier` must name the iOS app. Every `WKWatchConnectivityRefreshBackgroundTask` must be completed, or the app crashes when its budget runs out. | V | [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity) sample. |
| F12 | A watch app with a companion iOS app is either *dependent* (it cannot launch until the iOS app is installed) or independent ("Supports Running Without iOS App Installation"). | V | [Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps). |
| F13 | `BGContinuedProcessingTask` (iOS 26) must **start in the foreground**, shows progress in a Live Activity, and can be cancelled by the user or ended by the system under resource pressure. | V | [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask). It is an option for finishing a transcription the user started. It is not used in v1. |
| F14 | `SpeechAnalyzer` can take audio from a file (`start(inputAudioFile:finishAfterFile:)`, `AssetInputSequenceProvider`) or from buffers carrying a `bufferStartTime`. The system limits simultaneous analyses and throws `insufficientResources` when the limit is exceeded. | V | [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer). A file transcription must not run while the phone is recording live. |
| F15 | XcodeGen 2.46 (installed locally) embeds a dependency of `type: application` with `platform: watchOS` into an iOS app's **"Embed Watch Content"** phase (`$(CONTENTS_FOLDER_PATH)/Watch`). | V | `XcodeGenKit/PBXProjGenerator.swift` on master, around lines 787 and 1299. |
| F16 | The `macos-26` GitHub runner (image 20261013) defaults to **Xcode 26.6**, which ships the watchOS 26.5 SDK and watchOS 26.5 Simulator SDK. The image also has watchOS 26.0–26.4 SDKs with older Xcodes, and watchOS 26.2/26.4/26.5 simulator runtimes. The maintainer's Mac has Xcode 27.0 with the watchOS 27.0 SDK and **no watchOS simulator runtime**. | V | [runner-images macos-26 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), and `xcodebuild -showsdks` / `xcrun simctl list runtimes` on 2026-10-22. CI compiles watch code against an older SDK than local builds do, so watch code must not use API newer than watchOS 26.5. |
| F17 | `WKInterfaceDevice.batteryLevel` reports 0.0–1.0 when battery monitoring is enabled. | V | [batteryLevel](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterylevel). |
| F18 | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` is **unavailable on watchOS**. `volumeAvailableCapacityKey` and `FileManager.attributesOfFileSystem(forPath:)[.systemFreeSize]` compile for watchOS. | V | Compiled against the watchOS 27.0 SDK on 2026-10-22 in a scratch project. The same probe also compiled `AVAudioEngine` input taps, `AVAudioFile(forWriting:settings:)` with AAC settings, `AVAudioApplication.requestRecordPermission()`, `WKInterfaceDevice` battery and haptics, `WCSession.transferFile` / `outstandingFileTransfers` / `sendMessage`, and the SwiftUI `.backgroundTask(.watchConnectivity)` scene modifier. Compiling is not behavior: U3 still needs a device. |
| F19 | An XcodeGen 2.46 project with an iOS app that embeds a `platform: watchOS` application target (no extension target) **builds** with `-destination 'generic/platform=iOS Simulator'` and, unsigned, with `generic/platform=iOS`, using Xcode 27.0 with **no watchOS simulator runtime installed**. The watch app lands at `<App>.app/Watch/<Watch>.app`. | V | Scratch project on the maintainer's Mac, 2026-10-22. Signed archiving and provisioning are still the Slice 1 spike. |
| U1 | There is a documented size limit per `transferFile`. | U | None found. The design keeps chunks small (about 1.2 MB, §5.4) so the limit does not matter. |
| U2 | Real transfer throughput and battery cost of a 1-hour recording plus transfer. | U | Measure in the Slice 3 spike. |
| U3 | `AVAudioFile` can **write AAC** (`.m4a`) on watchOS from an `AVAudioEngine` input tap. | U | Spike. Fallback: `AVAudioRecorder` with AAC settings, which leaves a short gap at each chunk boundary. |
| U4 | Free storage available to a watch app, and whether data-protection classes behave as on iOS. | U | Spike. Check free space before recording with `volumeAvailableCapacity` (F18), not `volumeAvailableCapacityForImportantUsage`, which does not exist on watchOS. |
| U5 | App Store validation requires the embedded watch app's version and build to equal the iOS app's. | U | Long-standing behavior. This design matches them regardless (§5.6). |
| U6 | `WCSession.isSupported()` is false on iPad, which cannot pair a watch. | U | The UI hides watch features when the session is unsupported or unpaired. |
| U7 | Which watch models run watchOS 26. | U | It decides who can use the feature. Not a design input. |
| U8 | Whether `SpeechAnalyzer` file transcription keeps running while the iPhone app is in the background without a `BGContinuedProcessingTask`. | U | Assume it does not. v1 transcribes in the foreground and resumes at the next foreground (§5.5). |

---

## 4. Privacy

### 4.1 Rules (all slices)

1. **Watch → paired iPhone only.** Audio and commands travel only over WatchConnectivity between
   the user's own paired devices. The watch app makes no network requests: no `URLSession`, no
   analytics, no crash reporter. Transcription happens on the iPhone with `SpeechAnalyzer`, the
   same on-device path as live recording. AI summaries of a watch conversation then follow the
   provider the user already chose on the phone. A watch conversation is not special-cased.
2. **No recording without a visible indicator on the recording device.**
   - Slice 1: the **iPhone** records, in the foreground, with its existing recording UI and the
     system microphone indicator. The watch also shows "iPhone is recording · mm:ss". The watch
     microphone is not used.
   - Slice 3: the **watch** records. The watch app shows a full-screen recording state with elapsed
     time and a Stop button. While the background session runs, watchOS shows its session icon on
     the watch face and returns to the app on wrist raise (F3). Start and Stop each play a haptic.
     If the iPhone app is open, it shows "Apple Watch is recording · mm:ss" from application
     context. The phone records nothing in this mode.
3. **Recording starts only from a user action on the device that records.** The phone cannot start
   the watch microphone, and the platform prevents it anyway (F5, F9). The watch can ask the phone
   to start only when the phone app is already in the foreground.
4. **No change to the iPhone's foreground-only rule.** `iOS/Info.plist` keeps declaring no
   `UIBackgroundModes`. A watch message that wakes the phone app in the background is answered
   without activating the audio session. Received watch audio is transcribed only while the phone
   app is in the foreground (§5.5).
5. **Raw audio is transient.** The watch deletes each chunk once the transfer to the phone reports
   success (`session(_:didFinish:error:)` with no error). The phone deletes each chunk once its
   transcript segments are saved in the conversation archive. Chunks waiting on either device are
   written with data protection (`completeUntilFirstUserAuthentication` on the phone, matching the
   archive). On the phone they are covered by the existing **Exclude conversations from iCloud
   backup** setting, the same as the share inbox. Any audio still waiting is visible: on the watch
   as "N recordings waiting for iPhone", on the phone as a pending row in History. Both offer
   Delete.
6. **Consent.** The first watch recording shows the same reminder as the privacy page: only record
   people who agreed to it.

### 4.2 Documents that must change when Slice 3 ships

- `docs/ios-privacy.md` currently says the app "does not save raw microphone audio". It must
  describe watch recordings being held as audio on the watch and the iPhone until they are
  transcribed, then deleted.
- `docs/IOS.md` needs a new row in tier 2 or tier 3 for Apple Watch, or a watch section, saying the
  watch records in the background with a system indicator and the iPhone still does not. The tier-3
  row "Background recording" stays true for the iPhone. Also update the version policy (three
  targets) and the physical-device acceptance list.
- `docs/ios-support.md`, `README.md`, `CHANGELOG.md`, `docs/IOS-RELEASING.md` (watch bundle checks),
  the What to Test file for that build, and the App Store privacy answers. These answers should stay
  "no data collected", since nothing reaches the developer, but confirm them in App Store Connect.

---

## 5. Architecture

### 5.1 Targets (`project.yml`)

```yaml
  ListenToMeWatch:
    type: application
    platform: watchOS
    deploymentTarget: "26.0"
    sources:
      - Watch
      - path: Sources/ListenToMeCore/WatchLink.swift      # shared wire protocol (§5.2)
      - path: Sources/ListenToMeCore/WatchCapturePolicy.swift  # limits, rotation, outbox rules (Slice 3)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tomwu.ListenToMe.ios.watchkitapp
        PRODUCT_NAME: ListenToMeWatch
        MARKETING_VERSION: "<same as ListenToMeIOS>"
        CURRENT_PROJECT_VERSION: "<same as ListenToMeIOS>"
        INFOPLIST_FILE: Watch/Info.plist        # CFBundleVersion = $(CURRENT_PROJECT_VERSION), like iOS
        GENERATE_INFOPLIST_FILE: NO
        DEVELOPMENT_TEAM: T32FW7PZ3S
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

`ListenToMeIOS` gains `- target: ListenToMeWatch` (embed: true). XcodeGen puts it in "Embed Watch
Content" (F15).

**Until the release train for slices 1–3 (decision 4),** that dependency lives in an XcodeGen
`include` enabled only by `WATCH_EMBED=YES`. Otherwise any unrelated iOS train cut from `main` after
Slice 1 merges would ship the watch app early. The default build, and so `make ios-archive`, embeds
nothing, and the TestFlight helper refuses an archive that contains a watch app. Device testing
uses `WATCH_EMBED=YES make gen`. The release-prep change makes the embed permanent. A scratch
project confirmed that the include appends to the existing dependencies and toggles "Embed Watch
Content".

`Watch/Info.plist` carries:

- `WKApplication` = true
- `WKCompanionAppBundleIdentifier` = `com.tomwu.ListenToMe.ios`
- `WKRunsIndependentlyOfCompanionApp` = false. The app is *dependent* (F12) because nothing on it
  works without the phone app, which does the transcribing.
- `NSMicrophoneUsageDescription`: "ListenToMe records on your Apple Watch and sends the audio only to
  your paired iPhone, where it is transcribed on-device." Slice 3 only.
- `UIBackgroundModes` = `[audio]`. Slice 3 only. Approved for the watch target only (decision 2).

**No WatchKit extension target.** The brief mentions "watch app + extension", which describes the
pre-Xcode 14 two-target layout. Current Xcode adds a watch app to an existing iOS app with one
"App" template ([setup guide](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)),
and XcodeGen embeds that single target (F15). A scratch project confirms it builds for the
simulator and the device SDK with no extension target (F19). The Slice 1 spike settled signed
archiving: `WATCH_EMBED=YES make ios-archive` (Xcode 27) succeeded with no extension target, placed
`ListenToMeIOS.app/Watch/ListenToMeWatch.app` (1.10.5 (27), `WKCompanionAppBundleIdentifier` set),
and automatic signing signed it as `com.tomwu.ListenToMe.ios.watchkitapp` with the team's existing
wildcard development profile. App Store export and upload of a watch archive stay unverified until
the release-prep change; that archive was not uploaded.

`.swiftlint.yml` `included` gains `Watch`. While the embed is gated, `make ios-build` also builds a
`ListenToMeWatch` scheme for `generic/platform=watchOS Simulator`. Once the embed is permanent, the
`ListenToMeIOS` scheme builds the watch app as a dependency and that extra step is removed (§6).

### 5.2 Shared code

| Code | Lives in | Used by | Tested by |
| --- | --- | --- | --- |
| `WatchLink`: message and metadata schema (`WatchCommand`, `PhoneRecorderStatus`, `WatchChunkMetadata`, `protocolVersion`), encoding to and from `[String: Any]` property lists, validation | `Sources/ListenToMeCore/WatchLink.swift` | iOS (`import ListenToMeCore`) and watch (file compiled in) | `swift test`, coverage floor |
| `WatchCaptureLedger`: the phone inbox manifest per recording: ordering, duplicates, completeness and gap detection, resume point, which chunks may be deleted | `Sources/ListenToMeCore/WatchCaptureLedger.swift` | iOS | `swift test` |
| `WatchCapturePolicy`: recording limits, chunk rotation, outbox reconciliation, retry delay | `Sources/ListenToMeCore/WatchCapturePolicy.swift` | watch (file compiled in) | `swift test` |
| `RemoteRecorderPolicy`: whether a watch command is accepted given phone state (`idle`, `preparing`, `recording`, `stopping`, foreground or not), and the reply text | `Sources/ListenToMeCore` | iOS | `swift test` |
| `SessionArchive`, `SessionRecord`, `TranscriptSegment` | Core (tier 1, unchanged) | iOS only | existing |
| WCSession wrapper (`PhoneWatchLink`), watch inbox drain, file transcriber | `iOS/` | iOS | app-hosted unit tests with a fake link (`ListenToMeIOSUnitTests`) |
| Watch UI, `WatchRecorder` (AVAudioEngine → AAC chunks), `WatchLinkClient` | `Watch/` | watch | thin; physical-device acceptance |

The watch target compiles **only `WatchLink.swift` and `WatchCapturePolicy.swift`** from Core. It does not link the whole package, which
declares only macOS and iOS platforms and contains AppKit and UIKit code. Both files must therefore
import only Foundation. Their logic is plain values, so they stay under the package's coverage
floor.

Alternative, rejected for now: add `.watchOS(.v26)` to `Package.swift` and link `ListenToMeCore`.
This only becomes worth it if the watch ever needs more of the core.

### 5.3 Slice 1 — remote control

```
Watch app (foreground)                         iPhone app
  tap Start ──sendMessage {v,cmd:"start"}──▶   PhoneWatchLink → RemoteRecorderPolicy
                                                 foreground & idle → MobileSession.start()
                                                 background        → reply .openPhoneApp (mic untouched)
            ◀──reply {v,status,elapsed,title}──
            ◀──updateApplicationContext(status) on every MobileSession.state change
```

- **Commands:** `start`, `stop` and `status`. Nothing else. Notes, bookmarks and titles are out of
  scope.
- **Replies:** `accepted(status)`, `openPhoneApp`, `busy(reason)` (for example "Generating a
  summary" or "Stopping"), `unsupportedVersion`.
- **The phone publishes state** (`idle`, `preparing`, `recording`, `stopping`, the start date, the
  title and the last `StopReason`) through `updateApplicationContext` from `MobileSession.state`'s
  `didSet`, so the watch shows the truth when it next opens. Only the title and state cross. No
  transcript text goes to the watch.
- If the phone app moves to the background while recording, the existing behavior applies:
  recording stops and saves, and the reason is `.background`. The watch then shows "Stopped:
  ListenToMe left the foreground on iPhone".
- **Unreachable phone** (out of range, or the app not running and not wakeable): the watch says
  "iPhone not reachable" and offers nothing else in Slice 1.

### 5.4 Slice 3 — watch-microphone capture

**Recorder.** An `AVAudioEngine` input tap writes **AAC-LC, mono, 16 kHz, about 32 kbps** into
`AVAudioFile` chunks (U3). That is about 14 MB per hour, versus about 115 MB per hour for 16-bit
PCM. A new chunk starts every **5 minutes** (about 1.2 MB) at a buffer boundary, so there is no gap.

Short chunks bound the loss from a crash or battery death to one chunk. They also let transfer
start while recording continues, and they keep every transfer small (U1).

**Session.** `AVAudioSession` category `.record`, then activation, all while the app is in the
foreground. The audio background mode keeps it running with the wrist down (F3, F5).

**Limits** (decision 5):

- Do not start below 20% battery or below 200 MB free storage.
- Stop and save at 10% battery.
- Hard cap of 3 hours per recording.
- Each limit shows its reason and plays a haptic.

**Interruptions.** A call or Siri stops the recording, closes the current chunk as the last one,
and says why. Per F5 the recording cannot resume by itself. The user taps **Continue**, which
appends new chunks to the same recording ID with a wall-clock offset. This mirrors the phone's "tap
Listen to continue".

**Wire format.** Each finished chunk goes through `transferFile(url, metadata:)` with this metadata:

```
{ v: 1, recordingID: UUID, index: Int, startOffset: Double (s since recording start),
  duration: Double, isLast: Bool, startedAt: Date, watchBuild: String }
```

The phone never uses a file name or path from the metadata. It names stored files itself, as
`<recordingID>/<index>.m4a`. It validates the ranges: index under 1,000, duration under 600 s, file
size under 10 MB.

**Watch outbox.** Unsent chunks live in `Application Support/Outbox/<recordingID>/`. At launch, the
outbox is reconciled against `outstandingFileTransfers`, and anything neither delivered nor queued
is queued again. A chunk is deleted only after `didFinish` reports success. A chunk file that was
never finalized, because the app was killed mid-chunk, is discarded and the recording is marked
"ended unexpectedly". The loss is at most 5 minutes.

### 5.5 How a watch capture becomes a normal conversation (Slices 2 and 3)

1. **Receive** (any app state). `session(_:didReceive:)` moves the file synchronously (F8) into
   `Application Support/WatchInbox/<recordingID>/<index>.m4a` and updates that recording's
   `manifest.json` (a `WatchCaptureLedger` value). Duplicate deliveries of the same
   (`recordingID`, `index`) are no-ops. Delivery can wake the app in the background, so this step
   only files the bytes. It never starts audio or transcription.
2. **Drain** (foreground only). `MobileSession.importWatchInbox()` runs next to
   `importSharedInbox()`: on `.active` and when the session stops being busy. It **does not run
   while the phone is recording or preparing** (F14), and it never switches the conversation that
   is open.
3. **Transcribe.** For each recording, it creates or reopens the conversation:
   - `SessionRecord.sourceImportID` = `"watch:<recordingID>"`. This is the share-import idempotency
     key, reused.
   - Title "Apple Watch · <start time>".
   - Segments with `source: .you` and `speakerName: "Apple Watch"`.

   The language is the phone's **Transcription → Language** at the time the drain runs
   (decision 7). Chunks are fed **in index order into one `SpeechAnalyzer` session** as buffers carrying
   `bufferStartTime = startOffset` (F14), so words that span a chunk boundary are not cut. The
   segments from each chunk are appended and the archive is saved. Only then is that chunk's audio
   deleted and the chunk marked transcribed in the manifest. A drain that is interrupted by
   backgrounding or by the user starting a live recording resumes at the first chunk not yet
   transcribed. Only that resume point can split a word.
4. **Complete.** When the last chunk is transcribed, the inbox folder is removed, History shows the
   conversation with a "From Apple Watch" note, and a status message says so. The open conversation
   is not switched, and no notification is posted (decisions 6 and 8). The conversation then
   behaves like any other: search, Summary, Quick, Deep, export, delete. Its lines keep the
   "Apple Watch" label: #180's speaker identification does not run on them, never relabels them, and
   prompts read them as "You" (decision 11; speaker labels for watch recordings are
   [#192](https://github.com/tomqwu/ListenToMe/issues/192)).
5. **Gaps.** If `isLast` has arrived but an index is still missing 24 hours later, the drain
   transcribes what it has and adds a visible note: "Part of this recording (about N min) did not
   arrive from Apple Watch."

This is iOS's first audio-*file* transcription path. Today `docs/IOS.md` tier 2 lists "Audio-file
import: No". Slice 2 builds the transcriber as `MobileFileTranscriber` behind a protocol, so it can
be tested with fixture `.m4a` files and no watch at all. It stays internal to watch captures
(decision 9), so that tier-2 row does not change.

### 5.6 Failure and retry summary

| Failure | Behavior |
| --- | --- |
| Phone unreachable (Slice 1) | The watch shows "iPhone not reachable". The command is not queued, so a stale Start can never fire later. |
| Phone app in background (Slice 1) | Reply `openPhoneApp`. The audio session is never activated. |
| Interruption on watch (Slice 3) | Stop, close the chunk, explain, offer Continue in the foreground (F5). |
| Watch killed mid-recording | Finalized chunks survive. At most one unfinalized chunk is lost, and the recording is marked "ended unexpectedly". |
| Transfer error | Re-queue with backoff, and reconcile at launch against `outstandingFileTransfers`. Delete only after success. |
| Phone out of range for hours | The system queues transfers (F7). The watch shows how many recordings are waiting. |
| Phone storage full or read-only | Treated as transient, the same as `MobileSession.isTransient` for the share inbox, and retried on the next foreground. |
| Corrupt chunk or failed transcription | Keep the audio, mark it failed in the manifest, and show a History row with Retry and Delete. It is never deleted silently. |
| Protocol version mismatch | The phone rejects unknown `v` with `unsupportedVersion`. The watch says to update both apps. They ship in one bundle, so this only happens mid-update. |

### 5.7 Versioning

- The watch app is part of the iOS app's bundle, so it **tracks the iOS app exactly**. In
  `project.yml`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are identical across
  `ListenToMeIOS`, `ListenToMeShare` and `ListenToMeWatch`. There is no separate watch version line
  or tag. The `ios-vX.Y.Z-buildN` tag covers it. U5 is the platform reason. Consistency is reason
  enough.
- `scripts/ios-testflight.sh` already asserts that the app and share extension match. It gains the
  same assertions for `Watch/ListenToMeWatch.app/Info.plist`: the bundle ID, `WKCompanionAppBundleIdentifier`,
  and that version and build equal the app's. `scripts/test-ios-testflight.py` gains matching cases.
- `WatchLink.protocolVersion` is separate from the build number. It changes only when the wire
  format does.
- `docs/IOS.md` → Version policy then reads "the app, share-extension and watch targets keep
  identical values".

---

## 6. CI and test impact

**Builds.** While the embed is gated (§5.1), `make ios-build` builds the `ListenToMeIOS` scheme and
then the `ListenToMeWatch` scheme for `generic/platform=watchOS Simulator`. Once the embed is
permanent, `make ios-build` (`-scheme ListenToMeIOS -destination 'generic/platform=iOS Simulator'`)
builds the embedded watch app as a dependency. Either way the `iOS 26 app build` CI check covers the
watch target with no workflow change. The runner's default Xcode 26.6 has the watchOS 26.5 SDK and
Simulator SDK (F16), and building needs no watchOS simulator runtime (F19). If a future runner image
lacks the SDK, add `xcodebuild -downloadPlatform watchOS` before `make ios-build` in the `ios` job,
or select an installed Xcode that has it. Expect CI time to rise somewhat.

The check's name stays the same, which matters because the branch ruleset requires it by name.
`make ios-archive` (`generic/platform=iOS`) archives the watch app for devices once the embed is on
(`WATCH_EMBED=YES` before the release-prep change), and needs automatic provisioning for
`com.tomwu.ListenToMe.ios.watchkitapp`. The first archive is a Slice 1 task.

**Unit-testable:**

- **Core, under `swift test` and the coverage floor:**
  - the `WatchLink` round trip and rejection of malformed or unknown-version dictionaries
  - every `RemoteRecorderPolicy` cell (state × foreground × command)
  - `WatchCaptureLedger`: chunk ordering, duplicates, gap detection after 24 h, completeness,
    retention decisions, and resume after a partial drain
- **iOS app-hosted, in `ListenToMeIOSUnitTests`:**
  - `MobileSession` handling remote start and stop with the existing `makeRecorder` injection and a
    fake `WatchLinking`, including a background command never calling the recorder
  - `importWatchInbox` idempotency through `sourceImportID`, using a temp inbox and a fake
    transcriber
  - `MobileFileTranscriber` on a short bundled fixture `.m4a`, which runs on device only, the same
    as live speech
- **Not unit-testable:** real `WCSession` delivery (F7, F8: the Simulator does not support it),
  watch background audio, battery and thermal behavior. A watchOS unit-test target is optional. The
  maintainer's Mac currently has no watchOS simulator runtime (F16), so `make validate-local` does
  not gain a watch test step unless one is installed.

**Physical-device acceptance** (paired iPhone and Apple Watch, both release builds from TestFlight
or Xcode). This list is added to `docs/IOS.md` in the release-prep change for the train that ships
slices 1–3 together (decision 4).

*Slice 1:*

1. With ListenToMe open on the iPhone, Start from the watch. The phone shows recording and the system
   microphone indicator, and the watch shows the elapsed time. Stop from the watch, then check that
   the conversation is saved.
2. With the iPhone app in the background or locked, Start from the watch. The watch says to open the
   app on the iPhone, and the microphone indicator never appears on the phone.
3. While recording, lock the phone. Recording stops with the background reason, and the watch shows
   it.
4. Turn Bluetooth off on the phone. The watch shows "iPhone not reachable", and nothing starts later
   when it reconnects.

*Slices 2 and 3:*

5. Record 10 minutes on the watch with the wrist down and the phone nearby. The system session icon
   is visible on the watch face. Open the phone app: the conversation appears with the correct text
   and order across chunk boundaries.
6. Record 30 minutes with the phone out of range, then return. The chunks transfer and transcribe on
   the next foreground. No audio remains in either inbox afterwards (check the app containers).
7. Take a call mid-recording on the watch. The recording stops with the reason, Continue appends to
   the same recording, and the conversation has both parts.
8. Start a live phone recording while a watch drain is pending. The drain waits and resumes after
   Stop.
9. Force-quit the watch app mid-recording. Earlier chunks still arrive, and the recording is marked
   "ended unexpectedly".
10. Record one hour. Record the battery drop on the watch (U2) and the transfer time, and note them
   in the PR.
11. Turn on **Exclude conversations from iCloud backup**. The watch inbox directory is excluded
   (`isExcludedFromBackup`).

---

## 7. Slices, effort and task breakdown

Estimates are engineering days for one implementer, including tests and doc updates, and excluding
review latency and the release train. Each slice is its own pull request, or a few. Each one merges
to `main` when its checks are green and stays **unreleased** (decision 4): slices 1–3 ride one
TestFlight train together, under the AGENTS.md rules, once watch-mic capture passes physical-device
acceptance. Until then `CHANGELOG.md` records the work under Unreleased, and user-facing docs
(`docs/IOS.md`, `docs/ios-privacy.md`, `docs/ios-support.md`, `README.md`, What to Test) change in
the release-prep change for that train. No slice is described as released until a train publishes
it.

### Slice 1 — target, link, remote control (3–4 days, plus 0.5 day on device)

1. **Spike (0.5 day):** a minimal `ListenToMeWatch` target in `project.yml`, `Watch/Info.plist` and
   an asset catalog. Confirm that `make ios-build` and `make ios-archive` succeed with no extension
   target, and that automatic signing provisions the `.watchkitapp` ID. Settle §5.1 U.
2. Core: `WatchLink` (commands, status, version) and `RemoteRecorderPolicy`, with tests.
3. iOS: `PhoneWatchLink` (`WCSession` activation at launch, the iOS-only
   `sessionDidBecomeInactive` / `sessionDidDeactivate` handling and reactivation, and a
   `WatchLinking` protocol for tests). Wire it to `MobileSession.start()` / `stop()`, with state
   publication via application context.
4. iOS unit tests: a background command never reaches the recorder, plus start, stop and the busy
   replies.
5. Watch: one SwiftUI screen (status, Start/Stop, elapsed time, unreachable and open-the-app
   states), `WatchLinkClient`, and completion of `WKWatchConnectivityRefreshBackgroundTask` (F11).
6. Release plumbing: matching versions on three targets, `scripts/ios-testflight.sh` and its test,
   and `docs/IOS-RELEASING.md`.
7. Docs: `CHANGELOG.md` (Unreleased) and `docs/IOS-RELEASING.md` (watch bundle row and checks).
   The `docs/IOS.md` watch section, acceptance steps 1–4, `README.md`, the support page and What to
   Test wait for the release-prep change (decision 4).

### Slice 2 — iPhone watch inbox and file transcription (3–4 days)

Slice 2 can be built and tested without watch capture.

1. Core: `WatchCaptureLedger` (manifest, ordering, duplicates, gaps, retention, resume point), with
   tests.
2. iOS: `MobileFileTranscriber` (one `SpeechAnalyzer` across ordered files with `bufferStartTime`)
   behind a protocol, plus a fixture-file device test.
3. iOS: the receive path (synchronous move, data protection, backup exclusion) and
   `importWatchInbox()` (foreground-only, waits for live recording, `sourceImportID`, saves each
   chunk before deleting its audio, failure rows in History).
4. iOS unit tests with a fake transcriber and a temp inbox.

### Slice 3 — watch microphone capture and transfer (5–7 days, plus 1 day on device)

1. **Spike (1 day):**
   - AAC writing from an `AVAudioEngine` tap on watchOS (U3)
   - a background recording with the wrist down for 30 minutes or more (F5)
   - free-storage and data-protection behavior (U4)
   - first battery and transfer numbers (U2)

   Go or no-go on the recorder design.
2. Watch: `WatchRecorder` (session, tap, 5-minute rotation, limits, interruption handling, Continue).
3. Watch: outbox, `transferFile` with metadata, reconciliation at launch, delete-on-success, and
   the pending count UI.
4. Watch: the recording UI (full-screen state, haptics, first-use consent reminder) and the
   microphone permission flow.
5. iOS: "Apple Watch is recording" from application context, and the History pending and failed
   rows.
6. Docs: `CHANGELOG.md` (Unreleased) in this slice. In the release-prep change for the train:
   `docs/ios-privacy.md` (transient audio, decision 3), the `docs/IOS.md` tier tables and acceptance
   steps 1–11, `README.md`, `docs/ios-support.md`, What to Test, and the App Store privacy answers
   re-checked.

### Slice 4 — optional polish (2–3 days)

- A complication or Smart Stack widget showing recording state, which opens the app.
- An App Intent, "Start ListenToMe recording", for the Action button and Siri on watch. Recording
  must still begin with the app in the foreground (F5).
- A watch-face Control.

---

## 8. Alternatives considered

- **An extended runtime session** to keep the watch recorder alive. Rejected: no session type
  matches conversation recording, and Apple says to choose by purpose (F6). Their 10–60 minute
  limits are also too short.
- **An `HKWorkoutSession`** as a keep-alive. Rejected: it misrepresents the app's purpose, writes
  workout data, and is likely to fail review.
- **Streaming live audio to the phone over `sendMessageData`** for live transcription. Rejected for
  v1: it needs both apps reachable and the phone app awake (F9), so it fails exactly when the phone
  "is not at hand". It also gains nothing over chunks for an after-the-fact transcript.
- **Transcribing on the watch.** Not possible with Apple's on-device engine (F1). Shipping
  WhisperKit to the watch contradicts tier 3 (no WhisperKit on mobile) and the watch's power budget.
- **An independent watch app** (F12). Rejected: it is useless without the phone's transcriber, and
  it would invite a standalone listing.

---

## 9. Decisions

The maintainer answered the ten open questions on 2026-10-22, in a
[comment on #181](https://github.com/tomqwu/ListenToMe/issues/181). Questions 5–10 took this
spec's recommended defaults. Each answer below is binding on the plan. Decision 11 was added during
implementation, on 2026-10-23.

1. **A watch companion is in scope.** The `docs/backlog.md` → "Intentionally out of scope" exclusion
   of "companion features" means Mac↔iOS sync or companion features only. A paired Apple Watch,
   with no server and the same user's devices, is in scope.
2. **Background recording on the watch is approved.** The watch target declares
   `UIBackgroundModes: [audio]`, so lowering the wrist does not end a recording. The iPhone app stays
   foreground-only and declares no background modes. The question as posed included the risk that
   App Review questions recording under the audio mode (F5); the approval is recorded on that basis.
3. **Transient raw audio is approved, with no "keep the audio" option.** Watch audio is stored on
   the watch and on the iPhone only until it is transcribed, then deleted automatically.
   `docs/ios-privacy.md` changes its "does not save raw microphone audio" wording in the release that
   ships watch-mic capture, not before.
4. **Slice 1 is not released alone.** Slices 1–3 merge to `main` unreleased and ship together on one
   release train when watch-mic capture (Slice 3) works. User-facing docs change in that train's
   release-prep change. `CHANGELOG.md` carries the work under Unreleased until then.
5. **Default limits:** a hard cap of 3 hours per recording, no start below 20% battery or below
   200 MB free storage, and stop and save at 10% battery.
6. **A finished watch conversation lands in History** with a status message. It does not switch the
   conversation that is open.
7. **Transcription language:** the phone's current **Transcription → Language** at transcription
   time. Nothing is chosen on the watch.
8. **No phone notification in v1.** History and the status message report a ready watch
   conversation, so the app gains no notification-permission prompt.
9. **`MobileFileTranscriber` stays internal to watch captures.** This spec made no explicit
   recommendation here; its slice plan exposes nothing to the user, and that is the default taken.
   `docs/IOS.md` tier 2 keeps "Audio-file import: No". A user-facing audio-file import would be its
   own issue.
10. **Minimum watchOS is 26.0**, matching the iOS floor. The spikes do not raise it.
11. **Watch conversations ship without speaker labels** (maintainer decision, 2026-10-23; plan Task 14
    deferred). #180 labels only the open conversation from a live buffer of at most the last 600 s,
    which does not fit a drained recording of up to 3 hours whose audio is deleted as it goes.
    Watch lines keep `speakerName: "Apple Watch"`, a speaker pass never relabels them, and prompts
    read them as "You" like "Microphone". File-based identification for watch recordings is
    [#192](https://github.com/tomqwu/ListenToMe/issues/192).
