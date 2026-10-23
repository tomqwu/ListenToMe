# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`, version 1.11.0 (28).

## What this app is for

**ListenToMe for iPhone and iPad is a personal capture and recall companion — not a port of the macOS
meeting copilot.** It records and transcribes what *this device's* microphone hears: an in-person
conversation, a lecture, an interview, a phone left on the table. It summarizes on-device by default
(Apple Intelligence, where the device supports it) and keeps every conversation local, searchable and
shareable.

**It is deliberately not a copilot for calls or video meetings.** iOS does not let an app capture
another app's audio, so the dual-channel "You / Others" experience — and everything built on knowing
which voice is the remote participant, such as proactive answers to a question someone else asked —
stays macOS-only. This is a platform boundary, not a backlog item: there is no planned iOS feature
that captures system or call audio. Recording is foreground-only (`iOS/Info.plist` declares no
`UIBackgroundModes`); backgrounding stops recording and saves the conversation.

Apple Watch recording ([#181](https://github.com/tomqwu/ListenToMe/issues/181)) is under design, see [the spec](superpowers/specs/2026-10-22-apple-watch-recording-design.md); the tiers below are unchanged until it ships.

## Parity with macOS

Three tiers. Tier 1 must move in lockstep, tier 2 may differ but every difference is written down
here, and tier 3 is not coming to iOS.

### Tier 1 — shared core: identical on both platforms, changed together

These types live in `Sources/ListenToMeCore` (plus `SharedPlatform/`, which both app targets compile).
A change to any of them is a change to *both* apps: update both call sites, both platforms' tests and
this table in the same PR, and never fork a copy into `App/` or `iOS/`.

| Shared code | macOS entry point | iOS entry point |
| --- | --- | --- |
| `LiveSummaryScheduler` — the Auto batching/wake/cancel contract | `MeetingSession`, `MeetingSession+AutomaticReviews` | `MobileSummaryScheduler` (a typealias, `iOS/MobileSummaryScheduler.swift`) |
| `QuickSummaryContext` — pieces, attributed transcript and `Notes: ` lines | `MeetingSession`, `AutomaticReviewCoordinator` | `MobileQuickContext` (a typealias, `iOS/MobileQuickContext.swift`) |
| `QuickSummaryReader` / `QuickSummaryDecision` — evaluation and its JSON envelope | `MeetingSession` | `MobileQuickReader` (a typealias, `iOS/MobileQuickReader.swift`) |
| `AutomaticReviewCoordinator` — queued Summary/Deep reviews, deadlines, manual completion | `MeetingSession` | `MobileSession.automaticReviews` |
| Prompt data fences and caps: `PromptData.notice`, `PromptData.block`, `PromptBudget` | `PromptBuilder` (`Prompt.swift`) | `MobileSummaryMode.instructions`, `MobileSession.summarize` |
| `SessionArchive` — the on-disk conversation format | `App/SessionStore.swift` | `iOS/MobileSession.swift` |
| Speaker identification: `SpeakerDiarizer` and `SpeakerAudioBuffer` (`SharedPlatform/`, FluidAudio), `SpeakerIdentityTracker`, `SpeakerLabeling`, `SpeakerStats`, `SpeakerAnalysisPolicy` | `App/MeetingView+Speakers.swift` | `MobileSpeakers`, `iOS/MobileSession+Speakers.swift`; iOS language detection (#197) reuses `SpeakerAudioBuffer` with a two-minute `maxSamples` cap |
| `SessionSearch` — History search and its matching rules | `App/SessionSearchView.swift`, `App/MeetingView.swift` | `MobileHistoryView` via `MobileSession` |
| `AppleIntelligenceProvider` (`SharedPlatform/`) — on-device transport and its failure wording | `App/MeetingView.swift` | `MobileSession`, `MobileAISettings` |
| `OllamaProvider`, `LLMRequest` / `ChatMessage`, `OllamaGenerationOptions` | `App/MeetingView.swift` | `MobileAISettings.client(for:)` |

The prompt *fences* are shared; the prompt *text* is not entirely. macOS assembles pane prompts with
`PromptBuilder`, iOS with `MobileSummaryMode.instructions`, and both append the same
`PromptData.notice`. Changing that notice, `PromptData.block` or a `PromptBudget` cap changes both.

### Tier 2 — platform-appropriate: may differ, every difference listed here

| Capability | macOS | iOS |
| --- | --- | --- |
| Capture | Microphone **and** the other participants' system audio via ScreenCaptureKit (`App/DualChannelCapture.swift`), labeled You / Others | This device's microphone only; lines are labeled **Microphone** unless speaker identification names them; foreground only |
| Default AI provider | Explicit AI mode — Local only, Apple Intelligence, Cloud, or AI off — defaulting to a local Ollama model | A fresh install uses **Apple Intelligence on-device** when it is available, otherwise falls back to Ollama and names the reason (`MobileAISettings.fallbackExplanation`) |
| Ollama endpoint | The local daemon (`localhost:11434`) or Ollama Cloud | Ollama Cloud, or a server you run and address yourself (`.local`/loopback for plain `http`); a saved cloud key is never sent to another host |
| Per-role models | A picker per pane in the status rail, over local and cloud models, auto-picked local-first (`ModelRanking`) | Settings → Model role for Summary / Quick / Deep (`MobileRoleModelView`), Ollama only; Flash models are reserved for Quick and correction and refused for Deep |
| Local-model enforcement | `ModelPrivacy` / `localOnly` verifies downloaded weights before every request | Not applicable — on-device here means Apple Intelligence; iOS reaches Ollama only over the network |
| Speaker identification | Optional on-device diarization of the Others channel (and optionally the microphone) with naming; line labels need WhisperKit timestamps | On by default, can be turned off (**Settings → Speakers → Identify speakers**): FluidAudio diarizes the one microphone on-device, lines become **Speaker 1, 2…** by SpeechAnalyzer's audio time ranges, and **Notes → Speakers** renames them. Trailing-window passes while recording plus a final pass on Stop, foreground only; a line no speaker covers for at least 30% of its length keeps **Microphone** |
| Presets and reference context | Use-case presets (`PresetCatalog`) and file/folder reference context (`ReferenceBuilder`, `FileContextLoader`) | Not today. Attachments instead: extracted text is appended to Notes, so it reaches the model inside `<transcript>`, not a `<reference>` block |
| Calendar import | **Load from Calendar** fills Context notes (`App/CalendarService.swift`); text is imported as written | **Import from Calendar** removes e-mail addresses and link passcodes first (`MeetingContext.redactingLinksAndAddresses`, `MobileCalendar.attendeeNames`) |
| Share-sheet import | — | Share extension plus an App Group inbox (`ShareExtension/`, `iOSShared/SharedInbox.swift`) |
| AI speech correction | — | Opt-in, over a Flash model on Ollama (`MobileTranscriptCorrector`) |
| Proactive Quick answers | Yes — needs a finalized question on the Others channel | No — there is no Others channel to detect one in |
| "What's New" | GitHub release notes and `CHANGELOG.md` | In-app, shown once per set of bundled notes (`MobileReleaseNotes`) |
| Storage protection | Plain atomic writes | Data protection (`completeUntilFirstUserAuthentication`) plus an optional backup exclusion (`PrivateStorage`) |
| Export | Markdown, PDF and recap | Markdown and readable text through the share sheet |
| Audio-file import | Yes (`App/AudioFileReader.swift`) | No |
| Languages | Transcription language **and** AI response language; the opt-in WhisperKit engine transcribes mixed languages | Transcription language only: **Automatic** (the default) detects the spoken language on the device from the first seconds of speech and switches once per recording, or a fixed language (#197) |
| Input | Global ⌘⇧Space hotkey and a Session menu | Touch UI; no hotkeys or menu bar |

### Tier 3 — out of scope for iOS

| Not in the iOS app | Why |
| --- | --- |
| System, call or other-app audio capture | iOS gives no app another app's audio. The dual-channel copilot is macOS-only by platform, not by ordering |
| Background recording | No `UIBackgroundModes`: backgrounding stops recording and saves |
| A local Ollama daemon and its downloaded-weight verification (`ModelPrivacy` / `localOnly`) | A phone does not run the Ollama daemon; on-device inference on iOS is Apple Intelligence |
| The WhisperKit transcription engine | SpeechAnalyzer is the only iOS transcription engine. WhisperKit is linked into the app target (not the share extension or the watch app) for spoken-language detection only (#197), and FluidAudio for speaker identification only |
| Mac↔iOS sync or a Mac companion mode | Out of scope product-wide — see [backlog](backlog.md) → "Intentionally out of scope" |

## Version policy

**The two apps keep independent version lines.** They are separate products in separate distribution
channels, and an iOS build number already accepted by App Store Connect can never be reused. A higher
iOS version does *not* mean the iPhone app is ahead of the Mac app; today macOS is 1.4.4 (14) and iOS
is 1.11.0 (28).

- **`MARKETING_VERSION`** (iOS, in `project.yml`): a **minor** bump for user-visible features, a
  **patch** bump for fixes.
- **`CURRENT_PROJECT_VERSION`** (iOS): increments monotonically on every upload and **never resets**
  when `MARKETING_VERSION` changes. The app and share-extension targets keep identical values.
- **One release per batch of work, not per fix** — the release trains in
  [AGENTS.md](../AGENTS.md) govern both platforms: at most one macOS release and one TestFlight
  build per day, never one release per merged pull request.
- **Tags:** `ios-vX.Y.Z-buildN` for iOS, `vX.Y.Z` for macOS. An iOS build is never published as the
  latest macOS release.
- **`CHANGELOG.md` carries both platforms**, newest first, interleaved by date.
- Do not bump the macOS version for an iOS-only release, or the reverse.

The archive, upload, tagging and verification steps themselves are not repeated here: follow
[IOS-RELEASING.md](IOS-RELEASING.md) for iOS, [RELEASING.md](RELEASING.md) for macOS, and
[AGENTS.md](../AGENTS.md) for the release workflow that governs both.

## iOS 1.11.0 (28)

Optional on-device speaker identification (#180), off by default in this build (on by default since #195, unreleased): **Settings → Speakers → Identify speakers** labels microphone lines **Speaker 1**, **Speaker 2**… with FluidAudio after the first pass about 20 seconds in, and **Notes → Speakers** renames a speaker across the saved conversation, History search and exports. The speaker models download once from `huggingface.co` and are excluded from iCloud and Finder backups; recording audio is held only in memory, bounded to about ten minutes. Stop returns at once and never starts the first model download. See the speaker-identification entry under [Included](#included) for the full behavior, and the privacy policy's new section in [ios-privacy.md](ios-privacy.md). The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.11.0.txt).

## iOS 1.10.5 (27)

App Store readiness: Settings → Privacy links the privacy policy and support pages (#145). History surfaces a dismissable note when a saved conversation file cannot be decoded (the file is quarantined, never deleted) and search now covers notes with diacritic- and width-insensitive matching (#120, #139). Prompts fence transcript, notes and reference text as data (#140). No recording-path changes on iOS in this build. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.5.txt).

## iOS 1.10.4 (26)

Papercuts batch (#138): What's New keyed on the bundled notes rather than the build number, with first installs seeding the acknowledgement; share-inbox drain deletes stale manifest-less folders after 24 hours and sets failed batches aside (also aged out after 24 hours) instead of blocking later imports; transcription language persisted; one long-lived URLSession per role; automatic model-catalog refresh gated on the Ollama provider plus a key or custom server, so an Apple Intelligence install never contacts ollama.com; conversation and attachment files written with device data protection and an optional iCloud-backup exclusion covering the share inbox; History search backed by the shared `SessionSearch`. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.4.txt).

## iOS 1.10.3 (25)

Recording lifecycle: interruptions, route changes and backgrounding no longer stop capture silently; the app states why it stopped and resumes after an interruption ends, and connecting a new microphone rebuilds capture instead of stalling. Notes and title edits are debounced and flushed when the app leaves the foreground. Calendar imports redact join-link secrets and e-mail addresses from the event body and location. Apple Intelligence manual Quick uses a prose prompt with mapped error messages and a per-conversation language check. Ollama HTTP errors surface the server's own message, and Apple Intelligence prompts are clamped to the on-device window with a visible notice. Automatic reviews survive notes typing, never overwrite a fresh manual Quick answer, and use a size-scaled deadline. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.3.txt).

## iOS 1.10.2 (24)

A fresh install now defaults to on-device Apple Intelligence, falling back to Ollama with a stated reason only where Apple Intelligence cannot run. A provider chosen in an earlier build is untouched. Settings gains an optional **Server URL** so Ollama requests — summaries, Quick, Deep and speech correction — can go to an Ollama server you run on your own network instead of ollama.com. Use the computer's `.local` name; no API key is needed, and a saved Ollama Cloud key is never sent to a server you entered. The destination host is shown in the status text. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.2.txt).

## Attributed summary input

Summary, Deep and Quick all read the transcript with speaker labels and the user's typed notes
marked as `Notes:`. Summaries can therefore attribute a question or a commitment instead of
reporting the owner as unstated, and never present a typed note as something that was said.

Local speech is labelled `You` in prompts, the same label macOS uses, even though the transcript and
the Markdown export display it as `Microphone`: a device name is not a participant, and the review
prompts are told never to invent names. Remote or diarized speakers keep their own label.

The label format and the `Notes:` marker are shared with macOS; the two platforms still assemble the
full-review source differently (chunking and provisional-speech handling).
See [the shared policy](SHARED-LIVE-SUMMARY.md#attributed-input-and-user-directives-for-automatic-output-144--ios-1102)
for the exact rule and the known differences.

## iOS 1.10.1 (23)

An in-app What’s New screen shows the installed version/build and recent changes after an update. Continue acknowledges that exact build; future launches go straight to the workspace. More → What’s New reopens the offline changelog. Large text scrolls independently of the pinned Continue button. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.1.txt).

Release notes live in `iOS/MobileReleaseNotes.swift`. Update its newest release entry when bumping the marketing version; an app-hosted test checks it against the installed bundle. The shown build number always comes from the bundle. This screen belongs to the app; Apple's TestFlight introduction remains managed by TestFlight.

What's New is gated on the newest bundled release — its version plus a digest of its own text — not on
the build number, so successive TestFlight builds that change no notes do not re-present the same
sheet; editing a bundled entry does. A first launch after install has nothing acknowledged yet: it
records the current notes and goes straight to the app instead of opening a full-screen "IN THIS
UPDATE" for software the user has never run. The newest bundled entry is the one badged
"IN THIS UPDATE", even on a hot-fix build whose version does not match it. Settings still shows the
exact installed `version (build)`.

## iOS 1.10.0 (22)

Auto now connects Quick evaluation to automatic Summary and Deep generation with the selected models. Medium/high recommendations run serially, coalesce pending context and preserve previous output on failure. Manual Generate takes priority and remains available after Stop. The UI describes event-triggered evaluation and shows full-review status. Quick allows enough bounded response room for GLM planning preambles, with a 30-second deadline; displayed recaps remain limited to three short bullets. See [the shared policy](SHARED-LIVE-SUMMARY.md#automatic-full-reviews-ios-1100) and [What to Test](../metadata/ios/en-CA/what-to-test-1.10.0.txt).

## iOS 1.8.0 (16)

Auto Quick Summary now uses an event-driven evaluator: completed speech and note changes enqueue
five-second batches, with no model polling during silence. Each read accumulates context and decides
whether to keep the displayed bullets or publish a meaningful update. Corrections send the previous
and current wording. Summary/Deep recommendations show a grounded reason and qualitative AI confidence;
they remain manual actions. Quick reads can run alongside a manual Summary or Deep response.

This release also stabilizes the transcript's reading position while new speech arrives. The history
view stays still while recording continues; Latest reveals the newest text and resumes following.

See [the scheduler's events, actions and tests](IOS-LIVE-SUMMARY-SCHEDULER.md). Calls have a 15-second
deadline; failures keep previous results and retry with backoff. Stop cancels pending reads, and manual
Refresh includes the stopped transcript. Automatic evaluation reads long input in bounded batches;
manual full-snapshot summaries retain their provider input limits. Working context is rebuilt from
original finalized text after reopening a conversation. Auto remains opt-in.

## iOS 1.7.0 (15)

Intelligent speech correction is optional and off by default. Tap the sparkles row in Live transcript,
or open Settings, then enable **Correct speech with AI** and select an API-listed Flash model.
The correction role is independent of Quick, Summary and Deep; it can also run alongside Apple
Intelligence summaries using your Ollama key. It sends only new completed phrases and up to 2,000
characters of nearby recognized speech. Notes, attachments and microphone audio are excluded.

Apple's live partial text appears immediately. A separate bounded queue checks finalized phrases,
with a 350 ms delay and a 12-second deadline per request. At most six phrases wait behind the active
request; under sustained overload the oldest waiting phrase stays as recognized. Phrases longer than
1,200 characters are kept unchanged. Failures never stop recording or replace the original; later
phrases are still checked. Turning correction off, changing its model/key, backgrounding or opening
another conversation cancels pending work. Stopping normally lets the final check finish.

Applied edits show **AI corrected**. Tap to compare the original and corrected wording or **Restore
original**. Both wording versions persist with the segment, and Markdown exports include an originals
section. Future summaries use the current transcript; existing summaries refresh only through their
normal manual/Auto updates. The model is instructed to preserve names, dates, numbers and negation;
local checks also reject number/negation changes and large rewrites. These checks are conservative
filters, not proof of accuracy. Review edits where wording matters.

The Cloud request uses streaming chat, `think: false`, temperature 0 and a small output budget.
[Ollama Cloud does not support schema-constrained output](https://docs.ollama.com/capabilities/structured-outputs),
so responses are parsed and validated locally. A complete final JSON object with exactly one text
field handles the GLM Cloud reasoning preambles observed with and without a closing think marker.
Trailing prose, malformed objects and partial JSON are rejected; reasoning is never shown.

## iOS 1.6.0 (14)

History has a search field over title, summary and transcript, using the same keyword ranking
(`SessionSearch`) as the Mac History sheet: every typed term must appear in the same conversation,
results are ordered by match count then recency, and an empty query is the full list. A query that
matches nothing shows the standard "no results" view; the saved conversations themselves are
untouched. Matching is case-, diacritic- and width-insensitive and splits the query on any
whitespace, so "cafe" finds "café" and "ai" finds full-width "ＡＩ"; notes (where share-sheet imports
land) are searched too, and whole-word matches rank above matches inside longer words. If a saved
conversation file cannot be decoded it is set aside as `<id>.json.corrupt-<timestamp>` and the rest of
History still lists, with a one-line note above the list. History uses native row actions: swipe right to Share, left to Delete, or touch and hold for both.
Sharing opens the system share sheet for the selected conversation without switching the active one.
Delete always asks for confirmation, including from the context menu; a full swipe cannot delete it.
VoiceOver exposes Share and Delete as custom actions. See [the interaction design and checks](IOS-NATIVE-INTERACTIONS.md).

Auto Quick Summary resumes at the remaining 15-second cooldown after an AI request finishes. Speech
received during a slow response is picked up as soon as the cooldown has elapsed, without another full
interval or a Refresh tap. Auto remains opt-in. Its panel shows off, waiting, updating, paused, up-to-date
and retry status, plus the actual error if generation fails. Failed updates keep the previous result.
The timer belongs to the recording session and continues when another workspace tab is selected.

## iOS 1.5.0 (13)

The waveform logo now appears in the workspace and Settings. A violet canvas, distinct accents for
transcript and each summary role, refined cards and a prominent recording button give the app a
consistent identity in light and dark mode. Empty states show what belongs in each panel. The compact
transcript, auto-follow behavior and independent model controls remain available. See the
[GUI review and design decisions](IOS-GUI-REVIEW-1.5.md).

## iOS 1.4.1 (12)

Live now gives more space to Quick Summary. The transcript takes about one-third of the reading
area, capped at 260 points, and follows the latest words as partial and final text arrive.
Scrolling back pauses following; scroll to the end or tap **Latest** to resume. Use the expand
icon to read the full transcript. Landscape and accessibility text sizes show a short latest-text
preview with the same expand action, keeping Quick Summary reachable in one scrolling column.

## iOS 1.4.0 (11)

The meeting workspace now has direct Live, Summary and Deep tabs on iPhone. Live keeps the transcript
above Quick Summary; iPad displays review beside the live conversation. A compact recording bar keeps
Notes close at hand. See [the design rationale](IOS-DESIGN.md).

Each summary shows its provider/model and opens that role's chooser. Quick Summary can use Flash;
Deep Summary requires a non-Flash model. Existing inherited Flash assignments are repaired using the
API catalog, while valid full-model choices are preserved. A fresh setup prefers Flash for Quick,
a full model for Summary and an available Pro variant for Deep. No Flash fallback is used for Deep.

## iOS 1.3.3 (10)

Use **More → Import from Calendar**, or the same action in **Notes**. Connect Calendar when prompted,
choose a date and event, preview the details, then tap **Import**. The app appends meeting context to
existing notes and names an untitled conversation after the event. It does not edit Calendar events.
Imported notes — the title, time, location, attendee names, the event's own notes and its link — become
part of your notes, and your notes are sent to the selected AI provider by every summary, including
Auto summary, and are included in **Share**. With Ollama selected that means they leave the device.
Two kinds of detail are therefore filtered out during import:

- **E-mail addresses.** Attendees are kept as display names only, as on macOS (an invitee with no
  display name is left out), and any address written in the event's location or body is removed.
- **The secret-bearing part of every link.** The event's own URL and any link inside its location or
  body keep scheme, host and path only; the query string, fragment and user info — where a join
  passcode such as `?pwd=…` or Teams' `?context=…` lives — are dropped.

Nothing else is filtered: the title, times, the event's body text, dial-in numbers and meeting IDs are
imported as written, so review the notes before summarizing if the invite contains anything you would
rather not send. Notes imported by an earlier version of the app are stored text like any other and may
still contain a passcode or an address — edit those notes if you want them gone.
Only calendars configured on this device are available; no direct server login is needed.

Reading existing events uses Apple's full Calendar access level and
[`NSCalendarsFullAccessUsageDescription`](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
Denied/restricted access and dates without events have distinct messages. Permissions are requested
only through Connect Calendar, and rechecked when returning from Settings.

## iOS 1.3.2 (9)

Fixes automatic Quick Summary for short transcripts and failed-request retries. The recording session
owns automatic updates, independently of the visible screen. Settings remains usable while listening
and offers separate Quick Summary, Summary, and Deep Think model pages with a cached API catalog.

## Included

- Foreground microphone transcription using Apple's on-device SpeechAnalyzer. Language assets
  download on first use. Unsupported device/language and permission errors are shown in the app.
  **Settings → Transcription → Language** is remembered across launches, so a language chosen for
  daily meetings is still selected after a relaunch instead of reverting to the device's. The list
  compares BCP-47 identifiers, so a device on `en_US` is offered "System (en_US)" once rather than
  also listing "English (US)".
- Automatic transcription language (#197), the default: **Settings → Transcription → Language →
  Automatic (default)**. A user who had already picked a language keeps it fixed after the update;
  everyone else starts in Automatic. SpeechAnalyzer needs one locale up front and cannot detect or
  switch languages, so a recording starts in the device's language and the app identifies the
  spoken language on the device with WhisperKit's multilingual **tiny** Whisper model (about 75 MB:
  73 MB of Core ML models and a 3 MB tokenizer). The model downloads once from `huggingface.co`,
  started by the first speech of a recording rather than at Start, into Application Support
  (`LanguageModels/`, excluded from iCloud and Finder backups); later launches load it from the
  device with no network request. No audio or text is sent anywhere. Recording never waits for it.
  While recording, the audio the transcriber accepts is copied into a 16 kHz buffer capped at two
  minutes (about 7.7 MB, in memory only). Once 8 seconds of speech have been heard (or 30 seconds
  have passed since the first speech), up to 30 seconds from just before the first speech are
  checked once. `LanguageDetectionPolicy` switches only when Whisper is at least 80% sure, the
  language differs from the one being transcribed, and SpeechTranscriber supports it; Whisper's
  "zh" (Mandarin) becomes zh-CN, or zh-TW on a device in Taiwan, Hong Kong or Macao, and never the
  Cantonese zh-HK model. To switch, the recorder installs the new locale's speech assets if needed
  while the old transcriber keeps running, then swaps the analyzer without stopping the microphone:
  audio arriving during the swap is parked and sent to the new analyzer, so none is lost. The new
  analyzer first hears the buffered recording from its start. Its lines for the audio before the
  switch are held back while the earlier lines stay on screen and on disk, and replace them in one
  step once it reaches live speech (or, if the recording stops first, replace only what the replay
  covered), so a crash or a failed replay never loses the early transcript. The unfinished line at the
  switch is kept as a line of its own. Offsets, speaker labels and later lines stay on one timeline.
  Past the two-minute buffer the switch cannot re-transcribe anything: the old analyzer then
  finalizes what it heard up to the switch, the new one continues the timeline, and the notice says
  "switched for new speech". Speech that starts after the two minutes is not checked (Status details
  says so). The status area shows "Detected Chinese · switched" with **Undo**, which pins the
  language the recording started in. While recording it switches back first, re-transcribing what
  is still buffered, and the notice stays until that has worked (a failure says to try again). While
  stopping, the tap waits for Stop to finish; after Stop it restores the lines the switch replaced,
  touching only that recording's own lines (Apple Watch lines and later recordings stay) and
  keeping the line that spans the switch. A recording that resumes the conversation, after a call or
  Stop and Listen, starts in the switched language and keeps the notice. A recording switches at most
  once; mid-recording code-switching is not handled yet (#199). Apple Intelligence's language check
  uses the switched language. If the model cannot be loaded (offline first use), recording
  continues in the starting language and the status line says language detection paused; the next
  recording tries again. A check that keeps the language releases the buffered audio at once.
  **Status details** on the Quick Summary pane lists the mode, the recording's language, the last
  check's result and the model state.
  Apple Watch recordings are transcribed in the device language under Automatic: detection runs on
  live recordings only (#200).
- Partial and final transcript text. Everyone picked up by the microphone is labeled **Microphone**
  unless speaker identification is on. Unfinalized text is retained and labeled accordingly.
- Speaker identification (#180), on by default since #195 (a stored choice to turn it off is kept):
  **Settings → Speakers → Identify speakers**. It runs on this device with FluidAudio, the same
  diarizer the Mac uses, and uses more battery while listening. Its speaker models download once
  from `huggingface.co` (model weights only — no audio or text is sent; the model folder is excluded
  from iCloud and Finder backups because it can be downloaded again) and are loaded before the first
  recording needs them: when the setting is turned on, when the app comes to the foreground with it
  on, and at Start — never from Stop and never in the background. Recording never waits for them;
  a failed download leaves the status line saying so, with **Retry**, and recording continues.
  **Settings → Speakers** shows the download, the ready state, or the failure with **Retry**. The
  status under the conversation title reads "Speaker labels on" once the models are ready; while
  they download, when labels are unavailable or the models are not loaded (both with **Retry**), or
  after a skipped pass, a speaker line appears below it (`MobileSpeakers.statusLineIsShown`). Ready
  and periodic-pass states add no line, so the workspace keeps its height. Status details lists the
  setting, whether the models are ready, the passes run and the last speaker error. UI-test launches
  substitute models that load at once and hear no voices (`LISTENTOME_SPEAKER_MODELS_FIXTURE`, DEBUG
  simulator builds only), and the unit-test host substitutes models that never load, so no test
  downloads them. While recording, the audio the transcriber
  accepted is copied into a 16 kHz buffer; about every 20 seconds (never sooner than the previous
  pass took) a pass re-analyzes only the audio since the last one plus a one-minute overlap
  (`SpeakerAnalysisPolicy`). Stop returns at once; a final pass then labels the last words while the
  app stays open, queued behind any pass still running, and its result is dropped if a
  new recording or another conversation has started. The final pass is skipped while the models have
  not loaded yet, so Stop never starts or waits for the download; with the models ready, a recording
  shorter than the first periodic pass is labeled at Stop (#195). On every periodic tick, audio no later window can reach is released, so
  at most ten minutes (about 38 MB) is held even when passes keep failing, and only the last minute
  while the models are unavailable.
  No audio is saved. Lines are matched to speakers by SpeechAnalyzer's audio time ranges and become
  **Speaker 1**, **Speaker 2**…; a line no speaker covers for at least 30% of its length keeps
  **Microphone**. **Notes → Speakers** renames a speaker everywhere: the saved conversation, the
  transcript in History, search and exports all use the name. Renaming or relabeling starts no AI
  work, and Auto summaries do not re-read lines whose only change is the label; summaries pick the
  names up the next time they are generated. Prompts keep **Microphone** lines as `You` and pass
  named speakers through unchanged. If the models cannot be loaded (offline first use, a blocked
  host), identification pauses with the reason in the status area and no further passes run until
  you tap **Retry** or start a new recording. Limits: overlapping speech and short utterances are
  often left as **Microphone** or attributed to whoever spoke longest; a voice is not recognized
  across recordings, so after Stop/Listen (or an interruption) new voices continue the numbering
  (Speaker 3, 4…) and can be renamed to merge them (see #171); backgrounding ends identification at once without a final pass;
  more than two hours of one recording is not analyzed further.
- Editable titles and notes; atomic local saves after finalized utterances, explicit Save,
  save-before-New, local History, restoration on launch and Markdown through the share sheet.
  Title and Notes typing is saved about a second after you stop typing, and is flushed when
  recording stops or the app leaves the foreground — before the system can suspend it — so a
  keystroke never costs a full archive write. A
  save whose bytes are identical to the last one is skipped, and History is kept in memory: the
  conversation files are read on launch, after a delete and after a share-sheet import, not on
  every save.
- On-device Apple Intelligence summaries by default, or Ollama summaries — Ollama Cloud, or an Ollama
  server you run — with streamed results and secure API-key storage.
  Apple Intelligence accepts up to 8,000 characters (`PromptBudget.appleIntelligenceCharacters`, the
  shared cap macOS also clamps its Apple prompts to); Ollama accepts up to 60,000. Both caps are
  charged on the *fenced* conversation, not the raw text. Oversized input is rejected explicitly. AI output needs review.
- Prompts separate data from instructions (#140). The conversation a manual Summary, Deep or
  on-device Quick sends is wrapped in a `<transcript>` block, and every system prompt states that
  text inside that block is data to read and summarize, never instructions to follow. Closing tags
  inside the content are neutralized so nothing in a transcript or file can end the block early. iOS
  assembles one attributed source string, so a typed note travels inside `<transcript>` on its
  `Notes: ` line rather than in a separate `<notes>` block as on macOS; the grounding sentence about
  `Notes: ` lines is unchanged. Attachment text you copy into Notes travels the same way — iOS emits
  no `<reference>` block, because it has no file/folder reference context (see
  [Parity with macOS](#parity-with-macos)); the shared notice still names all four tags.
  This hardens the app against instruction-like text spoken by another participant or embedded in a
  shared file; it cannot fully prevent it.
- Recording stops and saves when the app is backgrounded or when audio is interrupted (call, Siri,
  alarm), and the status line says which of the two happened. When the system reports the
  interruption is over and asks for the audio back, recording resumes automatically and the status
  line says so; otherwise tap Listen to continue. Connecting or losing a microphone mid-recording
  (AirPods, a Bluetooth headset, a wired mic) rebuilds capture on whatever input remains instead of
  ending the meeting; one physical device change posts several notifications, so rebuilds within
  half a second collapse into one and a rebuild is skipped when the input format has not actually
  changed. Only a rebuild that fails stops recording, with the reason shown. The screen
  stays awake during active recording. No raw audio is saved.
- Version/build information in Settings.

System/call audio, background recording, Mac sync, audio-file import and WhisperKit transcription
are not included. A local/LAN Ollama server is supported only when you
enter its address yourself; the app performs no discovery and never switches servers on its own. Notes and saved
transcripts remain usable when the speech model or Apple Intelligence is unavailable.
App data is local to the sandbox. Sharing explicitly exports text.

Conversations, attachments and queued share imports are written with the
`completeUntilFirstUserAuthentication` data-protection class: after a restart they stay encrypted
until the device has been unlocked once, rather than being readable from the moment the system boots.
By default this data is included in the device's normal iCloud/Finder backup, like other app data, so
restoring a new phone brings the conversations along. **Settings → Privacy → Exclude conversations
from iCloud backup** (off by default) sets `isExcludedFromBackup` on the conversation and attachment
directories, the active-conversation file and the App Group share inbox — so a queued import that has
not been turned into a conversation yet is covered by the same promise; with it on, transcripts never leave the device — not even into an
Apple-held backup — and a restored phone will not have them. The setting is remembered and re-applied
at every launch, including for directories recreated later.

An automatic model-catalog refresh happens only where the user has already chosen that destination:
the Ollama provider plus either a saved API key or a server URL they entered. Opening a model list on
an Apple Intelligence install — or on Ollama Cloud with no key — contacts nothing; the explicit
**Refresh models from API** button is still there. A cloud catalog fetch with no key now fails locally
with "Add your Ollama API key…" instead of sending an anonymous request to ollama.com.

Ollama requests reuse one long-lived ephemeral `URLSession` per role (summaries, speech correction),
rebuilt only when the server URL or key changes, so an hour-long meeting with Auto Quick on does not
accumulate one session, connection pool and TLS handshake per evaluation.

Summaries can run while recording: each request uses a snapshot of the notes and transcript at
that moment. Stop listening remains available during generation. A disabled summary action shows
its reason (empty text, model unavailability, microphone transition or an in-flight response).
Check again re-reads readiness. Apple model-not-ready status does not prove a download is active.

Summaries render headings, bullets, bold, italics and inline code, including streamed responses. Fenced code remains monospaced. Saved conversations and Markdown exports keep the original output.

## Conversation actions

History supports swipe right to share, swipe left to delete, and a touch-and-hold menu. Deletion asks for
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
A batch that cannot be imported — an unreadable manifest, an oversized or unsafe payload — is moved to
`Inbox/Failed` and the drain continues, so one bad share no longer repeats its error on every
foreground or block the batches queued behind it. That quarantine is a recovery window, not storage:
its folders are deleted once they are 24 hours old, and the on-screen message says so. A failure that
describes the device rather than the batch (out of space, a read-only volume, a payload iCloud has
not finished materializing) is not quarantined at all — the batch stays queued and is retried the
next time the app opens, with a message saying so, until it is a day old, after which the same
failure is treated as permanent so a genuinely broken batch cannot fail forever. A
folder with no manifest is an extension that was killed mid-write and can never become a
conversation: it is left alone for 24 hours (the extension may still be writing) and then deleted, so
abandoned photo originals do not occupy the App Group forever.
It does not browse or synchronize your Apple Notes library. Paste text or add an exported PDF if a
source app does not offer a compatible share representation. Apple Notes rich formatting may be
flattened; verify that any scans or embedded documents you need were included.

## Provider default

A fresh install defaults to **Apple Intelligence · on-device** whenever
`AppleIntelligenceProvider.unavailableReason` is nil — a value that depends only on
`SystemLanguageModel.default.availability`, never on a locale. On a device that cannot run it the
default falls back to Ollama and Settings states the reason: ineligible hardware, Apple Intelligence
turned off, the model not ready, or an unlisted reason reported by the system ("Apple Intelligence is
unavailable. Choose another provider in Settings."). That explanation is shown only while the device is actually on the
unchosen Ollama fallback; once you pick a provider yourself it disappears, and it is never shown to
someone who selected Apple Intelligence deliberately. A provider you have chosen before is always
kept across updates — the default applies only when no choice has been saved. Automatic Quick Summary requires Ollama, so it
stays unavailable with an explanation until you select Ollama yourself.

On Apple Intelligence every AI output goes through `AppleIntelligenceProvider`, the same transport
macOS uses. **Manual Quick Summary asks the on-device model for the bullets in prose** rather than for
the automatic evaluator's JSON envelope: a small on-device model cannot be held to that schema, so the
JSON contract stays with the Ollama-backed Auto loop. The prose answer is read back leniently: list
markers, numbering, a "Here is the recap:" preamble and stray code fences are tolerated, and an answer
carrying no takeaway shows "No key takeaway yet." in the pane (a *failed* request is what keeps the
previous summary). Generation failures are stated in plain language instead of a developer message:
a conversation longer than the on-device context window, a guardrail refusal, a busy or undownloaded
model, and an unsupported language each say what happened and that Ollama can be selected instead.

The language check is per conversation, not per device: if the on-device model does not support the
**conversation's** language (the recording language shown in Settings), Generate is blocked with that
reason before the request is sent. Whether Apple Intelligence is available at all — the fresh-install
default above and the macOS status line — does not depend on any locale, so a device used in an
unsupported UI language still defaults to Apple Intelligence. macOS behavior is unchanged by this;
only the shared provider's failure wording is now the same on both platforms.

## Ollama (Cloud or your own server)

Open **More → Settings → Summary provider → Ollama Cloud**. Enter your key and tap **Save API key**,
then **Refresh models from API**, select a **Model role**, **Choose model**, and **Test connection**.
Each of the three roles has an independent model selection. When a new key is entered, the test
button becomes **Save key and test connection** and saves that key before sending the request. Keys are stored in
iOS Keychain with `WhenUnlockedThisDeviceOnly`, never in preferences, session exports or the app binary.
Enter the key separately on each device. Remove API key deletes it from this device.

### Your own Ollama server

**Server URL** is blank by default, which means `https://ollama.com`. Enter an `http://` or `https://`
address — for example `http://your-mac.local:11434` for an Ollama server running on your own Mac on the
same Wi-Fi network — and tap **Save server URL**. Only the scheme, host and port are kept; anything that
is not a valid http(s) URL with a host is rejected and the previous server stays in place. Entering
`https://ollama.com` yourself is recognised as Ollama Cloud, not as your own server. **Use Ollama Cloud
instead** clears the setting.

**Use the computer's `.local` name, not its IP address.** The app declares
`NSAllowsLocalNetworking`, which exempts plain `http` only for `.local`, link-local and loopback
names — not for a numeric private address such as `192.168.1.10`. A plain-`http` URL whose host is a
private IPv4 literal (`10.x`, `172.16–31.x`, `192.168.x`) is therefore refused at save time with a
message naming the `http://your-mac.local:11434` form, instead of failing opaquely on the first
request. `https://` to any address, and `http://127.0.0.1`, remain accepted. Reaching a LAN address
uses iOS local-network access, so iOS asks for that permission the first time.

**Your Ollama Cloud API key is never sent to a server you enter.** The saved credential belongs to
ollama.com; requests to any other host go out without an `Authorization` header, so a private endpoint
cannot collect it. The key stays in the Keychain and is used again as soon as the server is Ollama
Cloud. No API key is needed for your own server; one is still required for Ollama Cloud.

Nothing is discovered automatically and the app never changes the server for you: the destination
is shown as **Server: …** in Settings and repeated in the refresh, connection-test and error status text
so you can always see where a summary would go. A server you enter is your own machine, not ollama.com.

Refresh calls `/api/tags` on the selected server (`https://ollama.com` unless you entered one) with Bearer
authentication when a key is saved, and preserves exact returned
model IDs. The recent-family section picks the newest API modification time for each advertised
standard/Pro/Flash variant of DeepSeek, GLM, Qwen and Kimi. All API models remain available, including
other families. This is API update recency, not an independently verified release chronology.
No unavailable Flash/Pro name is invented. Refresh preserves your selected model; if it disappears,
choose another. Model refresh does not prove key validity: Test connection verifies a complete streamed
`/api/chat` response using only a synthetic prompt. Cloud models run remotely; `/api/pull` is not needed.

Selecting Ollama is opt-in; a fresh install summarizes on-device. Generating any of the three AI outputs
sends the current notes and transcript to the selected Ollama server (Ollama Cloud, or the server you
entered); microphone audio continues to be transcribed on-device. Quick Summary has an opt-in **Auto** toggle (off initially; your choice is remembered across launches). While listening, new completed transcript text triggers an evaluation in five-second batches. A valid evaluation either keeps or updates the visible Quick Summary and may recommend a manual Summary/Deep review. No unchanged-input requests are sent; failed reads retry with backoff. Enabling Auto with Ollama selected sends those snapshots to Ollama. Deep Think stays on-demand. Existing output remains visible while the next response streams; failures keep the last completed result.
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
and Foundation Models. iOS links FluidAudio for speaker identification and WhisperKit for spoken-language
detection only; WhisperKit never transcribes on iOS.

## Validation and release

Follow [the TestFlight release runbook](IOS-RELEASING.md) for exact archive, export, upload, account-recovery and tester-verification steps. A connected device is not required to upload an authorized beta; physical-device acceptance remains a separate production-readiness gate.

## App Store privacy and support pages

App Store Connect requires a reachable privacy policy URL and a support URL. Both are checked into this
repository and served from GitHub: [`docs/ios-privacy.md`](ios-privacy.md) and
[`docs/ios-support.md`](ios-support.md). The app links to the same two URLs from
**More → Settings → Privacy**, so a reviewer can reach them from inside the build. Keep both pages
accurate whenever behavior that they describe changes — the provider default, the Ollama server
setting, calendar redaction, backup exclusion, interruption handling and History search are all
described there.

Maintain the [iOS listing metadata](../metadata/ios/README.md) alongside release changes. Apply the
Beta App Description and per-build What to Test in App Store Connect, and verify the uploaded app
icon and the installed Home Screen icon. Repository metadata files alone do not update the listing.

Run lint, shared core tests/coverage, the iOS build and UI tests, and a macOS build to protect the
existing product. The simulator UI tests verify the unsupported-speech explanation without a microphone prompt, retry, saving notes, New, History and restoration across app restart.
GitHub Actions builds both apps and runs the headless `ListenToMeCore` unit/integration test suite plus the 95% coverage floor as a CI check; GUI, audio, device and Ollama-e2e acceptance stay local, run on the local Mac with `make validate-local`, including iOS UI and app-hosted tests. Simulator builds use ad-hoc signing so Keychain tests exercise actual storage. The credential-dependent live cloud test is opt-in and skips unless configured locally. Before marking iOS production-ready, test on a physical iPhone/iPad:

1. First-use microphone denial, retry after granting, and unsupported language/model errors.
2. Model installation, then at least two minutes of real speech with live/final transcript text.
3. Stop finalizes the last phrase; interrupted/unfinalized text remains visible after save/relaunch.
4. Background, incoming call, Bluetooth disconnection, and repeated Start/Stop do not leave the mic
   active. Decline a call mid-recording and confirm recording resumes on its own with a message;
   background the app mid-recording and confirm the message names backgrounding and that a later
   interruption-ended event does not re-open the microphone; connect AirPods mid-recording and
   confirm live text keeps arriving on the new input, then disconnect them and confirm capture
   continues on the built-in microphone.
5. New preserves the old conversation; History and sharing include notes, transcript and summary.
6. On an Apple Intelligence eligible device, confirm a fresh install starts on Apple Intelligence,
   generate a factual summary, and verify unavailable, oversized-input and failure states keep the
   transcript and previous summary. On an ineligible device, confirm the fallback to Ollama names the
   reason. Optionally point **Server URL** at an Ollama server on your own network using its
   `.local` name, accept the local-network prompt, refresh models and summarize without an API key;
   confirm a numeric `http://192.168.…` address is refused with the `.local` hint. On Apple
   Intelligence also tap **Generate** on Quick Summary after a few minutes of speech and confirm it
   publishes bullets rather than "did not return a usable Quick Summary update", and that a very long
   conversation reports the on-device context window in plain language.
7. Camera permission denial/retry, photo capture, photo library, Files and Apple Notes Send Copy imports. Preview, share originals, extract document text, remove attachments and delete/reopen conversations.
8. Portrait/landscape iPhone and iPad layouts, large text and VoiceOver controls.
9. Import a real meeting invite with attendees and a join link, then read Notes: attendee names appear
   without e-mail addresses, and the event link carries no `?pwd=`/`#` join secret.
10. Speaker identification (#180, #195): on a fresh install, confirm **Settings → Speakers →
    Identify speakers** is on, and that **Settings → Speakers** shows the models downloading, then
    ready, without recording; the status under the title reads "Microphone · Ready · Speaker labels on". Record about
    10 seconds of two voices and Stop: the lines are labeled. Separately, an offline first use shows
    "Speaker labels unavailable" with **Retry** (recording still works), and **Retry** works once
    online; Status details lists the speaker fields. Then record
    three people taking turns for at least two minutes. Confirm lines change from **Microphone** to **Speaker N** about 20 seconds in, that each
    speaker's lines land on the right person at turn boundaries (this checks SpeechAnalyzer's time
    ranges against the diarizer's), that Stop labels the last phrase, and that a cough or a
    one-word reply may stay **Microphone**. Rename a speaker in Notes, then confirm the name in the
    transcript, after relaunch, in History search and in a shared export, and that no Summary or
    Quick request starts. Record 20+ minutes and watch memory in Xcode's gauge stay flat, and note
    battery drain against an identical recording with the setting off.
11. Automatic transcription language (#197): on a device set to English, choose **Settings →
    Transcription → Language → Automatic (default)** and speak Mandarin, then Spanish in a second
    recording, for at least 30 seconds each. On first use confirm the one-time model download (and
    that it is the only network request: no audio leaves the device), then that within about 30
    seconds the status line reads "Detected Chinese · switched" (or Spanish), and the early English
    nonsense is replaced by Chinese (Spanish) text on the same timeline. Keep talking during the
    switch and confirm no words are lost around it. Tap **Undo** in a third recording and confirm
    the transcript returns to English and the picker shows English fixed. Speak English with
    Automatic on and confirm nothing switches. Turn on Airplane mode before the first-ever
    download and confirm recording continues with "Language detection paused". Take a phone call
    after a switch and confirm the resumed recording stays in the switched language with Undo. Then
    check the risks no simulator test covers: (a) with two minutes of speech before the switch,
    keep talking and confirm live text catches up within seconds and nothing is dropped, which shows
    SpeechAnalyzer keeps up with the replay while live audio queues (the new analyzer's input holds
    1,024 buffers, about 40 seconds of live audio); (b) the replayed lines carry the same times as
    the originals (Speaker labels on: the lines keep their speakers after the switch), which shows
    replayed buffers sent without `bufferStartTime` start at t=0; (c) with Identify speakers on,
    watch Xcode's memory gauge while Whisper, FluidAudio and SpeechAnalyzer are loaded together.

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

## iOS 1.9.0 (17)

Uses the [shared live-summary scheduler](SHARED-LIVE-SUMMARY.md) with macOS 1.4.0. Ollama was the fresh-install default in this build (changed to on-device Apple Intelligence in 1.10.2); existing choices remain saved. Auto requires Ollama and opt-in. Apple Intelligence remains available for manual summaries. See [What to Test](../metadata/ios/en-CA/what-to-test-1.9.0.txt).

## iOS 1.9.1 (18)

Quick publishes useful interim recaps while catching up with a backlog, with an explicit progress status. Quick requests prioritize three short bullets; manual generation displays only validated recap bullets. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.1.txt).

## iOS 1.9.2 (19)

Save confirms local History storage beside the bottom controls. Default Share sends readable text from the current conversation and History; More offers Share Markdown separately. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.2.txt).

## iOS 1.9.3 (20)

Automatic Quick Summary now evaluates substantial live recognition text at the shared five-second batching interval, even before Speech marks a phrase final. Short fragments wait for more words; silence does not poll. Final recognition replaces provisional wording. Status details exposes speech event, timer and model-read counts for device diagnosis without including transcript text. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.3.txt).

## iOS 1.9.4 (21)

Quick publishes its first short recap for a clear topic, problem, tentative proposal or substantive question without waiting for a decision. Questions are summarized, not answered, and ambiguous acronyms are preserved. Repetition still avoids unnecessary changes. Empty results say “Speech checked · No takeaway yet,” including after recording stops. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.4.txt).
