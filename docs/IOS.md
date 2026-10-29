# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`. Public App Store version is
**1.19.1 (39)** and the latest TestFlight version is **1.20.2 (42)**. See the
[public availability observation](releases/ios-1.19.1-build39-public.json).

## Unreleased History work

The current draft adds explicit local model download/cancel/remove controls, safer asynchronous
History indexing and refreshed search after saving. The optional multilingual backend still fails
its language-quality gate; it is not ready for distribution. [Implementation and BDD evidence](history-search-implementation.md).
Settings also corrects its screen-lock explanation to match continued user-started recording.
No version or in-app release-note announcement has been advanced for this incomplete work.

## Current TestFlight beta — 1.20.2 (42)

Apple accepted **1.20.2 (42)** through the official TestFlight helper at **2026-10-28T21:11:37.664213+00:00** from `a6b90e83f775cc9dc88df3c2805ecacedca044af`. Apple build `8967f095-470f-40c0-aba0-b1188bbb699c` is **VALID / IN_BETA_TESTING**. Readback at 2026-10-28T21:15:33.796221+00:00 confirms **en-US**, **Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for the existing two-member Dev group. Access does not establish physical installation of build 42.

[Publication receipt](releases/ios-1.20.2-build42.json) · [Release notes and native previews](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.2-build42).

Physical phone translation/lock-screen/multilingual and Watch acceptance remain pending. Public production remains **1.19.1 (39)**; this beta made no new public submission or listing-media upload. Mac changes remain unreleased and keep separate installed-app acceptance gates.

## Historical TestFlight beta — 1.20.1 (41)

Apple accepted **1.20.1 (41)** through the official TestFlight helper (receipt recorded 2026-10-28T19:02:09.198475+00:00) from `dc6b2e39a99568fb4931e937c555fa0de0f2ff18`. Apple build `5c2339eb-5e17-4bd6-8eb1-ec1d212ef49f` is **VALID / IN_BETA_TESTING**. Existing Dev group access was verified at 2026-10-28T19:05:58.417288+00:00; its two accepted memberships are unchanged. Primary locale and metadata are **en-US**, with localized name **Listen To Me - Real Time AI**; beta description and What to Test match the intended copy. Group access does not establish physical installation of build 41.

[Publication receipt](releases/ios-1.20.1-build41.json) · [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.1-build41).
Physical lock-screen, multilingual/translation and Watch acceptance remain pending. Public iOS
remains 1.19.1 (39); this beta did not submit a public version or update listing media.

## Historical translation beta — 1.20.0 (40)

Apple accepted **1.20.0 (40)** through the official TestFlight helper (receipt recorded 2026-10-28T13:56:43.061187+00:00) from `4a72489120fda713c6d117c3d6c3dc661cf1dd9e`. Apple build `93926f6c-0137-49fe-bc06-f73f04f831f5` is **VALID / IN_BETA_TESTING**, with existing Dev group access verified at 2026-10-28T14:06:21.847671+00:00. English (US) localized name, beta description and What to Test match the intended metadata. Group membership does not establish physical installation of build 40.

Physical phone/Watch acceptance and installed real-language-pair translation quality remain pending. The Mac translation feature remains unreleased. Public production remains 1.19.1 (39); this beta did not submit a new public version or upload listing screenshots. QA-only captures are not approved store assets.
[Publication receipt](releases/ios-1.20.0-build40.json) · [Translation behavior and limits](translation.md).

## Screen lock and language recovery (#339, TestFlight 1.20.1 / 41)

A recording started while the app is active continues through screen lock/background until Stop,
interruption or capture/transcription failure. Optional AI work pauses while inactive, and active
return keeps the same microphone run. Delayed preparation cannot start capture in the background.
See [recording continuity and evidence](recording-continuity.md) and
[language replay/recovery](language-replay-progress.md). Audio saving remains opt-in; data protection
and provider choices are unchanged. [TestFlight distribution is accepted](releases/ios-1.20.1-build41.json);
physical iPhone/iPad lock-screen acceptance remains pending.

## What this app is for

**ListenToMe for iPhone and iPad is a personal capture and recall companion — not a port of the macOS
meeting copilot.** It records and transcribes what *this device's* microphone hears: an in-person
conversation, a lecture, an interview, a phone left on the table. It summarizes on-device by default
(Apple Intelligence, where the device supports it) — or with Ollama, a cloud AI service or an
OpenAI-compatible server only when you choose one — and keeps every conversation local, searchable by
words and by meaning (with **Ask your history**), and shareable or exportable. Its answers are Quick
Summary and Summary; Deep stays on the Mac.

**It is deliberately not a copilot for calls or video meetings.** iOS does not let an app capture
another app's audio, so the dual-channel "You / Others" experience — and everything built on knowing
which voice is the remote participant, such as proactive answers to a question someone else asked —
stays macOS-only. This is a platform boundary, not a backlog item: there is no planned iOS feature
that captures system or call audio. The 1.20.1 (41) beta declares audio background mode so an
established user-started microphone recording continues through screen lock; new capture still
requires active use. Optional AI pauses. See [continuity limits and acceptance](recording-continuity.md).

Apple Watch recording ([#181](https://github.com/tomqwu/ListenToMe/issues/181)) is included in public iOS **1.19.1 (39)** and **TestFlight 1.20.2 (42)**. Its phone/Share/Watch distribution package and Apple beta access were verified; physical microphone, paired transfer, wrist-down and battery/storage acceptance remain pending. See [Watch installation and evidence](watch-beta.md), the [accepted beta receipt](releases/ios-1.20.2-build42.json) and the [public availability observation](releases/ios-1.19.1-build39-public.json). Dated earlier-build publication evidence remains in the Watch guide.

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
| `AutomaticReviewCoordinator` — queued Summary/Deep reviews, deadlines, manual completion; `modes` limits which reviews it runs | `MeetingSession` (Summary and Deep) | `MobileSession.automaticReviews` (`modes: [.summary]`: iOS ignores the evaluator's Deep recommendation, #235) |
| `SuggestedPrompts` (#61) — suggested-chip validation, 20-second refresh window, used-chip memory, the strict prose "Suggested:" block | `MeetingSession+Suggestions`, `App/SuggestedPromptChips.swift` | `iOS/MobileSession+Suggestions.swift`, `MobileSuggestedPrompts`, `MobileSuggestedAsk` |
| Prompt data fences and caps: `PromptData.notice`, `PromptData.block`, `PromptBudget` | `PromptBuilder` (`Prompt.swift`) | `MobileSummaryMode.instructions`, `MobileSession.summarize` |
| On-demand grounding (#114): `OnDemandGrounding` — Quick/Deep transcript budgets, the summary-plus-recent or opening-plus-recent excerpt, its model note and the pane's "Using the last ~N min…" line | `MeetingSession.clampedContext`, `roleNotices` | `MobileSession.summarize` (`iOS/MobileSession+Summarize.swift`), `answerNotices` (Quick; iOS has no Deep, #235) |
| Output-limit signal (#215): `LLMStreamEvent.outputLimitReached`, `LLMOutputLimit` (notice, plain-text cut-off error) | `MeetingSession.run`, `RoleBox` | `MobileSession.summarize`, `MobileAnswerNoticeLines` |
| `SessionArchive` — the on-disk conversation format | `App/SessionStore.swift` | `iOS/MobileSession.swift` |
| Speaker identification: `SpeakerDiarizer` and `SpeakerAudioBuffer` (`SharedPlatform/`, FluidAudio), `SpeakerIdentityTracker`, `SpeakerLabeling`, `SpeakerStats`, `SpeakerAnalysisPolicy` | `App/MeetingView+Speakers.swift` | `MobileSpeakers`, `iOS/MobileSession+Speakers.swift`; iOS language detection (#197) reuses `SpeakerAudioBuffer`, keeping its trailing two minutes (#199) |
| Save to folder (#53): `MarkdownVault` (note format and file names), `MarkdownVaultWriter` (bookmark, atomic coordinated write, failure wording), `MarkdownVaultSync` (`SharedPlatform/`, setting, queue, status, Retry) | `App/MacVaultSettings.swift`, `App/MeetingView+Conversations.swift` (`checkpoint`) | `iOS/MobileVaultSettings.swift`, `iOS/MobileSession+Vault.swift` |
| Domain vocabularies (#222): `VocabularyCatalog` (bundled presets and their validation), `VocabularySettings` / `ActiveVocabulary` (My terms, defaults, the 100-term recognition cap), `VocabularyPrompt` (prompt guidance, correction glossary), `VocabularyClassifier` / `VocabularySuggestionTracker` (on-device suggestion); `SessionVocabulary` and `SpeechVocabularyContext` (`SharedPlatform/`, banner state and the `AnalysisContext`) | `App/MacVocabularyViews.swift`, `MeetingSession.contextualStrings`, `App/SpeechAnalyzerTranscriber.swift` | `iOS/MobileSession+Vocabulary.swift`, `iOS/MobileVocabularyViews.swift`, `iOS/MobileRecorder.swift` |
| Export formats and file names (#130): `SessionExporter` (Markdown, plain text, SRT, WebVTT, JSON v1, file names), `TranscriptTimestamp` (which lines are timed, `[mm:ss]` and cue times); the conversation's own language (#206): `ConversationLanguages` on `SessionRecord` | `App/MeetingView+Export.swift` (Export menu, History detail sheet), `noteCaptureLanguage` | `iOS/MobileSessionExport.swift` (`ConversationExportFile`, **Export as**), `MobileLanguageDetection.languageChanges` |
| `SessionSearch` — History keyword search and its matching rules | `App/SessionSearchView.swift`, `App/MeetingView.swift` | `MobileHistoryView` via `MobileSession` |
| Semantic History search and Ask your history (#57): `HistoryIndex` (on-device index beside the archive), `HistoryChunker`, `NaturalLanguageEmbedder`, `HistoryRanking`, `HistoryQuestion`; `HistorySearchModel` (`SharedPlatform/`) | `App/SessionStore.swift`, `App/SessionSearchView.swift`, `App/HistoryAskPanel.swift`, `App/MeetingView+HistoryAsk.swift` | `iOS/MobileSession+HistorySearch.swift`, `iOS/MobileHistoryView.swift`, `iOS/MobileHistoryAskView.swift` |
| `AppleIntelligenceProvider` (`SharedPlatform/`) — on-device transport and its failure wording | `App/MeetingView.swift` | `MobileSession`, `MobileAISettings` |
| `OllamaProvider`, `LLMRequest` / `ChatMessage`, `OllamaGenerationOptions` | `App/MeetingView.swift` | `MobileAISettings.client(for:)` |
| Cloud AI presets (#214): `CloudAIPreset` (addresses, headers, key binding), `OpenAICompatibleDialect` (vendor request quirks), `AnthropicProvider` (native Messages API), `CloudAICatalog` (model lists), `CloudAISettingsChange` (macOS save plan) | `App/CloudAISettings.swift` | `MobileCloudAISettings`, `MobileAISettings.client(for:)` |
| OpenAI-compatible servers (#52): `OpenAICompatibleProvider` (stream contract), `OpenAICompatibleEndpoint` (validation, plain-`http` rule, "your server" / "may leave this device" labels, key origin), `OpenAICompatibleCatalog` (`/v1/models`) | `App/OpenAICompatibleSettings.swift` | `MobileOpenAISettings`, `MobileAISettings.client(for:)` |

The prompt *fences* are shared; the prompt *text* is not entirely. macOS assembles pane prompts with
`PromptBuilder`, iOS with `MobileSummaryMode.instructions`, and both append the same
`PromptData.notice`. Changing that notice, `PromptData.block` or a `PromptBudget` cap changes both.

### Tier 2 — platform-appropriate: may differ, every difference listed here

| Capability | macOS | iOS |
| --- | --- | --- |
| Capture | Microphone **and** the other participants' system audio via ScreenCaptureKit (`App/DualChannelCapture.swift`), labeled You / Others | This device's microphone only; lines are labeled **Microphone** unless speaker identification names them; active Start, with established background capture in TestFlight 1.20.1 (41) |
| Background recording (TestFlight 1.20.1 / 41) | Existing Mac capture lifecycle | An established user-started microphone run continues through screen lock with optional AI paused; physical lock-screen acceptance remains pending |
| Default AI provider | Explicit AI mode — Local only, Apple Intelligence, Cloud, Cloud AI service, OpenAI-compatible, or AI off — defaulting to a local Ollama model | A fresh install uses **Apple Intelligence on-device** when it is available, otherwise falls back to Ollama and names the reason (`MobileAISettings.fallbackExplanation`) |
| Ollama endpoint | The local daemon (`localhost:11434`) or Ollama Cloud | Ollama Cloud, or a server you run and address yourself (`.local`/loopback for plain `http`); a saved cloud key is never sent to another host |
| Cloud AI services (#214) | AI mode **Cloud AI service**; service, key (**Check key** lists its models) and links in Settings; each pane's model picked in the status rail | Summary provider → **Cloud AI** → a service; key, models per role and **Test this model** in Settings (`MobileCloudAISettings`). Speech correction stays on Ollama |
| OpenAI-compatible server (#52) | AI mode **OpenAI-compatible**; server URL and optional key in Settings; **Check Auto compatibility** tests the saved Quick model with synthetic text; failed JSON checks pause Auto per server/model | Summary provider **OpenAI-compatible**; **Test this model** on the Quick role checks the JSON contract and a failed check pauses Auto with the reason (`MobileOpenAISettings.automaticQuickReason`). Speech correction stays on Ollama |
| Selection summary (#234) | — (macOS later) | **Select** in the transcript, or touch and hold a line → **Summarize from here** / **Select from here**; a sheet with Copy, Share and Add to notes. Core: `TranscriptSelection`, `SelectionSummaryPrompt`, `SelectionSummary` (saved on `SessionRecord.selectionSummaries`, last 5) |
| Answer panes | Summary (Listener), Quick and Deep, each with its own model | Summary and Quick only (#235). Deep is macOS-only: Auto ignores the evaluator's Deep recommendation, and a Deep analysis an earlier version saved stays read-only under the Summary as **Earlier deep analysis**, in share/export text and in Save to folder notes; nothing new is written to it |
| Per-role models | A picker per pane in the status rail, over local and cloud models, auto-picked local-first (`ModelRanking`); on the OpenAI-compatible and cloud AI routes, the server's or vendor's model list, never auto-picked and none verified local | Settings → Model role for Summary / Quick (`MobileRoleModelView`), from Ollama, the cloud AI service's model list or the OpenAI-compatible server's `/v1/models`. A Deep model an earlier version saved (`mobileOllamaDeepModel`, `mobileOpenAIDeepModel`, `mobileCloudAI.<vendor>.deepModel`) is left in place and never read |
| Local-model enforcement | `ModelPrivacy` / `localOnly` verifies downloaded weights before every request | Not applicable — on-device here means Apple Intelligence; iOS reaches Ollama only over the network |
| Speaker identification | Optional on-device diarization of the Others channel (and optionally the microphone) with naming; line labels need WhisperKit timestamps | On by default, can be turned off (**Settings → Speakers → Identify speakers**): FluidAudio diarizes the one microphone on-device, lines become **Speaker 1, 2…** by SpeechAnalyzer's audio time ranges, and **Notes → Speakers** renames them. Trailing-window passes while recording plus a final pass on Stop, foreground only; a line no speaker covers for at least 30% of its length keeps **Microphone** |
| Presets and reference context | Use-case presets (`PresetCatalog`) and file/folder reference context (`ReferenceBuilder`, `FileContextLoader`) | Not today. Attachments instead: extracted text is appended to Notes, so it reaches the model inside `<transcript>`, not a `<reference>` block |
| Calendar import | **Load from Calendar** fills Context notes (`App/CalendarService.swift`); text is imported as written | **Import from Calendar** removes e-mail addresses and link passcodes first (`MeetingContext.redactingLinksAndAddresses`, `MobileCalendar.attendeeNames`) |
| Share-sheet import | — | Share extension plus an App Group inbox (`ShareExtension/`, `iOSShared/SharedInbox.swift`) |
| AI speech correction | — | Opt-in, over a Flash model on Ollama (`MobileTranscriptCorrector`); with vocabularies on, the request carries a glossary of My terms and near-miss preset terms (#222) |
| Vocabulary guidance in prompts (#222) | Rides in the persona line every pane's prompt carries (`VocabularyPrompt.combined`), so `PromptBuilder.scaffoldCharacterCost` measures it | Appended to the Summary and Quick system prompts (`LLMRequest.addingGuidance`) and to the automatic reviews' directives; on Apple Intelligence it is capped at 400 characters, and on every provider it is charged to the same prompt budget as the transcript |
| Add to My terms (#222) | Right-click a transcript line | Long-press a transcript line |
| Proactive Quick answers | Yes — needs a finalized question on the Others channel | No — there is no Others channel to detect one in |
| Suggested prompts (#61) | **Suggested · from context** above the fixed Quick actions, from the Auto Quick check only (macOS manual Quick answers are prose with no chips); a click asks Quick, the context menu also offers **Ask in Deep**, which behaves like the **Deep answer** button; Auto off or AI off clears them | Under Quick Summary, from the Auto Quick check or a manual Quick refresh — on Apple Intelligence through the strict prose "Suggested:" block; a tap is a separate ask to the Quick model, answered in a small Ask card under Quick Summary and never replacing a summary (iOS has no free-form Quick answer and no Deep tab, #235) |
| Ask your history (#57) | Uses the Deep pane's model on the current AI mode; AI off disables it | Uses the Summary role's model on the selected summary provider (iOS has no Deep role, #235) |
| Automatic titles (#221) | Renames a saved "Conversation — <date>" after Stop, Save or New conversation; **Settings → Name conversations automatically** | Renames "New conversation" or "Apple Watch · <date>" after Stop, Save, a finished Apple Watch recording or a return to the foreground; **Settings → Conversations → Name conversations automatically**. Both on by default, sharing `ConversationAutoTitle` |
| Deleting everything (#220) | **Clear history…** in the History sheet | **Delete all conversations…** at the bottom of History and in **Settings → Privacy**. Each platform runs its own `conversationDataOwners` list (Core `ConversationDataOwner`), so saved audio and the search index go with the conversations |
| Third-party licenses | **Open-source licenses…** shows `App/ThirdPartyNotices.txt` as one text | **Settings → About → Acknowledgements** lists each package from the same file with its full license (`MobileAcknowledgementsView`, #202) |
| "What's New" | GitHub release notes and `CHANGELOG.md` | In-app, shown once per set of bundled notes (`MobileReleaseNotes`) |
| Saved audio (#55) | Off by default (Settings); one `.m4a` per source per run — microphone and system audio as separate labelled files — under Application Support, following Time Machine; saved only while Save sessions locally keeps the conversation, deleted by Discard and Close without saving; placed at #233's `recordingOffset`; History → a conversation plays it, and only WhisperKit lines (real times) can jump into it | Off by default (**Settings → Audio recordings**); the microphone audio the transcriber accepted, one `.m4a` per run, always excluded from backups; the expanded transcript plays it and every line can jump to its time |
| Storage protection | Plain atomic writes | Data protection (`completeUntilFirstUserAuthentication`) plus an optional backup exclusion (`PrivateStorage`) |
| Export | Markdown, plain text, SRT, WebVTT and JSON files (subtitles only with WhisperKit timestamps; SpeechAnalyzer reports none until #68), PDF and recap, from the Export menu and the History detail sheet, named after the conversation (#130); **Save to folder** chosen with an open panel, written when a checkpoint is complete (capture stopped) and only while autosaving is on | Readable text and Markdown through the share sheet, and **Export as** Markdown, plain text, SRT, WebVTT or JSON files from More and a History row, named after the conversation, with timestamps (#130); **Save to folder** chosen in the Files picker (security-scoped bookmark), written at Stop/Save and on later changes while not recording |
| Audio-file import | Yes (`SharedPlatform/AudioFileReader.swift`) | No |
| Languages | Transcription language **and** AI response language, from every on-device language the OS lists (#172); the opt-in WhisperKit engine transcribes mixed languages | Transcription language only, from the same OS list (#172): **Automatic** (the default) detects the spoken language on the device from the first seconds of speech, re-checks it about once a minute and switches when it changes (#197, #199), or a fixed language. Words of two languages mixed within one sentence are not transcribed (#205) |
| Input | Global ⌘⇧Space hotkey and a Session menu | Touch UI; no hotkeys or menu bar |

### Tier 3 — out of scope for iOS

| Not in the iOS app | Why |
| --- | --- |
| System, call or other-app audio capture | iOS gives no app another app's audio. The dual-channel copilot is macOS-only by platform, not by ordering |
| A local Ollama daemon and its downloaded-weight verification (`ModelPrivacy` / `localOnly`) | A phone does not run the Ollama daemon; on-device inference on iOS is Apple Intelligence |
| The WhisperKit transcription engine | SpeechAnalyzer is the only iOS transcription engine. WhisperKit is linked into the app target (not the share extension or the watch app) for spoken-language detection only (#197), and FluidAudio for speaker identification only |
| Mac↔iOS sync or a Mac companion mode | Out of scope product-wide — see [backlog](backlog.md) → "Intentionally out of scope" |

## Mixed-language Whisper evaluation (#205) — October 29, 2026

[#205](https://github.com/tomqwu/ListenToMe/issues/205) remains an evaluation of on-device,
opt-in Mandarin–English transcription: compare WhisperKit **small** and **turbo** accuracy,
speed and battery on a recent iPhone, then record a go/no-go decision. No iOS engine feature
or release is established by this preparation.

The separate development-signed benchmark host and test bundle passed signature and exact
**73-file Assets** checks using pinned local models/tokenizers. Its physical compatibility
attempt on iPhone 17 Pro Max / iOS 27.0.1 installed that isolated host, but the OS refused test
launch while the phone was locked. **No native test start or completed model case was observed.**
The owned run was cancelled early with exit **130** after **388.464 seconds** of its 600-second
bound; all **539 frozen inputs** remained unchanged. Local processes were reaped, remote absence
was confirmed, and the temporary benchmark app was uninstalled with absence readback. The
production/TestFlight app and its data were unchanged.

[The sanitized preflight receipt](evaluations/whisper-205-device-preflight-2026-10-29.json)
binds the external source, model/tokenizer pins and retained evidence. It preserves the earlier
compile, resource-packaging, signing and inventory failures separately. The partial result bundle
has no finalized test summary. All 319 raw run files, including that bundle, were preserved;
no pass/fail/skip totals are claimed. LAN connectivity was present; whole-phone offline operation
is **not** asserted.

Physical model compatibility remains blocked, not failed on model quality. Mixed-language accuracy,
speed, battery and the go/no-go decision remain outstanding; synthetic-audio pronunciation has not
been accepted from its input text alone. A future fresh compatibility attempt needs an available
unlocked device, fresh source/device/ownership checks and internal resource coordination for the
preserved candidate. Existing testing authorization remains; this does not replace the full
measurement criteria.

## Version policy

**The two apps keep independent version lines.** They are separate products in separate distribution
channels, and an iOS build number already accepted by App Store Connect can never be reused. A higher
iOS version does *not* mean the iPhone app is ahead of the Mac app; today macOS is 1.4.4 (14) and iOS
has published TestFlight 1.18.1 (36).

- **`MARKETING_VERSION`** (iOS, in `project.yml`): a **minor** bump for user-visible features, a
  **patch** bump for fixes.
- **`CURRENT_PROJECT_VERSION`** (iOS): increments monotonically on every upload and **never resets**
  when `MARKETING_VERSION` changes. The app and share-extension targets keep identical values.
- **One release per batch of work, not per fix** — the release trains in
  [AGENTS.md](../AGENTS.md) govern both platforms: at most one macOS release and one TestFlight
  build per day for trains an agent starts on its own, never one release per merged pull request.
  A train the maintainer calls goes out the same day even if one already departed, and work the
  maintainer requested from tester feedback ships on a TestFlight train once merged and its
  candidate checks pass.
- **Tags:** `ios-vX.Y.Z-buildN` for iOS, `vX.Y.Z` for macOS. An iOS build is never published as the
  latest macOS release.
- **`CHANGELOG.md` carries both platforms**, newest first, interleaved by date.
- Do not bump the macOS version for an iOS-only release, or the reverse.

The archive, upload, tagging and verification steps themselves are not repeated here: follow
[IOS-RELEASING.md](IOS-RELEASING.md) for iOS, [RELEASING.md](RELEASING.md) for macOS, and
[AGENTS.md](../AGENTS.md) for the release workflow that governs both.

## Public App Store approval and US primary — October 27, 2026

Apple now reports **1.18.1 (36) READY_FOR_SALE** and its review **COMPLETE**. After approval, the
primary-language PATCH succeeded; subsequent app readbacks confirmed **en-US**. The submission-time
waiting/Canadian-primary states below are historical. Both beta localization records are also en-US.

### Submission checkpoint — October 26, 21:13 UTC (historical)

Later locale audit: build 36's separate TestFlight records initially still had only en-CA. The en-US
What to Test and beta description are now created and read back, with no binary upload. The app-wide
primary remained en-CA at that audit, pending Apple approval of the new US localization and platform screenshots.
See [the correction receipt and requirements](IOS-RELEASING.md#earlier-locale-correction--october-26-2241-utc).

The **English (US)** listing **Listen To Me - Real Time AI**, **1.18.1 (36)**, was resubmitted with
24 fresh US-region screenshots and accepted for App Review at **21:13:50 UTC**. Review
`4e63cda8-70db-4d67-9928-63409df4dbda` was WAITING_FOR_REVIEW and set to release after approval;
production was 1.15.0 (32). Earlier Canadian and US reviews were canceled. All 24 new US uploads
are COMPLETE, with native dimensions, MD5s, display order and downloaded RGB pixels verified. These
are fresh en-US captures, not reused en-CA images. At that checkpoint, Apple's primary-locale
change returned HTTP 409 and the app-wide primary/fallback remained en-CA despite the US submission.

The maintainer reports working TestFlight testing and requested no further local device testing or
participant requests for this submission. The requested screenshot refresh used synthetic simulator
content only. No new binary was uploaded; Watch stays excluded, with [native Watch previews](images/watch/1.18.1-preview/README.md)
saved separately for maintainer review. macOS distribution is separate. See
[the current receipt](IOS-RELEASING.md) and [the current handoff](HANDOFF.md).

## App Store Connect platform mapping

The native Mac App Store platform is prepared separately as a sandboxed **1.5.0 (15)** archive under the shared listing and bundle ID. The Mac draft has US metadata but no selected build or submitted review. The earlier signed candidate predates this main integration and is not eligible for upload; rebuild from the exact merged source after installed sandbox/OTHERS acceptance. See [Mac Store distribution](RELEASING.md#mac-app-store-distribution). The current public Mac distribution remains the signed/notarized DMG.

The iOS platform covers this universal iPhone/iPad app (`TARGETED_DEVICE_FAMILY=1,2`); no separate iPadOS platform is added. The Watch companion belongs to the same iOS app record and must actually be embedded in an uploaded build before it can be installed. Public iOS 1.19.1 (39) and its TestFlight build include it; older public 1.18.1 excludes it. The accepted Watch beta has verified package identity and existing-tester-access evidence; physical acceptance remains a production gate, not an authorized beta-upload blocker. macOS requires its own compatible archive and distribution; the current native Mac app is distributed as a signed/notarized DMG, and Mac publication remains paused. Adding a platform does not convert a DMG or include an unembedded Watch target. See [Apple’s platform guide](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/).

## Full summary menu icon (#319, published TestFlight 1.18.2)

The More menu uses the existing Summary symbol beside **Full summary**, matching the Summary
workspace. The action still opens the same sheet; Done returns to the conversation without starting
recording. `IOS-008` binds the native rendered-menu regression, with the original zero-pixel failure
retained separately from subsequent validation.

Apple accepted **1.18.2 (37)** at **2026-10-27T03:39:12.147449+00:00**, from `9494d024b9eee577b40695292aaf5e7dab9434eb`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and both existing Dev testers have accepted group access. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.2-build37).

Full local validation passed: 108 BDD scenarios, 1,239 core tests with 98.2493% coverage, 75 iOS UI tests, 454 iOS unit tests, 39 native Mac tests, four Watch tests and four real Ollama/OpenAI-compatible contract tests. Existing optional skips remain documented; all required selectors passed. All three hosted checks passed on the exact merged source ([CI](https://github.com/tomqwu/ListenToMe/actions/runs/40444715802)). The tested source `9425611` and release source `9494d02` have identical trees.

[Fresh capture catalog](images/ios/release-1.18.2-en-US.json): 28 inspected native en-US images across four iPhone/iPad categories, including four fixed-menu captures. Originals, hashes and source/binary provenance are preserved. These are synthetic simulator captures; 1.18.2 App Store listing uploads remain pending.

Physical-device acceptance was not performed for this beta; it is not a production-ready claim. Public iOS 1.18.1 remains READY_FOR_SALE; 1.18.2 has not been submitted to the public App Store. Watch is excluded and the separate Mac Store draft #318 remains unsubmitted.

## iOS 1.18.1 (36) — published TestFlight beta

The published tester-feedback speaker fix uses per-recording LS-EEND streaming for the live microphone,
with stable recording-scoped identities, bounded prediction history and final tail flushing.
The Settings switch can turn identification off while listening, releasing its audio and blocking
late labels; re-enabling waits until Stop. Mac capture and Watch/file
imports retain the existing offline pipeline. The [model contract and evidence limits](speaker-identification.md)
and [What to Test](../metadata/ios/en-US/what-to-test-1.18.1.txt) describe real-model gates and pending
original-recording / physical-device acceptance. Apple accepted the upload at 2026-10-26T17:29:24.328646+00:00; processing is VALID, internal state is IN_BETA_TESTING, existing Dev access and en-CA metadata were read back. [Release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.1-build36). All 24 source-matched native screenshots were inspected; App Store listing upload remains pending.

## iOS 1.18.0 (35) — published TestFlight beta

[Published October 26](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.0-build35) from `b1570ad567a43a093294974871d7f0abf1872708` after PR #308 merged. Apple accepted the upload; processing is VALID, internal testing is IN_BETA_TESTING, and the existing Dev group and en-CA metadata were verified. The combined batch includes on-device saved-audio re-transcription (#224), full automatic-review budgets (#148), completed orchestration extraction (#134), reliability follow-ups (#141) and the compatibility fixes below. Current-source physical acceptance remains pending. Mac-only features remain unreleased; the maintainer deferred their installed acceptance for this beta merge. That build excluded Watch. TestFlight 1.19.0 (38) later included it with physical acceptance explicitly pending.

The reported iPad Pro 12.9-inch (4th generation), iPadOS 27.0.1, supports on-device dictation but
reports advanced SpeechTranscriber unavailable and Apple Intelligence device-not-eligible. These
are independent capabilities. The app prefers supported advanced speech and otherwise uses
Apple's on-device DictationTranscriber for both microphone and received Watch audio. Language
choices and Automatic use the same supported-module catalog; reading it downloads no detector.

Live recording checks compatibility before enabling Start. Unsupported speech, denied microphone
access and simulator capture show a compact cause with applicable recovery. Live and Summary offer
Info for the full instructions; VoiceOver keeps the complete reason, and short landscape layouts
allow scrolling to model controls. A subsequent failed model or
microphone preparation presents “Couldn’t start listening” with its full error and recording settings;
cancellation does not create a false alert. A transient inactive permission prompt preserves the
pending start. A delayed foreground capability check cannot import a queued share after backgrounding.

Unavailable Apple Intelligence is omitted from enabled provider choices, with its current reason
and explicit alternatives. A saved unavailable Apple choice remains saved, and generation is blocked;
no cloud/provider/key is selected automatically. Foreground/settings refresh changes readiness,
not user choices. Speech capture never requires a configured summary provider.

The physical iPad's prior installed build reproduced the failure. Historical checks at `215d818`
produced new microphone words and retained opt-in audio with Play/Pause controls on iPad and iPhone.
The iOS persistence implementation changed afterwards; those checks do not establish physical
acceptance of this published beta, every model/language or audible playback quality. See the
[platform compatibility table](device-compatibility.md), BDD contracts and source-matched evidence.

For playback, enable More → Settings → Audio recordings → Save audio recordings before recording.
After Stop, open the conversation (from History when needed) and tap the play icon in Live transcript.
In compact Duo, open Transcript actions → Play recording. The expanded transcript contains Play/Pause
and playback controls. Unsaved earlier audio cannot be recovered by enabling the setting later.

## iOS 1.17.0 (34) — TestFlight, October 25

This batch adds remembered iPhone Duo pane widths (#268), per-conversation vocabularies (#237),
speech-activity language re-checks (#216), responsive speaker finalization on background (#188),
live-summary caching and provisional speech handling (#164), per-passage History index reuse (#223),
custom-server context limits (#210), local Ollama prompt sizing (#230), and clearer Ollama endpoint
validation (#149). Deleting a conversation cancels and clears its active History answer and citations
so a late response cannot restore deleted content (#131). Supported semantic languages are unchanged.
Watch stays excluded from the archive; no dependency or license inventory changed. At `dbd1cc7`,
`make validate-local` passed: 1,068 Core tests (seven intentional skips, 98.1107% coverage) and 471 iOS
tests (461 passed, ten intentional skips, zero failures), plus lint, release helpers, the signed Mac
build and real Ollama/OpenAI-compatible contracts. Four device capture tests passed; all 24 final
native-resolution images were visually accepted, with both phone sets retaken after rejecting a
system-notification overlay. Originals, hashes and device/source provenance are preserved. The
signed archive and distribution package passed verification. Apple accepted the upload from
`cbd2e454dbf502df5832dc3654ee2d284f147380` at 16:27:39 UTC on October 25. Processing is VALID,
internal state is IN_BETA_TESTING, Dev contains the build, and en-CA metadata matches. The remote
tag points to that source and the GitHub pre-release was read back; macOS remains Latest.
Physical-device acceptance and App Store listing screenshot upload remain pending.
[What to Test](../metadata/ios/en-CA/what-to-test-1.17.0.txt).

## iOS 1.16.0 (33)

Prompt below Notes adds one-time Ask and saved per-conversation summary instructions, with editable
domain presets (#257). Wide iPhone Live layouts show Transcript and Quick side by side (#253).
All seven vocabulary presets include Simplified Chinese terms (#238). Privacy and audio-retention
copy now describe selected remote providers and opt-in audio correctly (#247, #251). The release
workflow captures native screenshots for compact/large iPhone and iPad views (#255). Watch remains
excluded; no dependency or license inventory changed. [What to Test](../metadata/ios/en-CA/what-to-test-1.16.0.txt).

## iOS 1.15.0 (32)

Two answer panes (#235): the Deep tab is removed on iPhone and iPad — Quick Summary and Summary remain, Auto runs no Deep reviews and Settings asks for no Deep model; a conversation saved with a Deep analysis keeps it read-only under **Earlier deep analysis** in History, in shared text, exports and Save to folder notes ([Conversation actions](#conversation-actions)). Semantic History search and **Ask your history** (#57): an on-device index (Apple's NaturalLanguage embeddings, excluded from backups, deleted with its conversation) adds meaning-based results marked Related, and Ask answers from the top excerpts with tappable sources, labelled before it sends excerpts to a non-Apple provider. **Summarize selection** (#234): select transcript lines, or touch and hold → Summarize from here, and only those lines go to the chosen provider; the last five are saved under the Summary and in exports ([Summarize selection](#summarize-selection-234)). Domain vocabularies and My terms with an on-device suggestion banner (#222; [Domain vocabularies and My terms](#domain-vocabularies-and-my-terms-222)); context-aware **Suggested prompts** under Quick, answered in an Ask card (#61; [Suggested prompts](#suggested-prompts-61)); **Export as** Markdown, plain text, SRT, WebVTT or JSON (#130; [Export formats](#export-formats-130)) and the per-conversation transcription language (#206); opt-in **Save audio recordings** with tap-to-play, excluded from backups (#55; [Save audio recordings](#save-audio-recordings-55)); automatic conversation names after Stop or Save (#221); **Delete all conversations** in History and Settings → Privacy (#220); Quick grounding for long conversations with the "Using …" note, and the output-limit notice (#114, #215). The privacy policy in [ios-privacy.md](ios-privacy.md) covers saved audio, the search index, Ask your history, vocabularies, automatic titles, selection summaries and exports; its effective date is now October 24, 2026. No SwiftPM package changed since 1.14.0 (31), so `ThirdPartyNotices.txt` is unchanged. The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.15.0.txt).

## iOS 1.14.0 (31)

Cloud AI services for summaries (#214): **Settings → Summary provider → Cloud AI** offers OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, Groq, Mistral and xAI Grok at fixed vendor addresses, each with the user's own API key stored separately in the Keychain (`WhenUnlockedThisDeviceOnly`), sent only to that vendor and kept when switching services. Nothing is chosen by default: Apple Intelligence stays the default provider and the app never picks a model — the user picks one per role from the vendor's model list. Every service is labelled "Sends your transcript to <vendor>" with a link to its privacy policy and a "Get a key from …" link. Claude uses Anthropic's native Messages API, with structured output for Auto Quick and Anthropic's server-side fallback described in the privacy policy; the others use their OpenAI-compatible endpoints. The custom server is now listed as "Custom server (OpenAI-compatible)". The privacy policy in [ios-privacy.md](ios-privacy.md) lists each vendor, its address and privacy policy, and the Claude fallback. No SwiftPM package changed since 1.13.0 (30). The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.14.0.txt).

## iOS 1.13.0 (30)

Save to folder (#53), off by default: **Settings → Save to folder** writes one Obsidian-friendly Markdown note per conversation into a folder the user picks in Files (On My iPhone, iCloud Drive, an Obsidian vault) after Stop or Save, and updates that note in place; see [Save to folder](#save-to-folder-53). Automatic language re-checks mid-recording (#199): about once a minute while people talk, with hysteresis (a new language must be heard twice in a row, a switch holds at least 90 seconds, at most four switches), it re-transcribes only the audio since the change from a rolling two-minute in-memory buffer, and **Undo** reverts the latest switch. The language picker lists every language `SpeechTranscriber` supports on the device, grouped **Installed** and **Downloadable** (#172). Speaker labels match voices by embedding across analysis passes, so someone quiet for minutes keeps their label and name (#171); the embeddings live in memory for one recording and are never saved. Summaries can use an **OpenAI-compatible** server (LM Studio, vLLM, llama.cpp, Ollama's `/v1`, OpenRouter; #52) with an optional Keychain key bound to that server, labelled "your server" or "may leave this device". **Settings → About → Acknowledgements** lists every bundled open-source package with its license (#202); no SwiftPM package changed since 1.12.0 (29). The privacy policy in [ios-privacy.md](ios-privacy.md) already covers Save to folder, OpenAI-compatible servers and the re-check buffer. The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.13.0.txt).

## iOS 1.12.0 (29)

Speaker labels on by default (#195): **Identify speakers** is on unless the user turned it off, and the speaker models are prepared at launch, when the setting is turned on and at Start — never from Stop — so a short first recording is labeled at Stop once they are ready. A speaker status line under the title appears only when something needs action (preparing, unavailable with **Retry**, a skipped pass), and Status details lists the speaker fields. Automatic transcription language (#197), the new default: **Settings → Transcription → Language → Automatic (default)**; a language the user had already picked stays fixed. WhisperKit's multilingual tiny Whisper model (about 75 MB, one-time download from `huggingface.co`, excluded from iCloud and Finder backups) identifies the language of the first speech on the device, the recorder switches SpeechAnalyzer to it once and re-transcribes the buffered start of the recording, and the "Detected … · switched" notice offers **Undo**. No audio or text leaves the device for either feature; see the privacy policy in [ios-privacy.md](ios-privacy.md) and the full behavior under [Included](#included). The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.12.0.txt).

## iOS 1.11.0 (28)

Optional on-device speaker identification (#180), off by default in this build (on by default since 1.12.0, #195): **Settings → Speakers → Identify speakers** labels microphone lines **Speaker 1**, **Speaker 2**… with FluidAudio after the first pass about 20 seconds in, and **Notes → Speakers** renames a speaker across the saved conversation, History search and exports. The speaker models download once from `huggingface.co` and are excluded from iCloud and Finder backups; recording audio is held only in memory, bounded to about ten minutes. Stop returns at once and never starts the first model download. See the speaker-identification entry under [Included](#included) for the full behavior, and the privacy policy's new section in [ios-privacy.md](ios-privacy.md). The Apple Watch target is versioned with the app but is not embedded in this build (`WATCH_EMBED` off; #181 ships on a later train). [What to Test](../metadata/ios/en-CA/what-to-test-1.11.0.txt).

## iOS 1.10.5 (27)

App Store readiness: Settings → Privacy links the privacy policy and support pages (#145). History surfaces a dismissable note when a saved conversation file cannot be decoded (the file is quarantined, never deleted) and search now covers notes with diacritic- and width-insensitive matching (#120, #139). Prompts fence transcript, notes and reference text as data (#140). No recording-path changes on iOS in this build. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.5.txt).

## iOS 1.10.4 (26)

Papercuts batch (#138): What's New keyed on the bundled notes rather than the build number, with first installs seeding the acknowledgement; share-inbox drain deletes stale manifest-less folders after 24 hours and sets failed batches aside (also aged out after 24 hours) instead of blocking later imports; transcription language persisted; one long-lived URLSession per role; automatic model-catalog refresh gated on the Ollama provider plus a key or custom server, so an Apple Intelligence install never contacts ollama.com; conversation and attachment files written with device data protection and an optional iCloud-backup exclusion covering the share inbox; History search backed by the shared `SessionSearch`. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.4.txt).

## iOS 1.10.3 (25)

Recording lifecycle: interruptions, route changes and backgrounding no longer stop capture silently; the app states why it stopped and resumes after an interruption ends, and connecting a new microphone rebuilds capture instead of stalling. Notes and title edits are debounced and flushed when the app leaves the foreground. Calendar imports redact join-link secrets and e-mail addresses from the event body and location. Apple Intelligence manual Quick uses a prose prompt with mapped error messages and a per-conversation language check. Ollama HTTP errors surface the server's own message, and Apple Intelligence prompts are clamped to the on-device window with a visible notice. Automatic reviews survive notes typing, never overwrite a fresh manual Quick answer, and use a size-scaled deadline. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.3.txt).

## iOS 1.10.2 (24)

A fresh install now defaults to on-device Apple Intelligence, falling back to Ollama with a stated reason only where Apple Intelligence cannot run. A provider chosen in an earlier build is untouched. Settings gains an optional **Server URL** so Ollama requests — summaries, Quick, Deep and speech correction — can go to an Ollama server you run on your own network instead of ollama.com. Use the computer's `.local` name; no API key is needed, and a saved Ollama Cloud key is never sent to a server you entered. The destination host is shown in the status text. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.2.txt).

## Attributed summary input

Summary and Quick (and Deep, on macOS) all read the transcript with speaker labels and the user's typed notes
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

- Semantic History search and **Ask your history** (#57). The History search field keeps the keyword
  search and adds on-device semantic ranking. `HistoryIndex` (Core) chunks each conversation's
  summary, notes and transcript into short passages. A transcript passage uses the language its lines
  were transcribed in (#206; a language change starts a new passage), and any other passage's language
  is detected with `NLLanguageRecognizer`. It then stores a vector per passage from `NLEmbedding`: the mean of its nouns'
  word vectors (verbs, auxiliaries and nouns every meeting uses, such as "meeting" or "week", are left
  out), or the sentence model where only that exists. Small talk with fewer than three such words gets
  no vector. Only vectors, passage numbers and conversation/passage fingerprints are stored — the text stays in the
  archive — in `Search Index/` beside `Conversations/`, always excluded from backup, versioned (a new
  format or embedding method rebuilds it), and any damaged file is re-embedded. It is reconciled with
  the archive after a reload and updated a few seconds after saving stops, off the main thread.
  Unchanged passages reuse their stored vectors even when an inserted summary changes their positions;
  text, source, transcription-language or embedding-method changes invalidate reuse. Format 2 rebuilds
  older indexes once. Duplicate passages share one embedding attempt per changed save, including when
  a model is unavailable; unavailable passages are retried on a later changed save. This reduces repeated
  embedding work without changing semantic language coverage (#223).
- **Deletion.** A deleted conversation's vectors are removed at once by its `conversationDataOwners`
  entry (`forgetSearchIndex(ids:everything:)`), so Delete and Delete all conversations (#220) both
  take them. A sync still running stops at its next conversation and never embeds a deleted one again.
  macOS Clear history runs the same owner list. Searches always read the current History, and results
  computed before a deletion are never shown; opening a conversation that is no longer in History is
  refused, so a stale row cannot write a deleted conversation back.
- **Results.** The keyword and semantic orders are fused (reciprocal-rank fusion): every keyword match
  stays, and at most eight conversations are added by meaning alone, marked **Related**. A passage is
  related only when its similarity is at least 0.5 *and* at least 0.1 above the typical passage for
  the same query (0.55 when there are too few passages to tell). The thresholds are calibrated on
  Apple's English word vectors: ten unrelated queries relate to nothing, while seven of eight
  paraphrases are found. Each row shows the matching excerpt. A passage in a language with no
  on-device model gets no vector, so that conversation is found by keyword exactly as before.
- **Ask your history** sends only the top six retrieved passages and the question to the selected
  summary provider with the Summary role's model (iOS has no Deep role since #235). It sends at most two passages per conversation, and
  only passages that hold the question's words or pass the same relevance test. The prompt is fitted
  to about 8,000 characters, which suits Apple Intelligence and the 4,096-token default context of
  smaller Ollama servers. The answer cites excerpt numbers, shown as tappable sources. Apple
  Intelligence answers on the device; for Ollama, an OpenAI-compatible server or a cloud AI service,
  the footer names the destination before anything is sent. Stop ends a request for good: a stopped
  answer never overwrites the next one.
- Foreground microphone transcription using Apple's on-device SpeechAnalyzer. Language assets
  download on first use. Unsupported device/language and permission errors are shown in the app.
  **Settings → Transcription → Language** is remembered across launches, so a language chosen for
  daily meetings is still selected after a relaunch instead of reverting to the device's. Below
  **Automatic** and **System**, the picker lists the union of languages supported by the available advanced speech and on-device
  dictation modules for this device, read at launch, as **Installed** (speech model already on the device, per
  `AssetInventory`) and **Downloadable** (downloads from Apple on first recording), with the common
  languages first (#172; rules in Core's `TranscriptionLanguageCatalog`). Where that list is
  unavailable, such as the simulator, it offers the common languages. A fixed language the OS no
  longer lists stays selectable. Automatic switches among the same supported list, so any language it
  can switch to can also be chosen. The list compares BCP-47 identifiers, so a device on `en_US` is
  offered "System (en_US)" once rather than also listing "English (US)".
- Automatic transcription language (#197), the default: **Settings → Transcription → Language →
  Automatic (default)**. A user who had already picked a language keeps it fixed after the update;
  everyone else starts in Automatic. SpeechAnalyzer needs one locale up front and cannot detect or
  switch languages, so a recording starts in the device's language and the app identifies the
  spoken language on the device with WhisperKit's multilingual **tiny** Whisper model (about 75 MB:
  73 MB of Core ML models and a 3 MB tokenizer). The model downloads once from `huggingface.co`,
  started by the first speech of a recording rather than at Start, into Application Support
  (`LanguageModels/`, excluded from iCloud and Finder backups); later launches load it from the
  device with no network request. No audio or text is sent anywhere. Recording never waits for it.
  While recording, the audio the transcriber accepts is copied into a 16 kHz buffer that keeps the
  trailing two minutes (about 7.7 MB plus one 10-second block, in memory only; older audio is
  released in whole blocks as the recording goes on, #199). Once 8 seconds of speech have been heard (or 30 seconds
  have passed since the first recognized speech), up to 30 seconds from just before that speech are
  checked. Without recognized words, eight seconds of audio activity within the trailing 30 seconds
  can start the first check and model preparation; isolated sounds do not start a download (#216). `LanguageDetectionPolicy` switches only when Whisper is at least 80% sure, the
  language differs from the one being transcribed, and SpeechTranscriber supports it; Whisper's
  "zh" (Mandarin) becomes zh-CN, or zh-TW on a device in Taiwan, Hong Kong or Macao, and never the
  Cantonese zh-HK model. To switch, the recorder installs the new locale's speech assets if needed
  while the old transcriber keeps running, then swaps the analyzer without stopping the microphone:
  audio arriving during the swap is parked and sent to the new analyzer, so none is lost. The new
  analyzer first hears the recording from its start (or from the oldest audio still held). Its lines for the audio before the
  switch are held back while the earlier lines stay on screen and on disk, and replace them in one
  step once it reaches live speech (or, if the recording stops first, replace only what the replay
  covered), so a crash or a failed replay never loses the early transcript. The unfinished line at the
  switch is kept as a line of its own. Offsets, speaker labels and later lines stay on one timeline.
  When none of that audio is held any more the switch cannot re-transcribe anything: the old
  analyzer then finalizes what it heard up to the switch, the new one continues the timeline, and
  the notice says "switched for new speech". The status area shows "Detected Chinese · switched"
  with **Undo**, which pins the language from before the switch. While recording it switches back first, re-transcribing what
  is still buffered, and the notice stays until that has worked (a failure says to try again). While
  stopping, the tap waits for Stop to finish; after Stop it restores the lines the switch replaced,
  touching only that recording's own lines (Apple Watch lines and later recordings stay) and
  keeping the line that spans the switch. A recording that resumes the conversation, after a call or
  Stop and Listen, starts in the switched language, keeps the notice and goes straight to re-checks.
  Apple Intelligence's language check uses the switched language. If the model cannot be loaded (offline first use), recording
  continues in the starting language and the status line says language detection paused; the next
  recording tries again.
  **Status details** on the Quick Summary pane lists the mode, the recording's language, the first
  check's result, the re-checks (switches so far, and the latest result or why one was skipped) and
  the model state. The language line appears in the status area only while there
  is news (preparing, checking, switching, paused, a failed switch) or a notice with Undo. UI-test
  launches substitute a language model that loads at once and never switches
  (`LISTENTOME_LANGUAGE_MODEL_FIXTURE`, DEBUG simulator builds only, set with the speaker fixture by
  `useModelFixtures()`), and the unit-test host one that never loads, so no test downloads Whisper.
  Apple Watch imports in Automatic use the already-downloaded language model (#200), sampling up to
  30 seconds of voiced audio within the first five minutes available. At least eight seconds and
  80% confidence are required; otherwise the device language is used. Import never downloads the
  language model. The chosen locale is saved before transcription and reused across retries, new
  chunks and app launches, even if Settings changes. Fixed language choices skip detection.
  Older partially transcribed recordings inherit their saved transcript language. Watch remains
  excluded from distribution pending the physical-device acceptance in #181.
- Re-checking the language during a recording (#199), Automatic only. After the first check,
  `LanguageTracker` (ListenToMeCore, with `LanguageRecheckPolicy`) re-checks the trailing 30 seconds
  once a minute of recording time, only when that window holds at least 10 seconds of speech, so
  silence skips inference. Activity combines reported speech with audio energy, without double-counting
  overlapping intervals (#216). Every five seconds, a background task scans new complete 20 ms frames
  from the existing bounded audio buffer; activity above RMS 0.02 can trigger checks even when the
  recognizer produces no words. Energy is not a speech classifier: loud noise can qualify, but model
  confidence and the existing switch policy still decide whether to change language. A re-check
  overdue by a whole interval needs only 4 seconds of activity. The scanner pauses outside active
  foreground recording, and Stop cancels it without waiting for model preparation. Re-checks pause in Low Power Mode, while the app is in the background and
  while the device is hot (serious or critical thermal state); the first check is not affected.
  Re-checks run quietly, without a status line. Hysteresis: a confident (≥ 80%) different language
  only makes a candidate, and a check 20 seconds later must hear the same language again before the
  transcriber switches; a check that hears the current language, is unsure or hears a third language
  drops the candidate, and a candidate unconfirmed for a minute expires. A switch stays at least 90
  seconds, a recording switches at most four times (the first check included) and then stops
  re-checking, and a locale whose speech model could not be prepared is not tried again in that
  recording. On a confirmed switch, ten-second chunks since half a window before the current language
  was last heard (never before the previous switch, at most 12 chunks, each with at least 4 seconds of
  speech) are checked to find where the language changed: the change is the end of the last chunk
  that still heard the old language, so speech after it in a chunk too quiet to check is transcribed
  again too. Transcribing again starts there, moved back to the start of a line that spans it (or past
  a line whose start is no longer held), and never in the 10-second block the buffer is about to
  release. That start is chosen at the switch itself, after the new locale's speech assets are ready
  (a download can take a while), from the audio still held then, so a slow download moves the start
  later instead of losing the replay. The replay's first buffer is stamped with that recording time,
  so its lines keep the recording's timeline. The recording's own lines from that point (by id; never
  Apple Watch lines merged into the conversation meanwhile) are held back and replaced in one step
  where the first of them was; every other line stays, and earlier lines (including an earlier
  switch's) are never touched. The notice reads "Detected French from 2:05 · switched" whenever
  transcribing again did not start at the recording's start, the first switch included. It and
  **Undo** are for the latest switch; earlier switches are kept. Undo is not offered while a
  re-check is replacing the transcriber, since the switch back would fail and the new notice would
  then replace the old one; it returns once the switch settles. Undo while recording hears the same span again in the
  previous language when its audio is still held, otherwise it restores the lines the switch
  replaced; after Stop it restores only that span. A recording's own lines are found by time from
  its start rather than by index, so an Undo in a resumed recording, which first restores the earlier
  recording's lines, hears all of this one again exactly once. An in-flight check never switches once Undo has
  started, and an Undo pins the language, which ends re-checks. A switch is noticed one to two
  minutes after the language changes; the replay span is bounded by the two-minute buffer.
  Genuinely mixed speech within one sentence is out of scope: SpeechTranscriber transcribes one
  locale per analyzer, so running two side by side would double the Neural Engine load and still
  give each language's words as nonsense in the other, with no per-word language to merge on.
  Multilingual Whisper transcription (macOS's opt-in engine) is the possible route on iPhone (#205).
- Partial and final transcript text. Everyone picked up by the microphone is labeled **Microphone**
  unless speaker identification is on. Unfinalized text is retained and labeled accordingly.
- Speaker identification (#180), on by default since #195 (a stored choice to turn it off is kept):
  **Settings → Speakers → Identify speakers**. It runs on this device with FluidAudio, the same
  runtime library as the Mac, and uses more battery while listening. The unreleased #310 fix uses
  LS-EEND DIHARD II stateful streaming for the live microphone; Mac and Watch/file imports keep
  the offline pipeline. See [model behavior and acceptance](speaker-identification.md). Its models download once
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
  downloads them. These simulator substitutes establish control behavior only: `make mac-test`
  additionally runs real CoreML voice fixtures through the actual production iOS factory. While recording, the audio the transcriber
  accepted is copied into a 16 kHz buffer; about every 20 seconds (never sooner than the previous
  pass took) a pass re-analyzes only the audio since the last one plus a one-minute overlap
  (`SpeakerAnalysisPolicy`). In the unreleased #310 fix, only unseen samples enter LS-EEND; the
  overlap is returned for transcript alignment. A model slot is stable inside one recording epoch,
  including when a person stays quiet. The tracker keeps an edited name attached to that slot.
  A lost audio gap or reset starts a fresh epoch rather than guessing an old name from a reused slot.
  Recurrent voice state and at most ten minutes of prediction probabilities stay in memory, never
  persisted, and are reset after the run ends. Published 1.18.0 instead re-clusters each window and
  matches shared time and unmatched voice embeddings; short turns can incorrectly merge (#310).
  Stop returns at once; a final pass then labels the last words while the
  app stays open, queued behind any pass still running. The streaming final flush also runs when
  no new samples have arrived since the last pass; padding is clipped to captured time. Its result is dropped if a
  new recording or another conversation has started. Backgrounding also cancels an already-started
  final pass and clears the recording buffer without waiting. Model work already in flight may finish
  with its temporary input copy, but its result is discarded; queued passes retain their original
  recording token and cannot analyze a later run (#188). The final pass is skipped while the models have
  not loaded yet, so Stop never starts or waits for the download; with the models ready, a recording
  shorter than the first periodic pass is labeled at Stop (#195). On every periodic tick, audio no later window can reach is released, so
  at most ten minutes (about 38 MB) is held even when passes keep failing, and only the last minute
  while the models are unavailable.
  Speaker identification saves no audio. Lines are matched to speakers by SpeechAnalyzer's audio time ranges and become
  **Speaker 1**, **Speaker 2**…; a line no speaker covers for at least 30% of its length keeps
  **Microphone**. **Notes → Speakers**, or long-press an identified transcript line → **Rename speaker**, renames a speaker everywhere: the saved conversation, the
  transcript in History, search and exports all use the name. Renaming or relabeling starts no AI
  work, and Auto summaries do not re-read lines whose only change is the label; summaries pick the
  names up the next time they are generated. Prompts keep **Microphone** lines as `You` and pass
  named speakers through unchanged. If the models cannot be loaded (offline first use, a blocked
  host), identification pauses with the reason in the status area and no further passes run until
  you tap **Retry** or start a new recording. Limits: overlapping speech and short utterances are
  often left as **Microphone** or attributed to whoever spoke longest; the live model has ten
  speaker slots. An observed three-person synthetic sample still merges two voices under both
  the earlier model and this fix; reliable group-conversation separation is not established.
  Its synthetic regression fixtures do not establish every language, voice or noisy room. Physical-device speed/battery and original tester audio remain pending. A voice is not recognized
  across recordings, so after Stop/Listen (or an interruption) new voices continue the numbering
  (Speaker 3, 4…) and can be renamed to merge them. The 1.20.1 (41) beta pauses background labeling
  without ending the speaker run or identities. Foreground catch-up uses only the bounded last ten
  minutes; older background lines may remain Microphone. More than two hours of one recording is
  not analyzed further. See [screen lock speaker limits](speaker-identification.md#screen-lock-continuity-339).
- Automatic titles (#221): after Stop, Save, a finished Apple Watch recording or a return to the
  foreground, a conversation still named "New conversation" or "Apple Watch · <date>" with about
  30 final words is named in the background. `MobileSession+AutoTitle.swift` takes the title from:
  1. its Full summary, with no model call;
  2. the summary provider, only when it is Apple Intelligence (the default) or the user's own
     Ollama server (`ConversationAutoTitle.mayAskModel`). It is asked with a tiny fenced prompt of
     the transcript's first 2,000 characters and answers in the conversation's language. Ollama
     Cloud, a Cloud AI service or an OpenAI-compatible server is never asked for a title, so Stop
     sends nothing;
  3. on-device NaturalLanguage keywords.
  Naming never runs while recording, preparing or stopping.
  `ConversationAutoTitle` in Core holds the prompt, the cleaning (at most six words, no quotes,
  emoji, Markdown or trailing punctuation, nothing clearly in another language) and the replace
  rule. `SessionRecord.titleState` records where a title came from (`placeholder`, `automatic`,
  `user`, `calendar`). A record saved before it counts as a default only when its title is exactly
  "New conversation", or "Apple Watch · " / "Conversation — " followed by a date that parses; any
  other title (including "Imported notes") is treated as the user's. A naming that finds nothing
  stores `attemptedWords` and waits until the transcript doubles or grows by 100 words. Import from
  Calendar replaces a default or automatic name (`calendarMayReplace`). The title field marks
  edits as the user's and cancels a naming under way. A naming that finishes after the user
  renamed the conversation, or switched to another one, is applied only if that record still
  has its default name. An automatic title is refined at most once, after the transcript has
  tripled. The Save to folder note is rewritten in place (its file name is keyed by the
  conversation). Unit tests never reach a real model: they inject `onDeviceProviderOverride`.
  Settings → Conversations → **Name conversations automatically** (on by default).
- Editable titles and notes; atomic local saves after finalized utterances, explicit Save,
  save-before-New, local History, restoration on launch and Markdown through the share sheet.
  Title and Notes typing is saved about a second after you stop typing, and is flushed when
  recording stops or the app leaves the foreground — before the system can suspend it — so a
  keystroke never costs a full archive write. A
  save whose bytes are identical to the last one is skipped, and History is kept in memory: the
  conversation files are read on launch, after a delete and after a share-sheet import, not on
  every save.
- On-device Apple Intelligence summaries by default, or Ollama summaries — Ollama Cloud, or an Ollama
  server you run — a cloud AI service with your own key (OpenAI, Anthropic Claude, Google Gemini, DeepSeek,
  OpenRouter, Groq, Mistral, xAI; see [Cloud AI services](#cloud-ai-services-openai-claude-gemini-deepseek-openrouter-groq-mistral-xai)),
  or an OpenAI-compatible server you enter (LM Studio, vLLM, llama.cpp, OpenRouter;
  see [OpenAI-compatible server](#openai-compatible-server-lm-studio-openrouter-vllm)), with streamed
  results and secure API-key storage.
  Apple Intelligence accepts up to 8,000 characters (`PromptBudget.appleIntelligenceCharacters`, the
  shared cap macOS also clamps its Apple prompts to); Ollama and OpenAI-compatible assembly allows up to 60,000.
  A configured custom-server capacity also checks the complete request locally before sending,
  so its actual limit may be lower. These assembly caps are
  charged on the *fenced* conversation, not the raw text. A Summary that does not fit is rejected
  explicitly. Quick answers a conversation that does not fit from what does (#114,
  `OnDemandGrounding.excerpt`). A Summary generated in this session stands in for exactly the lines it
  read (`MobileAnswerNotices.summaryCoverage`, by segment ID, so re-transcribed lines are not covered);
  of the remaining speech — with no Summary, all of it — the start and the latest part are sent, and
  the panel says what was used ("Using your Summary of the first ~10 min, the ~3 min after it and the
  last ~5 min of the conversation (~20 min in between left out)."). A Summary restored from History,
  edited, cut off at the output limit or shortened to fit is sent but never claimed to cover anything;
  a long one keeps its end, where the decisions and actions are, and the panel says so. Notes keep
  what the speech leaves (at least a quarter), and an oversized latest line keeps its most recent
  words, so the message never exceeds the budget. On Apple Intelligence the budget is what the window
  leaves after the system prompt and the answer's reserve. An answer that stops at the model's output
  limit (`finish_reason`/`done_reason` `length`, Claude `max_tokens`) keeps its text and the panel shows
  "The answer was cut off at the model's output limit." (#215). Each line belongs to the exact text it
  describes, so it disappears when Auto or anything else replaces that text; both are for this session
  only and are not saved. AI output needs review.
- Prompts separate data from instructions (#140). The conversation a manual Summary or
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
- In the 1.20.1 (41) beta, established recording continues through screen lock/background while
  optional AI pauses; a pending Start is cancelled. Audio interruptions (call, Siri, alarm) still
  stop and save with a reason. When active and permitted by the system, recording can resume after
  an interruption; otherwise the status says to tap Listen. Connecting or losing a microphone mid-recording
  (AirPods, a Bluetooth headset, a wired mic) rebuilds capture on whatever input remains instead of
  ending the meeting; one physical device change posts several notifications, so rebuilds within
  half a second collapse into one and a rebuild is skipped when the input format has not actually
  changed. Only a rebuild that fails stops recording, with the reason shown. The screen
  stays awake during active recording. No raw audio is saved unless **Save audio recordings** is on
  (off by default; see [Save audio recordings](#save-audio-recordings-55)).
- **Settings → About**: version and build, and **Acknowledgements** — every open-source package
  bundled in the app (WhisperKit, FluidAudio and their SwiftPM dependencies) with its full license
  text, read from the same `App/ThirdPartyNotices.txt` the macOS app ships (#202).

System/call audio, Mac sync, audio-file import and WhisperKit transcription are not included.
Background continuity is included in TestFlight 1.20.1 (41), with [physical acceptance pending](recording-continuity.md).
A local/LAN Ollama server is supported only when you
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
confirmation and removes that conversation's transcript, notes, original attachments, saved audio, search-index entry and every saved AI output (Summary, Quick
Summary, selection summaries and any earlier Deep analysis). Deleting
an active conversation creates an empty active snapshot so the deleted content does not reappear
on restart. Other conversations are preserved.

**Delete all conversations…** (#220) sits at the bottom of History (hidden while a search is typed)
and in Settings → Privacy. The alert names the count ("Delete all 3 conversations?") and says it
cannot be undone. The button is disabled while recording, preparing, stopping or generating. The
open conversation starts over as "New conversation". Delete and Delete all run the same code path,
`MobileSession.eraseConversations` in `iOS/MobileSession+Deletion.swift`. The archive is the commit
point: Delete all calls `SessionArchive.clear()`, which also removes history files set aside as
unreadable. After that it runs every entry of `conversationDataOwners`, a list of Core
`ConversationDataOwner`s:
- attachments and their temporary preview copies;
- Apple Watch audio, tombstoned so a part the watch sends again is discarded;
- shared-inbox folders already imported, which would otherwise import again (Delete all also drops
  quarantined shares);
- the Save to folder queue.

Every owner runs even if one fails, and the message names what is left. New per-conversation
storage (saved audio #55, the search index #57) adds an owner there, so both deletes remove it.
Recordings still waiting from Apple Watch are kept, as are shares not yet imported. Notes Save to
folder already wrote are never touched. The directories keep their backup-exclusion flags; only
their contents go.

The **Live** tab shows the transcript above a full-width **Quick Summary**; the **Summary** tab holds the
full Summary (on iPad and in a wide window it sits beside Live). Landscape and accessibility text use a
scrollable page. Start/Stop remains available in either tab. **More → Full summary** also offers
**Summary** and **Quick Summary**. Each result is stored separately, restored with its conversation and
included when sharing. Requests use the selected provider and preserve previous completed output on
failure or cancellation.

iOS has no Deep pane (#235); Deep stays on macOS. A conversation an earlier version saved with a Deep
analysis keeps it: opening it from History shows it read-only under the Summary as a collapsed
**Earlier deep analysis**, and it stays in shared/exported text and Save to folder notes. Nothing new is
ever written to it.

### Summarize selection (#234)

The transcript has a **Select** mode: the checklist button on the Live transcript (or **Select** in the
expanded transcript) opens the full-height transcript with a circle beside each finished line. Tap
lines to toggle them, or drag down the circles to select a range. Touch and hold any finished line
for **Summarize from here** (that line through the latest), **Select from here** or **Copy**. A live
line that may still change is never selectable, so this works while recording and on a conversation
reopened from History.

**Summarize selection** sends only the selected lines — each with its time and speaker label, as
`[1:02] Alex: …` — to the provider chosen for Summary (`SelectionSummaryPrompt`, fenced as data with
`PromptData.notice`; notes, the Summary and unselected lines are not sent). Apple Intelligence runs on
the device; a cloud AI service, Ollama or an OpenAI-compatible server is used only when it is already the
chosen summary provider. The bar names the destination, and so does the sheet: on Apple Intelligence it
starts at once; with any other provider it shows "Sends the selected lines to <destination>" and a
**Summarize** button and sends nothing until that is tapped. When no provider can run (no key, no
server, Apple Intelligence unavailable, a response already generating), Summarize selection and the
touch-and-hold **Summarize from here** are disabled with the reason (VoiceOver gets both line actions too).
A running selection summary holds `isSummarizing` like a manual Summary or Quick request, so each
blocks the other, Auto's full reviews wait, and **Cancel** (or the main Cancel summary) stops it with
"Cancelled.". The sheet's state (`MobileSelectionRun`) is keyed to the request and the conversation and
reset whenever a sheet opens; every run carries a generation token, so a cancelled or replaced run can
neither stream into nor finish the next one. The sheets are presented from the workspace (Live panel)
and from the expanded transcript, views that survive rotation and Dynamic Type layout changes. Selected
lines that disappear (a language Undo or re-transcription) leave the selection. Transcript text stays
selectable everywhere except in Select mode. In Select mode a tap toggles the line and the saved-audio
play controls (#55) are hidden; outside it, a tap on a line with saved audio plays from there, as before. A selection longer than the
provider's window (Apple Intelligence's 8,000 characters, or 60,000) keeps its first and latest lines
(`OnDemandGrounding.select`) and the sheet says "The selection was too long for this model…"; an answer
cut off at the output limit says so too. The sheet offers **Copy**, **Share** and **Add to notes**
(appended as "Selection summary (1:02–1:15 · 2 lines):"). The last five are saved with the conversation
(`SessionRecord.selectionSummaries`; older records decode unchanged, and every copy of a record — a new
title, its languages, an Apple Watch recording — keeps them) and listed under the Summary. They are
exported under **Selection summaries** in Markdown, plain text and readable share text, as `selectionSummaries` in JSON
(see [export formats](export-formats.md)) and in Save to folder notes. The active domain vocabulary and
My terms (#222) reach the prompt as the same "Context for this session" guidance Quick gets
(`vocabularyGuidance`, without summary headings, the smaller share on Apple Intelligence, its glossary ranked by
the selected lines), charged to the budget.

## Domain vocabularies and My terms (#222)

**More → Settings → Vocabularies** lists seven presets — Medical, Legal, Software & Cloud,
Engineering, Finance, Sales and Education & Research — each with a curated English list of a few
hundred terms and a focused Simplified Chinese list of 50–60 terms the project wrote itself (`Sources/ListenToMeCore/Resources/Vocabularies/*.json`; no
licensed dictionaries), plus **My terms**: people, products and company jargon in any language. Each
preset has a **Use by default** switch, a description, and (Medical) the note that the app is not a
medical device. My terms can be added, edited (tap), deleted (swipe), imported from a text file (one
term per line, `#` comments ignored) and exported as plain text; long-pressing a transcript line opens
**Add to My terms…** with that line's distinctive words and names one tap away. Settings are stored in
`UserDefaults` (`vocabularySettings`), so a device backup includes them like any other setting.

The active vocabulary for a conversation is the default presets, any preset added from the banner for
that conversation, and My terms. It is used in three places:

- **Recognition.** `ActiveVocabulary.recognitionTerms()` takes at most 100 phrases of up to three
  words (Apple's guidance for `AnalysisContext.contextualStrings`): My terms first — up to 60 when a
  preset is on; past that, the ones already said in this conversation and then the newest, so a term
  added mid-meeting always makes it — then the presets' leading terms, which are the ones speech engines
  mis-hear most. `MobileRecorder` sets them on the `SpeechAnalyzer` before and again after it starts
  (the documentation does not promise that a context set before `start` survives it), again with
  `SpeechAnalyzer.setContext(_:)` when they change while recording (no restart of the microphone), and
  on the new analyzer a language switch creates (#197/#199); a change made while that analyzer was being
  prepared is set again once it is installed. Apple Watch recordings are transcribed
  with the default presets and My terms. Verified API: `SpeechAnalyzer.setContext(_:)`,
  `AnalysisContext.contextualStrings: [ContextualStringsTag: [String]]` in the iOS 27.0 / macOS SDK's
  `Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface`; Apple's documentation
  describes the bias for `DictationTranscriber`, so how much it helps `SpeechTranscriber` is checked on
  a device (see the manual smoke test), not assumed. The [October 26 controlled evaluation](vocabulary-biasing-evaluation.md)
  found identical 36/64 target-presence results with vocabulary off/on through the production adapter
  on iPhone and Mac. Custom Dictation models added at most one target over contextual Dictation in
  this fixed dataset, so no engine switch was integrated. The live app checks remain pending (#236).
- **AI speech correction.** The correction request gains a `glossary` field — My terms (at most half)
  and then preset terms, each ranked by how closely something in the phrase spells it, at most 40 —
  and one instruction: use the glossary spelling for a near-miss and never insert a term nobody said.
  The glossary is built off the main thread from an index prepared once per vocabulary
  (`VocabularyPrompt.CorrectionIndex`). The validator (`CorrectionGuard`) still refuses any change to
  numbers and negation; a term's own digits or negation are exempt only inside its span, and only when
  the original said the same tokens in a span spelled like it ("e c2" → "EC2" passes; "show rate" →
  "no-show rate", "with prejudice" → "without prejudice" and dropping the "2" of "for 2 vendors" do not).
- **Summary and Quick.** The domain's description and a glossary (My terms, then terms heard
  recently, then the rest) are appended as "Context for this session" — at most 1,500 characters, or
  400 on Apple Intelligence, where the compact form names the domain in a word and keeps at least half
  the space for the glossary, so My terms are never squeezed out. Its characters are charged to the
  same budget as the transcript: the Summary cap, and the on-demand Quick excerpt budget
  (`OnDemandGrounding.oneShotBudget`). With **Organize summaries by domain** on, only Summary (and the
  automatic Summary review) follows the domain's headings (Medical: History / Findings / Plan;
  Engineering: Decisions / Actions / Risks; Sales: Customer needs / Objections / Next steps…); Quick gets
  the domain and glossary without them. On the Mac the headings reach only the Listener and automatic
  Summary reviews (`MeetingSession.summaryGuidance`), never Quick or Deep.


**Simplified Chinese (#238, unreleased).** The transcription language selects the preset terms and
classifier description: `zh`, `zh-CN`, `zh-SG` and explicit `zh-Hans` use Simplified Chinese; Traditional
Chinese (`zh-Hant`, Taiwan, Hong Kong) and other languages keep the English lists. My terms stays in
whatever language you entered. Recording uses its current language, including an Automatic switch and
Undo; a reopened conversation's prompts use its saved current language. The on-device classifier
matches Chinese terms inside continuous sentences and separates adjacent Latin jargon, bounds its
recent window with NaturalLanguage word tokens, and uses the Simplified Chinese sentence embedding
when installed (the stricter six-term rule applies without it). UI names, safety notices and summary
headings keep their existing English wording. These curated lists are a starting vocabulary, not
proof of improved recognition accuracy; physical-device comparison remains required under #236.

**Suggestion banner.** After about a minute of final speech (150 words), and again every 50 words,
`VocabularyClassifier` checks the recent speech on the device, off the main thread, with no model call:
a preset needs at least 4 different terms at 2 weighted hits per 100 words (terms shared by several
presets count less), must lead every other preset by 1.5×, and must be among the top two by Apple's
NaturalLanguage sentence embedding (similarity to the preset's description, minus that of everyday
small talk); with no embedding on the device it needs 6 different terms instead. Abbreviations count
only in capitals, so "bid" is not BID. The thresholds keep false positives low: everyday chats about a
doctor's visit, a lease or a car purchase, an ordinary team meeting and an English/Chinese mixed chat
never trigger it in the fixtures (`Tests/ListenToMeCoreTests/VocabularyFixtures.swift`). The banner —
"Sounds like a medical conversation — add the Medical vocabulary?" with **Add**, **Not now** and
**Don't suggest Medical again** — never blocks the screen and never turns anything on by itself; Add
applies to this conversation at once and then offers **Use by default**. Each preset is offered at
most once per conversation; a preset added for one conversation is saved with it and restored when reopened, including after
relaunch. New conversations start without those additions; device-wide defaults and My terms still apply. **Suggest
vocabularies** turns it off.

Limits: languages other than Simplified Chinese keep the English lists; how
strongly `SpeechTranscriber` honors contextual strings is still to be measured on a device (#236);
Auto Quick receives the active domain and a bounded glossary, without summary headings (#237). The
glossary reaches only the provider you chose. Deleting a conversation also removes its saved additions.

## Suggested prompts (#61)

Quick Summary can show **Suggested · from context**: two or three one-tap requests drawn from the
conversation, such as "Who owns the Thursday review?". They are never a model call of their own. They
ride on a pass that already runs — the Auto Quick check while Auto is on, or a manual Quick refresh
you tap — so with Auto off and no refresh there are none, and no cloud service is called to make
them. On Ollama, OpenAI-compatible servers and cloud AI services they arrive in the Quick decision's
optional `suggestions` field. On Apple Intelligence the prose prompt asks for a final "Suggested:"
heading (always in English) followed only by `> ` lines. It is read strictly: the block must be the
last section, `>` is the only suggestion marker, and a heading anywhere else, a blank or other line
inside the block, or a second heading means no chips — the whole answer stays the recap, so a
suggestion block can never take a takeaway.

Each chip is at most 60 characters and one line, shown as plain text; duplicates, placeholders,
links, JSON and markup debris are dropped (`SuggestedPrompts`). Auto replaces chips at most every 20
seconds so a chip does not change under your finger; a manual refresh replaces them at once.

A tap is a **separate ask** (`MobileSuggestedAsk`), not a summary: it sends the literal text to the
Quick model with the copilot prompt (`MobileSession.askSystem`) over the notes and the speech that
fit the provider (`OnDemandGrounding`, as for an on-demand Quick answer, so a long conversation is
answered from what fits rather than refused), then `PromptBuilder.askInstruction`. The answer streams
into a small **Ask card** under Quick Summary — the question in bold, the answer below it, Cancel
while it streams and Close to dismiss — and the app stays on Live. It never replaces Quick Summary
or Summary on screen or in the saved conversation, never counts as a completed review and never touches
Auto's queued reviews or recommendations. The answer is kept in memory only and is not saved with
the conversation. A tap that cannot be sent (a response is generating, nothing has been said or the
provider is unavailable) sends nothing, says why and keeps the chip. A chip is used up only once its
answer has arrived, then it leaves the row and is not suggested again in that conversation; a failed
or cancelled ask can be tapped again. Nothing is sent without a tap.

A new or reopened conversation clears the chips and the ask; a provider or model change clears the
chips, drops chips from a refresh that was still running under the old model, and stops an ask in
progress. Stop keeps the chips, because the conversation can still be asked about. The chips stack
vertically with tap targets of at least 44 points, so they wrap at phone width and at accessibility
text sizes.

## Save to folder (#53)

**Settings → Save to folder** is off by default. Turning it on opens the Files folder picker; the
chosen folder (On My iPhone, iCloud Drive, an Obsidian vault) is kept as a bookmark. Each time
`MobileSession.save()` writes a conversation to History while the session is idle — Stop, Save, and
any later summary, title, notes or speaker-name change — `exportToVault` queues its note. Live
transcript lines during recording are not written to the folder. `MarkdownVault` builds the note
(YAML front matter with title, date, duration, BCP-47 language, speakers, the `listentome` tag and the
conversation ID; then Summary, Quick summary, Deep summary (only when the conversation has one — on
iOS, an earlier version's), Selection summaries, Notes, a transcript with `[mm:ss]`
timestamps and speaker names, and attachment names). The file is named
`<yyyy-MM-dd HHmm> ListenToMe <key>.md`, where the key is the first eight hex digits of the
conversation ID; an existing note is found by that suffix and its `listentome_id` front matter, so a
renamed conversation or a reopened app updates it in place. A file with that name but another (or no)
`listentome_id` is never overwritten: the note takes the whole-ID name instead
(`… ListenToMe <32 hex>.md`), and a foreign file under that name too is reported as a per-note failure.
A note the user renamed in Obsidian is not searched for (that would mean reading every note in the
vault); it is left alone and the next update writes a new note under the usual name.
`MarkdownVaultWriter` writes through `NSFileCoordinator` with an atomic replace and skips unchanged
bytes. Failures are kept visible, never dropped. Folder failures — a moved or deleted folder or lost
access ("choose the folder again"), a full disk — stop the queue; per-note failures — a legacy
`.icloud` placeholder (a download is requested), a name held by another note, any other error — keep
that note queued and let the rest be written. Either shows in Settings and as an orange line under
the conversation title, with Retry; notes waiting for a folder show there too. The IDs of unwritten
notes persist across launches; the next save or Retry rebuilds them from History. Apple Watch
conversations are written when the drain saves them. **Save all conversations now** and Retry skip
the conversation being recorded. Deleting a
conversation drops its queued note, so it is never written afterwards; a note already in the folder
stays, because the folder belongs to the user. On the Mac, the note's date is the conversation's first
checkpoint, quitting waits up to five seconds for the last note, and waiting notes are retried at launch.

The front matter's `language` is the conversation's own (#206), never the current setting: every
`SessionRecord` carries `language` (the current one) and `languages` (every language its lines are in,
in order of first use), as optional fields, so records written before decode with both missing. On iOS
each `TranscriptSegment` also keeps the `language` it was recognized in (live lines, replayed lines
after a switch, Apple Watch lines; a speech correction keeps it), and
`ConversationLanguages.resolving(recorded:segments:)` derives `languages` from the lines whenever every
line has one: a first check that transcribes everything again drops the starting language, and an Undo
— which restores only the lines before the switch (`LanguageDetectionPolicy.restoring`) — keeps the
switched-to language while lines after the switch are in it (review of #233). The current language
comes from `MobileLanguageDetection.languageChanges`, the languages recorded while the conversation
was open: each recording's at `beginRun`, an Automatic switch's, an Undo's (the original language) and
Apple Watch lines'. Lines saved before per-line languages cannot say, so nothing already listed is
dropped for them. A watch conversation that is not open gets its language when the drain saves it. On
the Mac the capture's language is noted when Listen starts (and for audio-file imports); WhisperKit in
Automatic mode reports no language, so none is recorded. A conversation never transcribed, or saved
before #206, has no `language` line (and **Save all conversations now** and Retry write each record's
own value).

## Export formats (#130)

**More → Export as** (the open conversation) and **Export as** in a History row's context menu offer
Markdown, plain text, Subtitles (SRT), Subtitles (WebVTT) and JSON, each as a file in the share sheet
(`ConversationExportFile`, a `Transferable` with one `FileRepresentation` per format). The file is
written to `tmp/ConversationExports/<uuid>/` with `PrivateStorage` data protection only when a share
destination asks for it. The folder is removed at the next export, at launch, and by an owner in
`conversationDataOwners` on every Delete and Delete all, so no export copy outlives the conversation
in the app. Names (at most 200 UTF-8 bytes, cut on whole characters) come from the title
and date (`Standup 2026-10-23 1435.srt`, made filesystem-safe; a default title becomes
`Conversation`). Every iPhone and Apple Watch line carries the recognizer's audio range, cumulative
across resumed recordings, so Markdown and plain text show `[mm:ss]` and the subtitle formats are
offered; a conversation without timed lines (imported notes only) offers neither. The swipe **Share**
and **Share Markdown** keep sharing text. Cue rules, timestamp sources per engine and the versioned
JSON schema are in [export-formats.md](export-formats.md); the formatting lives in Core
(`SessionExporter`, `TranscriptTimestamp`) with golden-file tests.

## Save audio recordings (#55)

**Settings → Audio recordings → Save audio recordings** is off by default (`SavedAudioPolicy.enabledKey`,
`saveRawAudio`). While it is off nothing is written; the speaker and language copies stay in memory as
before. When it is on, `MobileSession.attachRunAudio` gives each recording run a writer next to the
speaker (#180) and language (#197, #199) buffers. `AnalyzerSink.copy` hands it exactly the chunks the
analyzer accepted, after conversion, so a dropped or unconvertible chunk is missing from the file as it
is from the transcript and the three copies keep one timeline; audio parked during a language switch is
written once, and a replay is never written again. The writer (`SharedPlatform/SavedAudioWriter.swift`)
resamples to **16 kHz mono** and encodes AAC at 24 kbit/s into a **fragmented** `.m4a` with
`AVAssetWriter` (`movieFragmentInterval` 4 s) on its own serial queue, so memory is bounded (at most 512
waiting chunks), the capture path never touches the disk, and a file the app is killed in the middle of
still plays up to its last fragment. 16 kHz is the rate the transcriber, speaker and language buffers use, it does not change when a
headset changes the microphone's native rate mid-recording, and it costs about 12 MB per hour.

Files live in `Application Support/SavedAudio/<conversation id>/`: `audio.json` lists the runs and each
Start writes `part-NNN-microphone.m4a`, placed by `timelineOffset` (the time the run's lines start
from), so a conversation recorded in several Starts has several files whose times match the lines.
`SavedAudioLibrary` (in `ListenToMeCore`, tested) owns the paths, the manifest, deletion and retention.
The folder is created with data protection and is always excluded from iCloud and Finder backups,
whatever **Exclude conversations from iCloud backup** says: raw audio is the most sensitive thing the
app can hold, and its backup would grow by 12 MB an hour. Below 100 MB of free storage a recording
does not start saving audio; a write error, a full disk or a writer that falls behind stops the file
and shows an orange line under the title ("Saving audio stopped … Transcription continues"), and the
recording goes on. In the 1.20.1 (41) beta, backgrounding keeps an opted-in writer open with capture;
with saving off no hidden audio writer starts. Stop waits for the file to close before it returns.
Only finished runs are listed, played or shared, so a run still being
written can never be shared half-written.

Saved audio is one of `MobileSession.conversationDataOwners` (#220), so Delete and Delete all
conversations stop any writer for those conversations and delete their folders (Delete all deletes
the whole `SavedAudio` folder); on the Mac it is an owner of Clear history (`SessionStore`).
**Delete all saved audio** in Settings deletes every file and keeps transcripts; **Keep audio** can
delete runs automatically after 7, 30 or 90 days, checked at launch, when the app becomes active and
when Settings opens. **Delete all saved audio** is unavailable while a recording saves audio; deleting
that conversation's audio another way stops its saving and says so. Turning the setting off mid-recording
stops the file at once — what was written until then is kept, like audio saved before — and the status
line stops saying "Saving audio". A recording that ends without becoming a saved conversation (no line
and no notes) keeps no audio. At launch (`tidySavedAudio`) a run the app was killed in gets its length
from the file, or is deleted if unreadable, and audio whose conversation is not in History is deleted,
but only when History read completely, so a set-aside file's audio is never taken for an orphan.
Retention ages a folder whose `audio.json` is missing or damaged by its files' modification dates.
`SavedAudioLibrary` caches each conversation's runs in memory, so History does not read the disk per row.

Playback (`SharedPlatform/SavedAudioPlayer.swift`, `AVAudioPlayer`, local files only): when the open
conversation has audio and nothing is recording, the live transcript's header shows a play button that
opens the expanded transcript with the player (part picker, play/pause, position, **Share audio** for the
share sheet). Each line shows its time; tapping the line or its time plays the part that recorded it
from that moment (`SavedAudioSeek`). History marks conversations with saved audio and offers **Share
audio** in the touch-and-hold menu. Starting a recording stops playback.

At accessibility text sizes, the player stacks its title and Share audio control and gives the
elapsed/duration text its own line. This keeps complete words and useful transcript space in both
the phone reader and the iPad sheet. Standard-size controls, playback and retention behavior are
unchanged. [Native layout regression evidence](saved-audio-accessibility.md).

Apple Watch (#225, TestFlight 1.19.0 (38)) uses the same opt-in library: before a batch is transcribed,
`retainWatchAudio` copies each part with a stable recording/chunk filename and an atomic manifest.
A failed copy or manifest write leaves inbox audio for retry. The inbox records committed copies and
effective timeline offsets/durations, so retries neither duplicate files nor undo a later Delete all
saved audio, and overlapping parts retain their playback/transcription alignment after relaunch.
The setting is read per import batch; off keeps the temporary delete-after-transcription path.
Retention uses the recording date; old imports are immediately subject to the chosen expiry.
WatchConnectivity already queues disconnected transfers and deletes Watch files only after success.
No cloud audio transport is added. Watch beta eligibility and pending physical/production acceptance are separate; see [the Watch beta](watch-beta.md).
UI tests use `--saved-audio-fixture`, a
synthetic tone written by the real writer; no test records the microphone.

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
kept across updates — the default applies only when no choice has been saved. Until you choose a
provider, availability is checked again on each launch; enabling or disabling Apple Intelligence
can therefore change that unchosen default. Selecting a provider pins your choice. Automatic Quick Summary requires Ollama, a cloud AI
service or an OpenAI-compatible server, so it stays unavailable with an explanation until you select one yourself.

On Apple Intelligence every AI output goes through `AppleIntelligenceProvider`, the same transport
macOS uses. **Manual Quick Summary asks the on-device model for the bullets in prose** rather than for
the automatic evaluator's JSON envelope: a small on-device model cannot be held to that schema, so the
JSON contract stays with the Ollama-backed Auto loop. The prose answer is read back leniently: list
markers, numbering, a "Here is the recap:" preamble and stray code fences are tolerated, and an answer
carrying no takeaway shows "No key takeaway yet." in the pane (a *failed* request is what keeps the
previous summary). The same prompt may end with a final "Suggested:" block of up to three `> ` requests,
which become [suggested prompts](#suggested-prompts-61) and are removed from the bullets; any other
shape means no chips and an unchanged recap, never a failure. Generation failures are stated in plain language instead of a developer message:
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
then **Refresh models from API**, choose the **Summary model** and **Quick Summary model**, and tap
**Test connection**. Each role has an independent model selection, and speech correction has its own. When a new key is entered, the test
button becomes **Save key and test connection** and saves that key before sending the request. Keys are stored in
iOS Keychain with `WhenUnlockedThisDeviceOnly`, never in preferences, session exports or the app binary.
Enter the key separately on each device. Remove API key deletes it from this device.

### Your own Ollama server

**Server URL** is blank by default, which means `https://ollama.com`. Enter an `http://` or `https://`
address — for example `http://your-mac.local:11434` for an Ollama server running on your own Mac on the
same Wi-Fi network — and tap **Save server URL**. Only the scheme, host and port are kept; Settings reports when a pasted path, query, fragment or
credentials were omitted, without echoing those values. Anything that
is not a valid http(s) URL with a host is rejected and the previous server stays in place. Entering
`https://ollama.com` yourself is recognised as Ollama Cloud, not as your own server. **Use Ollama Cloud
instead** clears the setting.

**Use HTTPS, or a local-network HTTP address.** Plain `http` is accepted only for `.local`,
`localhost`, loopback and link-local addresses, using the same rule as OpenAI-compatible settings.
Other addresses, including private IPv4, CGNAT/VPN ranges, public IPv4 and IPv6 literals, require
`https://`. A rejected URL leaves the previous server unchanged and explains the accepted forms.
Loopback addresses refer to the iPhone itself, not your Mac. Reaching a LAN address uses iOS
local-network access, so iOS asks for that permission the first time.

**Your Ollama Cloud API key is never sent to a server you enter.** The saved credential belongs to
ollama.com; requests to any other host go out without an `Authorization` header, so a private endpoint
cannot collect it. The key stays in the Keychain and is used again as soon as the server is Ollama
Cloud. No API key is needed for your own server; one is still required for Ollama Cloud.

Nothing is discovered automatically and the app never changes the server for you: the destination
is shown as **Server: …** in Settings and repeated in the refresh, connection-test and error status text
so you can always see where a summary would go. Requests use the server you entered instead of ollama.com.

Refresh calls `/api/tags` on the selected server (`https://ollama.com` unless you entered one) with Bearer
authentication when a key is saved, and preserves exact returned
model IDs. The recent-family section picks the newest API modification time for each advertised
standard/Pro/Flash variant of DeepSeek, GLM, Qwen and Kimi. All API models remain available, including
other families. This is API update recency, not an independently verified release chronology.
No unavailable Flash/Pro name is invented. Refresh preserves your selected model; if it disappears,
choose another. Model refresh does not prove key validity: Test connection verifies a complete streamed
`/api/chat` response using only a synthetic prompt. Cloud models run remotely; `/api/pull` is not needed.

Selecting Ollama is opt-in; a fresh install summarizes on-device. Generating either AI output
sends the current notes and transcript to the selected Ollama server (Ollama Cloud, or the server you
entered); microphone audio continues to be transcribed on-device. Quick Summary has an opt-in **Auto** toggle (off initially; your choice is remembered across launches). While listening, new completed transcript text triggers an evaluation in five-second batches. A valid evaluation either keeps or updates the visible Quick Summary and may recommend a Summary review (a Deep recommendation from the shared evaluator is ignored on iOS, #235). No unchanged-input requests are sent; failed reads retry with backoff. Enabling Auto with Ollama selected sends those snapshots to Ollama. Existing output remains visible while the next response streams; failures keep the last completed result.
The last complete summary is preserved on HTTP errors, incomplete streams and cancellation. Streamed
text is shown separately until completion. Backgrounding cancels an active summary request.

## OpenAI-compatible server (LM Studio, OpenRouter, vLLM)

Open **More → Settings → Summary provider → Custom server (OpenAI-compatible)**. Enter the server's base URL and
tap **Save server URL**: `http://your-mac.local:1234/v1` for LM Studio on your Mac, `http://your-server.local:8000/v1`
for vLLM or llama.cpp, `http://your-mac.local:11434/v1` for Ollama's own OpenAI API, or
`https://openrouter.ai/api/v1`. A bare origin gets `/v1`; a pasted `…/chat/completions` or `…/models` is
trimmed to the base. A user name, password, query or fragment in the URL is refused rather than stored.
Nothing is set by default, nothing is discovered, and the app never changes the server on its own.

**Plain `http://` only for this device or a `.local` name.** `localhost`, loopback and link-local
addresses and `.local` names are accepted over `http`, because App Transport Security's
`NSAllowsLocalNetworking` exempts exactly those; every other host, including numeric private addresses
such as `192.168.1.20`, Tailscale `100.x` addresses and public names, must use `https://` and is refused at
save time with that explanation. This is stricter than the Ollama server field (tracked in #149).

**Honest labels.** The address — never the model — decides the wording. Loopback, `.local`, RFC 1918,
link-local and IPv6 unique-local addresses (IPv6 judged on the parsed address bytes, IPv4-mapped
addresses as IPv4) read **your server**; the picker says
"OpenAI-compatible · your server" and the explanation adds that ListenToMe cannot verify where that
server runs the model, since a local server can relay requests to a cloud service (Ollama's own `/v1` API
serves `:cloud` models from `localhost`, for example). Every other address reads **may leave this
device** and names the host. Nothing on this route is ever called on-device.

**Key bound to its server.** The optional API key is stored in the Keychain
(`WhenUnlockedThisDeviceOnly`, account `openai-compatible`, separate from the Ollama key) together with the
`scheme://host:port` it was saved for. It is sent as a Bearer token only to that origin. Saving a server on
another origin removes it, and a mismatched origin sends no `Authorization` header at all. The Ollama Cloud
key is never sent to this server, and this key never to Ollama. Keys never appear in status or error text:
an error body that echoes the key is masked.

**Transport contract** (`OpenAICompatibleProvider`, shared with macOS): requests stream
`/chat/completions` as server-sent events. `data:` chunks carry content (a JSON payload split over several `data:` lines is joined, and LF, CRLF
or bare CR line endings are accepted), and reasoning (`reasoning_content`
or `reasoning`) is kept apart from the answer as on Ollama. A response is accepted only when it ends with
`data: [DONE]` or a `finish_reason`; a stream cut off before that is "ended before completion" and keeps
the previous output. A `finish_reason` of `length` (the output-token cap) completes the answer but ends
the event stream with `LLMStreamEvent.outputLimitReached`: the panel keeps the partial text and says "The
answer was cut off at the model's output limit." (#215; Ollama's `done_reason: "length"` is reported the
same way). The plain-text `stream(_:)` ends with `LLMOutputLimitError` instead, so the Quick evaluator,
speech correction and the connection test never take a cut-off answer for a whole one.
An `error` object inside the stream or a `finish_reason` of `error` fails the request
with the server's message, as does a reasoning-only or empty answer. A non-2xx status shows the server's
explanation, bounded to 8 KiB, with hints for 401/403, 404 and 429. Redirects are never followed: a 3xx
fails with the target host named, so neither the transcript nor the key reaches a host you did not enter.
A captive portal or other non-event-stream page is reported as such. Responses are capped at 16 MiB of
stream and 1 MiB per line; cookies are neither stored nor sent; the transport is the same ephemeral
per-role `URLSession` the Ollama path uses, rebuilt when the server or key changes.

**Models.** **Refresh models from server** reads `/models`, keeps unique IDs in alphabetical order and
fills empty roles only when the server lists exactly one model. Each role (Summary, Quick) keeps its
own choice, separate from the Ollama choices; Flash/Pro rules do not apply. The list says nothing about
where a model runs.

**Auto and Quick need the JSON contract.** Manual Quick and Auto send the evaluator prompt with
temperature 0 and 3,072 tokens, plus best-effort reasoning-off hints in place of Ollama's `think: false`
(`reasoning_effort: "none"`, `chat_template_kwargs.enable_thinking: false`; a server that rejects them with
400/422 is asked once more without them), and accept only the strict `QuickSummaryDecision` envelope. Many
small local models cannot hold it. Open the Quick model and tap **Test this model**: it sends a short
synthetic exchange in the evaluator's shape. A pass says Auto and Quick can use the model; malformed JSON,
or an empty or reasoning-only answer, says so and pauses Auto with "… did not follow the Quick Summary
format" until you choose another Quick model or the test passes. Results are kept per server and model
(the 32 most recent failures), recorded for the model that was tested, and model rows are disabled while
a test runs. Summary is plain chat and keeps working. An untested model is allowed; if it breaks
the contract the Quick pane shows "did not return a usable Quick Summary update" and keeps the previous
summary.

Speech correction is unchanged: it always uses the Ollama connection, shown separately in Settings.

## Cloud AI services (OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Groq, Mistral, xAI)

Open **More → Settings → Summary provider** and choose a service under **Cloud AI** (#214). The menu
lists Apple Intelligence, Ollama, the eight services, then **Custom server (OpenAI-compatible)** (the
route above). Nothing is chosen by default: Apple Intelligence stays the default where it can run, and
the app ships with no keys. Choosing a service selects only that service; no key, model or request
follows until you add them.

**Disclosure.** The service's rows start with "Sends your transcript to <vendor>", name the host that
receives the notes and transcript, and link the vendor's privacy policy. A key typed for one service is
cleared when another is chosen, and Save refuses to store it under a different service. The provider
menu is disabled while a test or refresh runs, and a test reports and records the service and model it
started with. **Get a key from <vendor>** opens
the vendor's key page. Claude adds that Anthropic may re-run a declined request on another Claude model.

**Addresses and request shape** (`CloudAIPreset`, shared with macOS; checked against each vendor's
documentation on 2026-10-23):

| Service | API base | Quirks handled |
| --- | --- | --- |
| OpenAI | `https://api.openai.com/v1` | `max_completion_tokens` instead of `max_tokens`; no `temperature` (GPT-5 reasoning models accept only the default); Quick sends `reasoning_effort: "none"` |
| Anthropic Claude | `https://api.anthropic.com/v1` | Native Messages API (`AnthropicProvider`), below |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | Gemini's OpenAI-compatible path; model IDs listed as `models/…` are shown without the prefix; key errors arrive as HTTP 400 in an array-wrapped body, which is read; Quick sends `reasoning_effort: "none"` |
| DeepSeek | `https://api.deepseek.com` | Reasoning streamed as `reasoning_content` stays apart from the answer; Quick sends `thinking: {"type": "disabled"}` |
| OpenRouter | `https://openrouter.ai/api/v1` | Optional `HTTP-Referer` (the GitHub URL) and `X-Title: ListenToMe` attribution headers; keep-alive comments ignored; Quick sends `reasoning: {"effort": "none"}` |
| Groq | `https://api.groq.com/openai/v1` | Quick sends `reasoning_effort: "none"` |
| Mistral | `https://api.mistral.ai/v1` | No reasoning hint |
| xAI Grok | `https://api.x.ai/v1` | No reasoning hint (Grok 4.x reasoning cannot be disabled) |

A vendor or model that rejects the Quick reasoning hint with 400/422 is asked once more without it, as on
the custom server. Everything else is the custom server's transport contract: streamed answers must end
explicitly, redirects are refused, responses are capped at 16 MiB, and keys are masked in every error.

**One key per vendor.** Each service has its own Keychain item (`WhenUnlockedThisDeviceOnly`, account
`cloud-ai-<vendor>`, apart from the Ollama and custom-server keys) saved with that vendor's
`scheme://host:port`; a mismatch sends no credential. The address is fixed in code, so a key is only ever
sent to its own vendor. Switching services keeps every vendor's key and model choices
(`MobileCloudAISettings`).

**Models are always your pick.** **Refresh models from <vendor>** reads the vendor's model list with your
key (no transcript). Nothing is assigned, not even when the list holds one model. The role list shows a
**Suggested** section for the vendor's suggestions it actually lists — for Claude, Claude Opus 5.5 (marked
"Suggested default"), Sonnet 5.5 and Haiku 5.5 — then every listed model. **Test this model** on the Quick
role checks the Quick Summary contract and a failure pauses Auto for that vendor and model, as on the
custom server.

**Claude (native Messages API).** `POST https://api.anthropic.com/v1/messages` over `URLSession` with
`x-api-key`, `anthropic-version: 2026-10-21` and `content-type: application/json`; the body carries
`model`, `max_tokens`, `system`, `messages` and `stream: true`. No `temperature`, `top_p` or `top_k`
(version 2026-10-21 rejects them), no `thinking` (it cannot be turned off on Opus 5.5 or Sonnet 5.5) and
no assistant prefill. Depth is set with `output_config.effort`: `low` for the Quick evaluator, `medium` for
Summary (and Deep on macOS; set explicitly; Opus 5.5 defaults to `medium`, other models to `high`). The Quick
evaluator asks for structured output (`output_config.format` with the `QuickSummaryDecision` JSON schema),
so it always receives valid JSON; `QuickSummaryDecision.parse` still enforces the length and count limits
a schema cannot express. Opus 5.5 and Sonnet 5.5 Summary (and macOS Deep) requests send `fallbacks: "default"` with
`anthropic-beta: server-side-fallback-2026-07-01`; the structured-output Quick evaluator never does, so
the two options are never combined. Any 400 to a request with fallbacks is retried once without them, and
the model is remembered as not taking them (until the app restarts) only when that retry succeeds. A
fallback mid-answer continues the partial text on another Claude model; Anthropic documents that nothing
already streamed is invalidated, so the answer simply carries on. A refusal that ends the response
discards the partial text: iOS keeps the previous summary and the macOS pane restores its previous
answer (`LLMPartialOutput`). Only `text_delta` is answer text; `thinking_delta`,
`signature_delta`, `ping` and unknown events are ignored, and a response completes only at
`message_stop`. `stop_reason: "refusal"` shows "Claude declined to answer this request"; `max_tokens`
(or `model_context_window_exceeded`) keeps the partial text with the shared "The answer was cut off at
the model's output limit." notice, on iOS as on macOS (#215; until then iOS dropped Claude's partial
text and said it was shown); an `error` event (such as `overloaded_error`) fails the
request. HTTP 401/403 names a bad key, 429/529 retries once only when `retry-after` (seconds or an HTTP date)
asks for a wait of 20 seconds or less, and a 400
`invalid_request_error` shows Anthropic's message with the key masked. Model lists come from
`GET /v1/models`.

### Watch file speaker identification (#192; TestFlight beta)

When Identify speakers is on and the models are already loaded, Watch imports analyze all available
file audio in 60-second windows with 10-second overlap before transcribing that batch. Decoding runs
off the UI actor with bounded PCM memory. Gaps flush the overlap so missing time is never collapsed;
timestamps use the same ChunkFeed mapping as transcription. The file passes share the serialized
model queue but never begin/end a live microphone run. Cancellation releases the import immediately,
even if model processing ignores it; the late result is discarded while later model passes stay serialized. Imports never prepare or download speaker models.
If identification is off, unavailable, fails, or cannot confidently cover a line, it keeps Apple Watch.

Speaker IDs and names are saved with text before raw chunks are deleted, including for a conversation
that is not open. Watch provenance survives rename; live microphone and language-replay passes cannot
relabel these lines. Named speakers reach search/export and prompts; unidentified Watch speech still
maps to You. No additional AI summary is requested for a label change. Voiceprints remain in memory for
one recording import only, including later arriving batches while the app stays open. After cancellation
or relaunch, new voices start numbering after existing labels rather than guessing an identity. No audio-retention or backup behavior changes. Distribution still waits
on #181; simulator tests with a fake diarizer do not establish real-device speaker accuracy.

## Build and run

Use Xcode 26+, XcodeGen and an installed iOS 26 simulator runtime:

```sh
make ios-build
make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

UI tests run serially (`-parallel-testing-enabled NO`) to avoid competing fixture schedulers
and permission dialogs. For release acceptance, supply the UUID of a dedicated erased simulator
in `IOS_DESTINATION`; do not erase a simulator used by another session. Launch waits for either
release notes or an interactive workspace. Calendar accepts the actual permission prompt or an
already-authorized date picker; correction and summary assertions wait on their final UI state.
The bounded waits fail with diagnostics rather than adding fixed sleeps. (#176)


For provider-default test isolation (#241), run `MobileAITests` on a freshly erased dedicated
simulator before any UI tests (`-only-testing:ListenToMeIOSUnitTests/MobileAITests`). The test sets
and restores both the provider and cloud vendor, and checks the no-vendor fallback explicitly;
it must not depend on a service selected by an earlier Settings UI test.

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
4. On physical iPhone and iPad, establish Listening, lock beyond the usual suspension interval,
   provide known speech, unlock and verify continuous words/times, the same elapsed start and
   opted-in audio. Optional AI must pause while inactive. Stop remains terminal after scene and
   interruption events; a cancelled pending Start cannot open capture. Calls/route failures can
   interrupt capture: resume only while active and when permitted, with accurate recovery guidance.
   Connect and disconnect AirPods and verify live text on the remaining microphone. Repeat with each
   supported native speech module; see [the acceptance checklist](recording-continuity.md#remaining-physical-acceptance).
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
   OpenAI-compatible (#52): point the provider at LM Studio on your Mac as `http://your-mac.local:1234/v1`,
   accept the local-network prompt, refresh models, run **Test this model** on Quick and summarize; confirm
   the picker says "your server", that `http://192.168.…` is refused, and (optionally) that an `https://`
   hosted endpoint reads "may leave this device" and that changing servers removes its key.
7. Camera permission denial/retry, photo capture, photo library, Files and Apple Notes Send Copy imports. Preview, share originals, extract document text, remove attachments, delete/reopen conversations and Delete all conversations (#220).
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
    battery drain against an identical recording with the setting off. Voice matching (#171): in a
    30+ minute recording of three or more people, rename one early, then have them stay quiet for
    five minutes or more before speaking again; their new lines must carry the name, and Notes →
    Speakers must list no more speakers than took part. Note any split of two similar voices.
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
12. Re-checking the language mid-recording (#199): with Automatic on, speak English for two minutes,
    then Mandarin for two minutes in one recording. Within about two minutes of the change confirm
    "Detected Chinese from m:ss · switched", that the time is close to where you changed language,
    that the English lines before it are untouched and the Mandarin part is in Chinese, and that
    the replayed lines keep their times (the first replayed buffer carries a `bufferStartTime`).
    Say one short English phrase inside the Mandarin part and confirm nothing switches back. Tap
    **Undo** and confirm only the Mandarin span returns to English. Turn on Low Power Mode during a
    recording and confirm Status details shows "skipped (Low Power Mode)". Record 20+ minutes of
    one language and confirm memory stays flat and battery drain is close to a recording with a
    fixed language.

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

## Adaptive two-pane iPhone workspace (#253, unreleased)

The Live page places Transcript and Quick Summary side by side when its available workspace is at
least 640 points wide and 180 points tall. Each pane scrolls independently; compact headers keep
model selection, Generate, speech correction settings and Expand transcript reachable, and Auto stays in the Quick pane's
scrolling content, below an existing answer. A compact title/status row and recording dock leave more
reading room in landscape. Layout uses the current workspace geometry, so rotation and window resizing
recompute it. The selected Live/Summary page, conversation, expanded transcript and selection-sheet
state belong to their existing parent views and survive layout changes.

Portrait retains the vertical Live panels. Accessibility text and very short/narrow workspaces use
one outer scroll. The wide iPad workspace still shows Live and Summary together. This feature is an
adaptive two-pane layout, not a certification for any particular new device model.

## Pending iOS updates
- Settings → Privacy names every optional off-device provider (Ollama, Cloud AI services and OpenAI-compatible servers), and explains that requests send text and included context only through the provider you choose (#247). This copy is not yet published.

## Release screenshot coverage

UI testing and release trains capture fresh iPhone/iPad screenshots with source and device provenance.
Before App Store submission, verify every applicable localized screenshot set in App Store Connect;
see the [release screenshot checklist](IOS-RELEASING.md#screenshot-capture-and-app-store-handoff-255).

## Conversation prompts (#257)

Below Context notes on Mac and in Notes on iPhone/iPad, **Prompt** offers **Ask once** and
**Summary instructions**. Ask Quick sends the edited question through the selected Quick provider;
Mac also offers Ask Deep. The answer uses the current transcript and notes. On iOS it appears in an
Ask card in Notes and below Quick Summary, with Cancel/Close, and is not saved with the conversation.
Saved summary instructions apply to future manual and automatic summaries and travel with the saved
conversation and text/JSON exports. Clear the editor and Save instructions to remove them. Starting a
new conversation clears them. Existing summaries are not regenerated just by editing instructions.

Domain presets fill an editable draft; they never send a request or overwrite context notes. A domain
suggestion appears when the existing on-device vocabulary classifier offers a domain for this
conversation. All seven presets remain available in the menu. Existing conversation-based suggested
questions can also fill the Ask draft. Requests and saved instructions are limited to 1,000 characters.
Mac History can reopen modern saved conversations after capture/import stops; the current conversation
must first be saved. Older records without structured transcript lines remain readable/exportable.
Settings Transcription and Speakers descriptions explicitly explain opt-in saved audio; audio is never sent for transcription or speaker identification (#251).

## Re-transcribe saved audio (#224)

Unreleased #348 corrects a shared saved-audio conversion tail loss affecting the feed used by re-transcription and Watch imports. The candidate drains converter output before advancing files and preserves saved originals and recording-time anchors. Focused generated-PCM tests passed; this is not a claim of changed transcription accuracy or physical acceptance. See [scope and evidence](audio-file-feed-tail.md).

After stopping, open a conversation with saved audio and choose **More → Re-transcribe saved audio**.
Choose its language and tap **Re-transcribe**. Apple speech recognition processes each saved track
on-device; a language model may need a first-use download. Preview the result, then choose
**Replace transcript** or **Keep original**. Cancel, an unreadable file, or a failed recognition pass
leaves the original transcript untouched. A transcript changed during recognition cannot be replaced
by the stale preview.

Replacement removes every original transcript line, including lines without saved audio. It resets
speaker identities and corrections, updates transcript/audio timing, and preserves the title, notes,
attachments, instructions and summaries. Review those summaries against the new text. Saved audio
files are not rewritten. Retained Watch audio keeps its Apple Watch playback label and device provenance
on replacement lines, while previously inferred speaker identities are cleared. Mac offers the same
flow with Apple or WhisperKit recognition.

## Custom Ollama context windows (#230)

For a custom Ollama endpoint, the app reads model metadata before a request. Locally hosted models
receive a context sized to the complete assembled prompt, with answer space reserved and a 64K
ceiling. If its conservative UTF-8 budget cannot fit the reported model capacity, the pane shows
an error asking for a shorter selection or a larger-context model. No answer request is sent in
that case. Cloud models retain server-managed windows. This applies to summaries and correction.

### Duo pane widths

In the wide iPhone Live workspace, tap **Duo pane widths** beside the Live/Summary control to choose
Equal widths, More transcript, or More Quick Summary. The device remembers the choice; each pane
keeps at least 280 points when space permits. Portrait and accessibility layouts still stack their
content. **Transcript actions** holds Select lines, Speech correction settings, and Play recording
when available. Expand transcript stays directly accessible. The width preference is device-local,
shared by conversations, and does not change saved text or audio. It is applied only to two-pane
Live layouts; Summary, narrow windows, and accessibility text keep their existing reading layouts.


### OpenAI-compatible server context capacity (#210)

Mac Settings and iPhone Settings → Custom server offer **Server context window**: Unknown
(the existing default) or 4K, 8K, 16K, 32K, 64K, 128K and 256K tokens. Match the capacity
actually configured on the server; a model's advertised maximum does not change a local runner's
configuration. The selection is stored per normalized full API URL, including its path, and does
not transfer to a different server. Switching back restores that server's choice.

The provider reserves answer tokens (up to one quarter of the window), template overhead and
message framing. Mac uses the existing prompt budget and truncation notice. Both platforms also
check the complete system/messages using conservative UTF-8 byte budgeting before any request;
oversized text fails locally, including Unicode-heavy input. This is a conservative estimate, not
a tokenizer guarantee. Unknown retains the previous request behavior. No credentials or audio
are changed, and this setting applies only to Custom server, not cloud vendor presets.

### Live summary snapshots and unfinished speech (#164)

Repeated live events reuse their summary input until finalized speech, speaker labels, the current
hypothesis or notes change. Manual Summary, Quick Summary and Ask require at least 24 trimmed
characters before using unfinished speech. They mark it as provisional and instruct the model not
to record it as a decision, owner, deadline or action item. The marker and instruction count toward
the prompt budget; a shortened hypothesis keeps its marker. Saved transcripts and exports retain
the recognizer's original text.

### Capture task ownership (#134)

`MobileSession+Capture` adapts the platform recorder to Core `CaptureCoordinator`. The coordinator
owns preparation, start, cancellation and joined Stop tasks, with a token for each run. It accepts
final utterances while Stop drains and rejects callbacks after that run finishes. The adapter retains
foreground/interruption policy, speaker/language buffers, saved-audio cleanup and final checkpoints.
The original #134 extraction changed no recording permission, background capability, model or audio
destination. The later [#339 candidate](recording-continuity.md) changes background capture policy
separately. Core tests cover
transition races, and native simulator adapters passed in full validation before PR #308 merged.
The remaining Mac view and shared lifecycle extraction in #134 is also complete; installed Mac
GUI/OTHERS acceptance remains explicitly deferred. See [orchestration](ORCHESTRATION.md).

Automatic naming task ownership now lives in Core `ConversationTitleCoordinator`, shared with Mac.
It tracks each conversation independently and ignores cancelled generations. The iOS adapter still
selects eligible on-device/local providers and checks the captured title/state before persisting a
result. Watch-import naming and Save to folder use the same path; no new data destination is added.

### Save transaction ownership

ConversationPersistenceCoordinator in Core owns unchanged-byte suppression, deciding whether empty
content updates an existing History entry, archive/export/active-snapshot ordering and retry eligibility
after partial failure. MobileSession supplies stable encoding, private file writes, backup attributes,
paths and existing UI messages. Native tests use real archive and active-snapshot failures before
and after extraction. See [orchestration and validation boundaries](ORCHESTRATION.md).

### Watch import regression — 1.19.1 (39)

Fix #326's iPhone opening crash: raw Float32 language/speaker analysis no longer constructs
Speech `AnalyzerInput`, whose physical integer-only precondition was reproduced with stock AAC.
File transcription still negotiates the Speech format and keeps recording-relative timestamps.
The Watch recording presentation no longer interprets incidental dismissal as Stop. Pending
preparation and actual audio interruption behavior remain explicit. `WATCH-015`/`WATCH-016` retain
native red/green evidence; physical paired transfer/wrist-down acceptance remains separate.
See [Watch beta status](watch-beta.md). [Published to TestFlight](releases/ios-1.19.1-build39.json); complete physical/production acceptance remains unverified.

## Live and Summary translation (#330; TestFlight recovery #343)

Unreleased #346 strengthens essential translation guidance/status foregrounds while preserving font sizes, layout, originals and translation behavior. Focused native contrast evidence and acceptance limits are [recorded separately](translation-legibility.md); this change is not part of published build 42.

**More → Live translation** and **Notes → Live translation** control opt-in finalized-line translation
on phone/iPad/Duo. **Summary → Translate summary** translates an existing completed summary into an
independent target; it does not change summary generation language/provider. Originals stay available.
Installed Apple Translation packs are required; setup is explicit and unsupported pairs are explained.
TestFlight 1.20.2 (42) disables Translate while busy, provides Cancel and stops indefinite progress after a per-text-chunk deadline. Native cancellation retains one worker slot until it exits; originals remain visible and retry waits for safe recovery. No translation engine is added to Watch. See [usage, privacy and acceptance](translation.md) and [recovery evidence](translation-recovery.md).
