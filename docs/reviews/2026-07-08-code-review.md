# ListenToMe Code Review — 2026-07-08

**Scope:** full codebase at `51ad703` (v1.2.0) — `Sources/ListenToMeCore`, `App/`, `Tests/`, build & release scripts, CI.
**Method:** ten parallel reviewers (eight subsystem shards + security/privacy and Swift-concurrency lenses), findings deduplicated, then every finding re-verified against the actual code. Verdicts: **CONFIRMED** = defect reproduced in the code with a reachable failure scenario; **PLAUSIBLE** = real weakness, but conditional on circumstances that couldn't be fully confirmed.

**Overall impression:** the codebase is in very good shape for its size — unusually careful race-window handling (generation guards in `SpeakerAudioBuffer`, run-ID guards in `MeetingSession`, drain-before-finalize teardown), a cleanly protocol-separated core that is genuinely unit-testable, and a 95% coverage gate in CI. The confirmed issues below are mostly edge-case reliability and a few privacy-promise gaps; none indicate structural problems.

**Counts:** 2 high · 16 medium · 21 low — 33 confirmed, 6 plausible.

---

## High

### H1. Local-first privacy filter misses `-cloud` model tags — CONFIRMED
`Sources/ListenToMeCore/ModelRanking.swift:77`

`roleDefaults` implements the documented promise that "an unpinned pane never silently sends transcripts to Ollama Cloud" by filtering `!$0.contains(":cloud")`. Ollama's cloud catalog also uses tags where `-cloud` is a suffix of the tag rather than the whole tag (e.g. `gpt-oss:120b-cloud`, `qwen3-coder:480b-cloud`). Those pass the filter, count as "local", and can be auto-assigned to a pane — after which live meeting transcripts are sent to the cloud without the user picking a cloud model.

*Failure scenario:* user signs into Ollama with both `llama3.2:3b` and `gpt-oss:120b-cloud` available; auto-defaults rank the 120b model heaviest and assign it to Deep; the next Deep answer ships the transcript to ollama.com.
*Fix:* filter on the tag portion: split on `":"` and reject tags equal to `cloud` **or ending in `-cloud`** (or query `/api/show` for the `remote` property).

### H2. Microphone channel dies silently on audio-device change — CONFIRMED
`App/DualChannelCapture.swift:74-82`

`startMic()` installs a tap using the input node's format at start time and never observes `.AVAudioEngineConfigurationChange`. When the default input device changes mid-session (AirPods connect/disconnect, dock/undock), AVAudioEngine stops or reconfigures; the tap stops delivering buffers and nothing restarts the engine or informs the user. The "You" channel goes silent while the UI still shows recording.

*Failure scenario:* user starts a meeting on the built-in mic, AirPods auto-connect a minute later → the rest of the meeting has no "You" transcript, with no error shown.
*Fix:* observe `AVAudioEngineConfigurationChange`, re-install the tap with the new input format and restart the engine; surface a transient warning if restart fails.

---

## Medium

### M1. Ollama in-band stream errors are swallowed — CONFIRMED
`Sources/ListenToMeCore/OllamaProvider.swift:58-64`

Ollama can return HTTP 200 and then emit `{"error": "..."}` as an NDJSON line (e.g. model OOM, context overflow). `OllamaParser.delta` returns nil for such lines and `isDone` is false, so the stream just ends. The pane shows an empty (or truncated) response with no error, unlike the HTTP-status path which surfaces a ⚠️ message.
*Fix:* detect an `error` key in the parsed object and `finish(throwing:)`.

### M2. Second audio import during teardown of the first is silently dropped — CONFIRMED
`Sources/ListenToMeCore/MeetingSession.swift:227`, `App/MeetingView.swift:494-499`

`importAudioFile` cancels `importTask` and immediately starts a new `transcribeAudio`. The cancelled run only clears `isTranscribingFile` in its `defer` after finishing/draining its transcriber, so the new call's `guard !isTranscribingFile` fails and returns — silently. The user picks a file and nothing happens.
*Fix:* have `transcribeAudio` await the previous run's teardown (like `start()` awaits `stopDrain`) instead of guarding re-entry away, or surface "still finishing previous import".

### M3. "Rolling summary" forgets everything outside the last 4,000 characters — CONFIRMED
`Sources/ListenToMeCore/MeetingSession.swift:358`, `Prompt.swift:175-190`, `ContextEngine.swift:12`

Listener refreshes call `buildContext` with the default `maxChars: 4000` and `buildListener` ignores the `summary` field entirely, so each "rolling summary of what has been discussed so far" is computed only from the last ~4k characters of transcript. In an hour-long meeting the summary silently loses the first 50+ minutes; Quick/Deep grounding (`lastCompletedListenerSummary`) inherits the same blind spot.
*Fix:* feed the previous completed summary into `buildListener` (true rolling summarization) or give the listener the recap-sized budget.

### M4. Prompt assembly has no delimiting against transcript/reference injection — CONFIRMED
`Sources/ListenToMeCore/Prompt.swift:131-149`

Transcript text (spoken by remote participants), calendar-invite notes, and attached file contents are concatenated raw into the user message. Any of these can contain instruction-like text ("ignore previous instructions and…"), which the model can't distinguish from the app's own instruction line appended at the end. For an app whose output the user may read aloud in a meeting, that's a real manipulation channel.
*Fix:* wrap untrusted sections in clearly labeled fenced delimiters and add a system-prompt line that content inside them is data, not instructions. (Inherent-risk caveat: this hardens, it can't fully prevent.)

### M5. `installTap` crashes with an uncatchable exception when no input device exists — CONFIRMED
`App/DualChannelCapture.swift:74-81`

On a Mac with no usable input device (Mac mini/Studio with nothing plugged in), `inputNode.outputFormat(forBus: 0)` returns a 0 Hz/0-channel format and `installTap` raises an Objective-C `NSException` that Swift's `try` cannot catch — the app crashes on Listen instead of showing the error path that `try engine.start()` would have produced.
*Fix:* validate `format.sampleRate > 0 && format.channelCount > 0` before installing the tap and throw a descriptive error.

### M6. SpeechAnalyzer pipeline (incl. model download) is built on the feed path — CONFIRMED
`App/SpeechAnalyzerTranscriber.swift:26-45, 58-98`

The first `feed` for each source runs `makePipeline`, which can `downloadAndInstall()` speech model assets — potentially minutes — while the capture pump is blocked awaiting `feed`. The capture stream buffers only the newest 64 chunks (`bufferingNewest(64)` in `DualChannelCapture`), so live audio from the start of the meeting is silently discarded. If `makePipeline` fails (`bestAvailableAudioFormat` nil), `feed` returns nil and retries the whole setup on *every subsequent chunk* with no failure latch.
*Fix:* kick off pipeline setup eagerly at transcriber creation (or buffer fed audio during setup), and latch a failed setup with a surfaced error instead of per-chunk retries.

### M7. SCStream created with `delegate: nil` — system-audio death is undetectable — CONFIRMED
`App/DualChannelCapture.swift:98`

Without an `SCStreamDelegate`, `stream(_:didStopWithError:)` is never received. If macOS stops the capture (permission revoked mid-session, display disconnect, WindowServer hiccup), the "Others" channel goes silent with no log, no retry, no UI signal — in a meeting app whose main job is transcribing the other side.
*Fix:* pass a delegate, log the stop error, and either attempt one restart or surface "system audio stopped".

### M8. SFSpeechRecognizer callbacks carry no task identity — CONFIRMED
`App/SpeechRecognizerTranscriber.swift:85-101, 107-135`

The recognition-task callback captures only `source`. `taskEnded` replaces `states[source]` with a fresh task, but a late callback from the superseded task (a trailing error such as a cancellation, which Speech commonly delivers after the final result) then runs `taskFailed(source)` and nils out the *new* state — dropping its request and any replayed pending audio; stale partials from the old task can also overwrite the new task's output.
*Fix:* capture the `SourceState` (or an ID) in the callback and ignore callbacks whose state is no longer `states[source]`.

### M9. Model list silently empties when capability probes fail — CONFIRMED
`App/OllamaModels.swift:30-35`

`isChatCapable` returns `false` on *any* failure: timeout, transient network error, or an older Ollama server whose `/api/show` has no `capabilities` field. `chatModels` then filters every model out, and `reloadAndHealModels` un-pins the user's selections against an empty list. An older-but-working Ollama shows "no models" with no hint why.
*Fix:* distinguish "probe failed" from "not chat-capable" — treat a missing `capabilities` field or transport error as capable-by-default (or keep the previous list on probe failure).

### M10. Corrupt `sessions.json` is silently destroyed on the next save — CONFIRMED
`App/SessionStore.swift:29-44`

`all()` maps any decode failure to `[]`; `add()` then writes the new single-record array over the file. One bad byte (or a future schema change without migration) erases the user's entire saved-meeting history without any prompt or backup.
*Fix:* on decode failure, rename the corrupt file aside (e.g. `sessions.json.corrupt-<date>`) before writing fresh, and log/surface it.

### M11. Search sheet re-reads and re-decodes all sessions on every parent invalidation — CONFIRMED
`App/SessionSearchView.swift:16-24`

`SessionSearchView.init` runs `store.all()` (full file read + JSON decode of up to 200 transcripts) to seed `@State`. While the sheet is open, every `MeetingView` body re-evaluation (once per streamed LLM token during recording) re-runs the sheet content closure and therefore this init on the main thread; the freshly-decoded value is discarded because `@State` keeps its first value. Additionally `results` (a computed property running `SessionSearch.search`) is evaluated twice per body pass (`results.isEmpty` + `List(results)`).
*Fix:* load in `.task`/`onAppear` instead of `init`, and bind `results` once per body evaluation (`let results = ...`).

### M12. App dependencies are unpinned — no committed lockfile — CONFIRMED
`project.yml:12`, `.gitignore`

WhisperKit and FluidAudio are declared with `from:` ranges, and the only `Package.resolved` lives inside the gitignored `*.xcodeproj`. No lockfile is committed, so two checkouts can build different dependency versions; a bad upstream minor release breaks the build/app with no way to bisect.
*Fix:* commit the workspace `Package.resolved` (un-ignore that path) or pin `exactVersion` in `project.yml`.

### M13–M15. Test-suite blind spots — CONFIRMED
- **M13** `Tests/ListenToMeCoreTests/MeetingSessionTests.swift:183-208` — the three negative proactive tests assert `quickSuggestion == ""` immediately after `ingest`. Even if the guard under test were deleted, the spawned response task wouldn't have run yet, so the assertion still passes: the tests cannot fail. Await a settle (`waitForResponse(.quick)` + yields) before asserting.
- **M14** `Tests/ListenToMeCoreTests/Mocks.swift:5-31` — no mock provider can throw, so `MeetingSession.run`'s error path (the ⚠️ output, `CancellationError` suppression, generation-guarded error display) has zero coverage despite being user-visible behavior.
- **M15** `Tests/ListenToMeCoreTests/Mocks.swift:73` — `MockCapture.start()` can't throw, so `start()`'s capture-failure rollback (`isRunning=false`, capture/transcriber cleanup, rethrow) is untested.

---

## Low

### L1. `"mini"` marker prefix-matches `"minimax"` — CONFIRMED
`Sources/ListenToMeCore/ModelRanking.swift:36,50` — `hasMarker` uses `hasPrefix`, so `minimax-m3` scores −30 ("light") and matches `fastPatterns`, letting a frontier-scale MiniMax model be auto-picked for Quick/Listener. Use exact-token match for `mini` (or add `minimax` to the exception list).

### L2. Default 60 s URLSession timeout kills cold model loads — CONFIRMED
`Sources/ListenToMeCore/OllamaProvider.swift:81-88` — `URLSession.shared`'s 60 s request timeout applies while Ollama loads a large model before the first byte; the stream dies with a timeout error. Use a session/request with a longer `timeoutIntervalForRequest` for streaming chat.

### L3. Stale trailing listener refresh clears the new run's `listenerRefreshPending` — CONFIRMED
`Sources/ListenToMeCore/MeetingSession.swift:366-371` — `fireTrailingListenerRefresh` resets the flag *before* the `runID` guard, so a stale cross-run task un-arms the current window and allows a duplicate trailing refresh (an extra LLM call). Move the flag reset after the guard, or key the flag by run.

### L4. Single `partial` slot is shared by both speakers — CONFIRMED
`Sources/ListenToMeCore/ConversationStore.swift:10-21` — mic and system-audio partials overwrite each other, and a final from one source clears the other's live partial. Display-only (finals are always appended), but the live line visibly flickers between speakers during crosstalk. Track one partial per `SpeakerSource`.

### L5. Search tokenizer only splits on space/`\n` — CONFIRMED
`Sources/ListenToMeCore/SessionSearch.swift:21` — a pasted query with a tab or CRLF keeps `\t`/`\r` inside a term and returns zero matches despite the doc-comment's "whitespace-split" contract. Split on `.whitespacesAndNewlines`.

### L6. `finish()` waits at most 3 s for final recognition — CONFIRMED
`App/SpeechRecognizerTranscriber.swift:54-63` — Stop polls 30×100 ms for `done`; a slower finalization means the last utterance never reaches the store even though `stopAndWait` promises drain-before-save. Consider a longer/adaptive deadline or awaiting the final callback.

### L7. Mid-file read error treated as EOF — CONFIRMED
`App/AudioFileReader.swift:42` — `catch { return nil }` on `AVAudioFile.read` makes a decode error at minute 3 of a 60-minute import look like a successful (truncated) transcription. Distinguish error from EOF and surface it.

### L8. Synchronous Keychain read on every root body evaluation — CONFIRMED
`App/MeetingView.swift:199` — `CommandCenterFooter(cloudActive: Self.ollamaKey() != nil)` calls `SecItemCopyMatching` (an IPC round-trip to securityd) once per body pass, i.e. per streamed token while any pane streams. Cache the key/route in `@State` and refresh on settings/onboarding dismiss.

### L9. Listen-cancelled-during-start leaves stale UI state — CONFIRMED
`App/MeetingView.swift:322-335` — after `try await session.start()` returns, the code doesn't re-check `wantsCapture`; a Stop pressed during startup leaves `recordingStartedAt` set and `anchorDiarizationRun()` run for a dead session. Cosmetic (indicator/timer gate on `session.isRunning`), but re-check `wantsCapture` after the await.

### L10. Heading preprocessing emits invalid emphasis on trailing whitespace — CONFIRMED
`App/MarkdownText.swift:96-98` — `# Title ` becomes `**Title **`, which the inline parser renders as literal asterisks; visible transiently while a heading streams token-by-token. Trim the heading text before wrapping.

### L11. Symlink bypasses the reference-file size cap — CONFIRMED
`App/FileContextLoader.swift:55-57` — for a directly-attached symlink, `attributesOfItem` returns the *link's* size (bytes) while `String(contentsOf:)` follows it, so a symlink to a multi-GB `.log` passes the 200 KB cap and is read whole into memory (the folder walk correctly skips symlinks; direct attachment doesn't). Resolve `URL.resolvingSymlinksInPath()` before the size check, or check via `resourceValues(.fileSizeKey)` on the resolved target.

### L12. Overlapping calendar events pick the wrong meeting — CONFIRMED
`App/CalendarService.swift:59-64` — among in-progress events the *earliest-started* wins, so a 9-5 "work block" (not all-day) or the previous back-to-back meeting beats the standup that just started. Prefer the most-recently-started in-progress event.

### L13. `xcode-select` failure is swallowed in CI — CONFIRMED
`.github/workflows/ci.yml:21` — `sudo xcode-select -s /Applications/Xcode_16.app || true` means the Swift-6 toolchain pin silently no-ops if that path doesn't exist on the runner image; the gate then runs on whatever default Xcode ships. Drop `|| true` (or select by `ls /Applications/Xcode_16*` with a hard failure).

### L14. Nested-code signing order can invalidate framework seals — CONFIRMED
`scripts/release.sh:105-112` — `find` prints a `.framework` before the `.dylib`s nested inside it (pre-order), so the framework is signed first and any nested dylib signed afterwards invalidates the framework's seal; notarization would then fail. Add `-depth` to the `find` so contents sign before their containers.

### L15. Trailing-edge listener debounce has zero test coverage — CONFIRMED
`Tests/.../MeetingSessionTests.swift:11` (+ integration tests) — every session test uses `listenerDebounce: 0`, so the leading edge always fires and `listenerRefreshPending`/`fireTrailingListenerRefresh` (including its stale-run guard, see L3) never execute under test. Add a test with a controllable clock and nonzero debounce.

### L16. Exported Markdown doesn't escape segment text — PLAUSIBLE
`Sources/ListenToMeCore/SessionExporter.swift:28` — multi-line or Markdown-significant transcript text breaks the list structure / injects headings. ASR output rarely contains newlines or `#`, hence plausible rather than confirmed; cheap to harden by replacing newlines and escaping leading markers.

### L17. `CMSampleBufferCopyPCMDataIntoAudioBufferList` status ignored — PLAUSIBLE
`App/DualChannelCapture.swift:194` — a failed copy would emit an uninitialized buffer as audio. No known reproduction, but the status check is one line.

### L18. Audio-only SCStream leaves video capture at defaults — PLAUSIBLE
`App/DualChannelCapture.swift:92-96` — no `.screen` output is attached, but the stream still runs a video pipeline at default resolution/frame-rate; setting `width`/`height` small and `minimumFrameInterval` large is the documented pattern to cut WindowServer overhead for audio-only capture.

### L19. Orphanable NSEvent monitors on view re-init — PLAUSIBLE
`App/HotkeyMonitor.swift:27`, `App/MeetingView.swift:82` — `HotkeyMonitor` has no deinit cleanup and lives as a plain `let` in the view struct; if the root view is ever re-initialized without an `onDisappear`/`onAppear` cycle, the started monitors (retaining the old action closure) leak and the replacement instance's `stop()` can't remove them. Hard to trigger for a root view; add a `deinit { stop() }` and/or hold the monitor in `@State`.

### L20. `make e2e` passes if the test filter matches nothing — PLAUSIBLE
`Makefile:51` — `swift test --filter OllamaContractE2ETests` exits 0 when zero tests match, so a rename silently turns the e2e gate green-by-vacuity. Assert non-empty match (grep the `--list-tests` output first).

### L21. Release app-location fallback can package a stale build — PLAUSIBLE
`scripts/release.sh:90` — the `find`-based fallback searches all of `Build/Products` and could pick up an older app from a different configuration left in derived data. Scope the fallback to the `${USED_CONFIG}` directory.

---

## Refuted / intentional (for the record)

- `KeychainStore` omitting `kSecAttrAccessible` is documented as an intentional choice of the file-based login keychain (`App/KeychainStore.swift:5`).
- `DualChannelCapture.emit` yielding to a finished continuation after `stop()` is a documented no-op, not a leak (`App/DualChannelCapture.swift:130-133`).
- The `SpeakerAudioBuffer` resample-under-lock design looks heavyweight but is deliberate and correct (serializes the shared `AVAudioConverter` across restart races; per-chunk cost is small).

## Suggested priority

1. **H1 + H2** (privacy promise; mic dying silently) — small, high-value fixes.
2. **M1, M7, M8** — silent-failure trio in the audio/LLM pipeline; all three make the app look broken with no error.
3. **M2, M3, M5, M9, M10** — data-loss and crash edges.
4. Test gaps M13–M15 (they'd have caught several of the above), then the Low list opportunistically.
