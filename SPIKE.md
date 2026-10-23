# Spike: Apple Watch audio recorder (#181, plan Task 15)

Throwaway branch `spike/181-watch-audio`. **Never merged, no PR.** It answers U3, F5, U4 and U2 from
`docs/superpowers/specs/2026-10-22-apple-watch-recording-design.md` on real hardware before any
Slice 3 code is written (plan: `docs/superpowers/plans/2026-10-22-apple-watch-recording.md`, Task 15).

## What the branch adds

- `Watch/Spike/SpikeAudioRecorder.swift`: Task 15 Step 1 exactly. `.record` session,
  `AVAudioEngine` input tap, `AVAudioFile(forWriting:settings:)` with `kAudioFormatMPEG4AAC`,
  16 kHz, mono, 32 kbps, a new file every 300 s of audio. The tap's hardware format is converted to
  16 kHz mono Float32 first (`AVAudioFile.write(from:)` requires the file's processing format). Each
  new file gets `FileProtectionType.completeUntilFirstUserAuthentication` and the attribute is read
  back at creation and again after `close()`.
- `Watch/Spike/SpikeAudioView.swift`: the debug screen, reached from **DEBUG: Task 15 audio spike**
  under the Slice 1 remote on the watch. Shows elapsed time, chunk count, last chunk (index, seconds,
  bytes), protection read back (at create, after close, and a control file written with
  `.completeFileProtectionUntilFirstUserAuthentication`), free space (`volumeAvailableCapacityKey`
  and `systemFreeSize`), battery now and at start (`WKInterfaceDevice`), the last audio event, and a
  **Send last chunk to iPhone** button (`WCSession.transferFile`) with the delivery time measured on
  the watch clock (`session(_:didFinish:error:)`).
- `Watch/Info.plist`: `NSMicrophoneUsageDescription` (Global Constraints copy) and
  `UIBackgroundModes = [audio]`.
- `iOS/PhoneWatchLink.swift`: `session(_:didReceive:)` copies each received chunk to the iPhone app's
  `Documents/WatchSpike/`, appends a row to `Documents/WatchSpike/receipts.csv`
  (`receivedAt,name,bytes,sentAt,secondsSentToReceived`) and logs `[spike181] received …` with NSLog.

Every watch reading is also appended to the watch app's `Documents/spike-log.csv`, so numbers
survive the screen sleeping. Rows with kind `start`, `stop`, `chunk`, `transfer-sent` use the header
columns `time,kind,elapsedSeconds,battery,freeBytes,chunk,chunkSeconds,chunkBytes,protectionAtCreate,protectionAfterClose`.
`event` rows are `time,event,<text>` and `transfer-finished` rows are
`time,transfer-finished,<file>,<seconds on watch clock>,<ok or error>`.

Builds verified on this branch (simulator SDK, watchOS 27.0 SDK, deployment target 26.0, no
`#available` gates, so nothing newer than watchOS 26.0 is used): `WATCH_EMBED=YES make ios-build`,
`make watch-build`, and the watch target for `generic/platform=watchOS` with signing off.

## 0. Prerequisites

- iPhone on iOS 26 and its paired Apple Watch on watchOS 26, both with **Developer Mode** on
  (iPhone: Settings → Privacy & Security → Developer Mode; watch: Settings → Privacy & Security →
  Developer Mode; each restarts).
- Mac with Xcode 27, signed in to the Apple ID on team **T32FW7PZ3S** (Xcode → Settings → Accounts).
- iPhone connected by cable or on the same Wi-Fi, unlocked, "Trust This Computer" accepted. The watch
  appears in Xcode under Window → Devices and Simulators once the iPhone is connected and the watch is
  unlocked and near it (first time: keep both awake while Xcode prepares the watch, which can take
  several minutes).
- Watch charged above 90 % before the F5/U2 run, then off the charger.

## 1. Build and install

1. `git fetch origin && git checkout spike/181-watch-audio`
2. `WATCH_EMBED=YES make gen` (embeds the watch app in the iPhone app), then `open ListenToMe.xcodeproj`.
3. Signing, for each of the targets **ListenToMeIOS**, **ListenToMeShare** and **ListenToMeWatch**:
   Signing & Capabilities → "Automatically manage signing" on, Team **T32FW7PZ3S**. The project
   already sets `DEVELOPMENT_TEAM`; just confirm no red errors. Xcode registers
   `com.tomwu.ListenToMe.ios.watchkitapp` on first build if needed.
4. Scheme **ListenToMeIOS**, destination your iPhone, Product → Run (⌘R). This installs the iPhone app
   with the watch app embedded. Leave the iPhone app open.
5. Scheme **ListenToMeWatch**, destination your Apple Watch (listed as the watch name, or
   "<iPhone> via <Watch>"), Product → Run. The app opens on the watch. Allow the microphone prompt
   the first time you tap Start.
6. **Before any timed measurement, detach the debugger:** Product → Stop in Xcode, then open
   ListenToMe from the watch's app list. A debugger-attached app is not suspended normally, so F5 and
   U2 numbers are only valid with Xcode detached. Same for the iPhone app: stop it in Xcode and reopen
   it from the Home Screen.
7. On the watch: open ListenToMe, scroll down, tap **DEBUG: Task 15 audio spike**.

### Pulling files off the devices

- Watch: Xcode → Window → Devices and Simulators → select the **Apple Watch** → Installed Apps →
  ListenToMeWatch → "…" (gear) → **Download Container…**. In Finder, right-click the `.xcappdata` →
  Show Package Contents → `AppData/Documents/` holds `SpikeChunks/*.m4a`, `spike-log.csv` and
  `protection-control.txt`.
- iPhone: same, select the iPhone → ListenToMeIOS → Download Container… →
  `AppData/Documents/WatchSpike/` holds the received chunks and `receipts.csv`.
- If the watch container download is unavailable, send the chunk with **Send last chunk to iPhone**
  and take it from the iPhone container instead (same bytes); note that in the results.
- iPhone receipt log live: Console.app → select the iPhone → Start streaming → search `spike181`.

## 2. Measurements, in order

### Run A: U3, the AAC file plays and is 16 kHz mono (about 2 minutes)

1. On the spike screen tap **Start**. Say "ListenToMe spike test one, two, three", wait 20 s, tap
   **Stop**. Expect Chunks = 1 and Last chunk "#1 20 s, ~80000 B" (32 kbps ≈ 4 kB/s).
2. Download the watch container (above). In Terminal:
   ```sh
   cd "<path>/AppData/Documents/SpikeChunks"
   afinfo chunk-*-001.m4a
   afplay chunk-*-001.m4a
   ```
3. Pass when: `afinfo` shows `File type ID: m4af`, a data format of `1 ch, 16000 Hz, aac`, a bit rate
   around 32000, and an estimated duration close to the Last chunk seconds; `afplay` plays your
   words clearly, without silence, chipmunk speed or crackle.
4. Record the `afinfo` "Data format" line and "bit rate" line in the table.

### Run B: F5 background recording + U2 battery + rotation (35 minutes)

1. Watch off the charger, battery noted (screen "Battery"). iPhone nearby with the app open.
   Xcode detached (step 1.6).
2. Tap **Start**. Check the watch shows the system recording indicator (microphone indicator at the
   top of the screen / the app's session icon on the watch face once you leave the app).
3. Press the Digital Crown to go to the watch face. Confirm the session icon for ListenToMe is on the
   watch face; tap it once to confirm it returns to the app, then return to the face.
4. **Lower the wrist and leave the watch alone for at least 30 minutes** (normal wear, screen off,
   no other app opened). Don't take a call or use Siri: an interruption ends the recording (F5).
5. At 35 minutes raise the wrist. Before opening the app, note whether the session icon is still on
   the watch face. Open the app: note Elapsed, Chunks (expect 7 once past 35:00) and Event (expect empty
   or only "input format …"). Tap **Stop** (Chunks becomes 8).
6. Download the watch container and open `spike-log.csv`:
   - F5: one `chunk` row about every 300 s of wall-clock time, `chunkSeconds` ≈ 300.0 on every full
     chunk, no `INTERRUPTION` or `ENGINE` event rows.
   - Rotation gap: wall-clock time between chunk rows minus 300 s; and total `chunkSeconds` vs
     `elapsedSeconds` on the `stop` row (difference = audio lost).
   - U2 battery: `battery` on the `start` row minus `battery` on the 6th `chunk` row (= 30 min).
     Battery is 0.00–1.00; multiply by 100 for percent.
7. `afplay` a middle chunk (for example `-004.m4a`) and spot-check the chunk boundary: play the end of
   `-003` and start of `-004` and listen for a gap or click.

### Run C: U4, free space and data protection (1 minute, any time after Run A)

1. Open the spike screen and tap **Refresh storage**.
2. Record **Free (volCap)** (`volumeAvailableCapacityKey`, what Task 17 will use) and
   **Free (sysFree)** (`systemFreeSize`).
3. Record **Prot. create**, **Prot. closed** and **Prot. control**. Expected for all three:
   `CompleteUntilFirstUserAuthentication`. If "Prot. closed" differs from "Prot. create",
   `AVAudioFile` replaced the file on close and Task 18 must set the attribute after `close()`.
   "none" means watchOS does not report the class for that file.
4. Optional: lock the watch (cover the screen) with a recording running for 6 minutes, unlock, and
   confirm the chunk written while locked is in `spike-log.csv` with a normal size (a write blocked by
   protection would show a `write error` event).

### Run D: U2, transfer time for one full 300 s chunk (10 minutes)

1. iPhone app open in the foreground, iPhone unlocked and within 1 m of the watch. Note whether the
   iPhone is on Wi-Fi and whether Bluetooth is on (both normally on). Xcode detached.
2. On the watch tap **Start** and wait until Chunks = 1 and Last chunk shows "#1 300 s, … B"
   (expect about 1.2 MB). Keep recording.
3. Tap **Send last chunk to iPhone**. Wait for "Delivered in X s (watch clock)". This is the transfer
   time, measured on one clock from `transferFile` to `didFinish`.
4. Repeat step 3 twice more (same file), then tap **Stop**. Take the median of the three.
5. Cross-check on the iPhone: `receipts.csv` (or Console.app `spike181`) shows each receipt with
   `bytes` equal to the watch's Last chunk bytes. `secondsSentToReceived` compares two clocks and is
   only a sanity check.
6. Optional second condition: repeat steps 3–4 with the iPhone app in the background and the iPhone
   locked; note it separately.

## 3. Results (fill in, then paste on #181)

| ID | Measurement | Result | Pass? |
|----|-------------|--------|-------|
| — | Devices: iPhone model / iOS, watch model / watchOS, Xcode | | |
| U3 | `afinfo` data format line (expect `1 ch, 16000 Hz, aac`) | | |
| U3 | `afinfo` bit rate (expect ≈ 32000) | | |
| U3 | Chunk plays back clearly with `afplay` | | |
| U3 | Rotation: full chunks ≈ 300.0 s; audio lost per rotation (s); audible gap at boundary? | | |
| F5 | Recording continued 30+ min with the wrist down (elapsed at check / chunks) | | |
| F5 | Session icon on the watch face during recording (yes/no) | | |
| F5 | Interruption or engine events during the run (none expected) | | |
| U4 | Free space, `volumeAvailableCapacityKey` (bytes) | | |
| U4 | Free space, `systemFreeSize` (bytes) | | |
| U4 | Protection at create / after close / control file | | |
| U2 | Battery drop per 30 min of recording (percentage points) | | |
| U2 | Size of one 300 s chunk (bytes) | | |
| U2 | `transferFile` time for one 300 s chunk, watch clock (3 runs, median) | | |
| U2 | Same with the iPhone app backgrounded and locked (optional) | | |

## 4. Go / no-go (Task 15 Step 3, verbatim)

**Decide.** Go: continue with Task 16. No-go on AAC from the tap: switch Task 17 to
`AVAudioRecorder` with the same settings and accept a short gap at each rotation. No-go on
background recording: stop and raise it on #181 before writing Slice 3 code.

Applied to the table:

- **U3 fails** (no file, `write error`/`convert error` events, wrong format, or unplayable audio) →
  no-go on AAC from the tap: Task 17 uses `AVAudioRecorder` with the same settings.
- **F5 fails** (recording stopped or chunks stopped arriving with the wrist down, or an interruption
  with no cause) → no-go on background recording: stop and raise it on #181 before any Slice 3 code.
- **Otherwise go**: continue with Task 16. Record the U4 and U2 numbers on #181; the U4 protection
  result settles the attribute Task 18 sets (plan Task 18 Step 1).

## 5. Afterwards

- Delete ListenToMe from the watch (hold the icon → Delete) and reinstall the iPhone app from
  `main` if you use it daily.
- Back on `main`, run `make gen` (without `WATCH_EMBED`) so the project no longer embeds the watch.
- Leave this branch unmerged. Delete it once #181 records the results.
