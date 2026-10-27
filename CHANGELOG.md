# Changelog

All notable user-facing changes to ListenToMe (macOS) and ListenToMeIOS, in one place. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/); versions are listed newest first, macOS and
iOS interleaved by release date.

macOS entries are drawn from the [GitHub releases](https://github.com/tomqwu/ListenToMe/releases).
iOS entries are drawn from [`iOS/MobileReleaseNotes.swift`](iOS/MobileReleaseNotes.swift), the
in-app "What's New" copy shown once per set of bundled release notes — a build that changes no notes
does not show it again, and a fresh install does not see it at all; see
[`docs/IOS.md`](docs/IOS.md) for the fuller per-build technical notes and
[`metadata/ios/en-US/`](metadata/ios/en-US/) for current TestFlight "What to Test" text.

## Repository tooling (unreleased)

- Support an explicit, validated manual TestFlight signing file when cloud-managed signing is unavailable. Preserve the automatic default, exact companion eligibility, stable versions/team, upload locks and acceptance receipts; upload from a private validated snapshot and record its hash, original path and signing mode. No app binary or privacy behavior changes. (#323)

- Require Given/When/Then behavior contracts and changed native regression-test bindings for behavior
  changes across apps, shared services and delivery tooling. Add a baseline scenario catalog,
  executable native-test adapter, local/CI gates and PR evidence template. This changes development
  workflow only; it does not require a binary release or claim exhaustive legacy acceptance.

- Recognize complete native XCTest pass records joined to timestamped framework diagnostics while
  rejecting mentions, mismatched selectors and unsuccessful/incomplete records. This repairs a
  local BDD-verification failure; it does not change an app feature or count a failed aggregate run
  as passing.

## iOS (unreleased since 1.19.1 (39))

- Add opt-in on-device translation beneath finalized transcript lines, plus **Translate summary**
  on the Summary page with its own target language and original summary retained. Check exact
  installed language pairs, offer explicit preparation and preserve original speech, speakers,
  audio timing and AI-provider choices. Derived text is not archived as the original. (#330)

## iOS 1.19.1 (39) — 2026-10-27 (TestFlight)

- Fix an iPhone crash while opening received Watch audio with automatic language detection. Language and speaker analysis decode raw PCM without passing Float32 samples to Apple's integer-only Speech input initializer. Queued/retained audio and on-device privacy remain unchanged. (#326)
- Keep established Watch capture running when its recording presentation is dismissed; Stop remains explicit, while actual audio interruptions still show a reason and wait for Continue. (#326)

Apple accepted **1.19.1 (39)** from `f1728150e3e66664e36d2506022c2918fa60a53c`: Xcode upload success at **2026-10-27 15:39:29.401 UTC**, Apple uploaded date **2026-10-27 15:40:24 UTC**. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing internal Dev group includes build 39 with two existing active/installed tester members. This does not prove physical installation of build 39. Primary locale, localized name, beta description and What to Test were read back in **en-US**, with name **Listen To Me - Real Time AI**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.1-build39).

**Distribution procedure correction:** an existing private plist with `destination=upload` was passed to direct Xcode export, which uploaded this build. Actual upload was **not** performed by the helper; the later helper dry run is not upload evidence. No duplicate upload was sent. Package verification was completed after acceptance, and the receipt preserves that order. Future local export must use a private copy with `destination=export`; use the official make target for actual upload.

## iOS 1.19.0 (38) — 2026-10-27 (TestFlight)

- Include the Apple Watch companion in the default iOS build. Record on Watch, keep recording with wrist down, and sync finished audio to the paired iPhone for on-device transcription when connected. Phone remote Start/Stop requires a reachable, compatible, ready foreground app. (#181)
- Retain Watch playback audio only when **Save audio recordings** is on during iPhone import; otherwise remove temporary audio after its text is saved. Existing Retry, Delete, playback and expiry controls remain. (#225)
- Watch imports can identify speakers with already-loaded on-device models and detect language with an already-downloaded model in Automatic mode. Imports never initiate those model downloads; unsupported/uncertain language detection uses the device language. (#192, #200)
- Preserve pending Watch audio/metadata through failed handoffs and relaunch. Duplicate/conflicting callbacks cannot overwrite unacknowledged audio; recording end markers survive storage failure and continued chunks advance old boundaries. Waiting includes failed recovery audio; after Stop, Delete removes audio and recovery state without resurrection. (#181)
- Cancelled/Stopped microphone preparation and readiness changes cannot activate capture after permission returns. An interruption waits for explicit Continue. (#181)
- Explicit Watch-beta upload mode validates companion identity, platform, icons/executable and matching versions. Physical microphone/paired-transfer, wrist-down, battery/storage and production acceptance remain pending. Simulator tests are separate from those gates. (#181)

Apple accepted **1.19.0 (38)** at **2026-10-27T08:31:46.551678+00:00**, from `e43244f752712ac80e179e35c893e967aea38753`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing Dev group includes this build with two accepted testers. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.0-build38). Watch inclusion is confirmed in the exact uploaded IPA and Apple’s processed nested entitlements. All three required checks and full local gates passed; the tag points to the exact app source. The delivery-only helper is recorded separately as `ea2c05febf858065efd611db32dc57d81d523d10`. Physical Watch installation, microphone capture, paired transfer, wrist-down and battery/storage acceptance remain unverified. This is an authorized beta, not a production-ready claim. Public iOS remains 1.18.1; no new public App Store submission or screenshot listing upload was performed by this train. Mac Store draft #318 stays separate.

## iOS 1.18.2 (37) — 2026-10-27 (TestFlight)

- Restore the missing Summary icon beside Full summary in the iPhone/iPad More menu. Opening and dismissing the summary are unchanged. (#319)

Apple accepted **1.18.2 (37)** at **2026-10-27T03:39:12.147449+00:00**, from `9494d024b9eee577b40695292aaf5e7dab9434eb`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and both existing Dev testers have accepted group access. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.2-build37). No privacy or audio-retention change. Fresh screenshots are captured; the public listing was not updated. Physical-device acceptance was not performed for this beta; it is not a production-ready claim. Public iOS 1.18.1 remains READY_FOR_SALE; 1.18.2 has not been submitted to the public App Store. Watch is excluded and the separate Mac Store draft #318 remains unsubmitted.

## iOS 1.18.1 (36) — 2026-10-26 (TestFlight)

October 26 correction: the en-US TestFlight description and What to Test were created and read back
for build 36, without a binary re-upload. All 24 fresh en-US App Store screenshots are COMPLETE and
the iOS version is waiting for review. The app-wide primary locale remains en-CA until Apple approves
the new US localization/screenshots; submitted localization and primary language are separate.
The original upload checkpoint below retains its historical locale and then-pending screenshot state.

Published from `7643b204def6acea0b616a2c2de2bade2fc4c7c9`; Apple accepted the upload at 2026-10-26T17:29:24.328646+00:00. Processing is VALID, internal state is IN_BETA_TESTING, both existing Dev testers have group access, and en-CA metadata was read back. [Full release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.1-build36). Physical-device accuracy/performance and original tester audio remain unverified; three-person separation is not established. App Store listing screenshot upload remains pending. Watch is excluded and Mac publication remains paused.

- Fix live speaker identification merging brief alternating voices into Speaker 1. A recording-scoped streaming model carries voice identities and edited names through overlapping windows and silence. Stop flushes delayed words; the Settings switch can disable labels while listening, releasing its audio and voice state. Re-enabling waits until Stop. Similar voices can still merge in group conversations. Real-model native regression tests supplement simulator controls. Original tester audio and physical-device accuracy/performance acceptance remain pending. (#310)

## iOS 1.18.0 (35) — 2026-10-26 (TestFlight)

Published to TestFlight from `b1570ad567a43a093294974871d7f0abf1872708`; Apple accepted the upload at 12:51:44 UTC on October 26. Processing is VALID, internal state is IN_BETA_TESTING, and both existing Dev testers have group access. en-CA What to Test and beta description were read back. [Full release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.0-build35). Current-source physical acceptance and App Store listing screenshot upload remain pending. The maintainer explicitly deferred Mac GUI/OTHERS acceptance for the combined merge and iOS beta; Mac publication remains paused.

- Maintenance: active/history save ordering, unchanged-save suppression and retry acknowledgement now use a tested Core owner. Native file protection, backup options, storage format and user-facing save behavior are unchanged. (#134)

- Compatible older iPhones/iPads use Apple's on-device dictation when advanced transcription is unavailable. Fixed and Automatic language choices use supported local modules. (#306)
- Check recording support before enabling Start, with clear device/language and microphone recovery. Genuine preparation failures remain actionable; cancelling preparation or leaving the app suppresses obsolete callbacks. Recording remains independent of summary AI. (#306)
- Explain unavailable Apple Intelligence and require an explicit supported alternate provider; preserve saved choices and keys. Live/Summary help stays compact and supports large text and landscape. (#307)
- Re-transcribe retained audio in a chosen language, review the result and replace or cancel. Recognition stays on-device; notes, attachments, summaries and Watch device attribution remain. Replaced evidence invalidates stale speaker corrections and summary cards. (#224)
- Automatic reviews enforce their full assembled request limit, including directives and references, before sending. Directive edits alone keep the existing review. (#148)
- Shared recording, naming and speaker-work coordinators preserve Stop finalization, cancellation, conversation identity and old-callback isolation. (#134)
- Harden literal Markdown export, incomplete-import provenance, reference-file handling, model discovery and cold local Ollama requests. Existing provider privacy choices remain unchanged. (#141)
- Integration regression coverage preserves dictation fallback during file re-transcription and incomplete-import status through summary/save/title/language copies.

Privacy: speech and re-transcription remain on-device; saved audio is opt-in. Optional AI providers receive only the text/context already explicitly configured. Apple Watch is not embedded in this build; paired-device acceptance remains pending (#181, #193).

## iOS 1.17.0 (34) — 2026-10-25 (TestFlight)

Published to TestFlight from `cbd2e454dbf502df5832dc3654ee2d284f147380`. Apple accepted the upload on October 25; processing is VALID, internal state is IN_BETA_TESTING, and Dev access plus en-CA metadata were read back. Physical-device acceptance and App Store listing screenshot upload remain pending.

- Deleting a conversation immediately cancels and clears its streamed History answer and citations, preventing deleted content from returning when an old request finishes. (#131)

- Ollama settings reject unsupported plain-HTTP addresses before saving and explain when pasted URL parts are omitted. Destination prose names Ollama Cloud clearly; provider-default and catalog-refresh behavior are documented. (#149)

- Backgrounding cancels final speaker labeling already started after Stop and clears the recording buffer without waiting. Queued work stays bound to its original recording, so an old pass cannot analyze or relabel a new recording. Lifecycle and model-backup tests cover these paths. (#188)

- Live summaries reuse their transcript snapshot between unchanged events. Manual Summary, Quick and Ask omit very short recognition hypotheses and mark longer unfinished speech as provisional, with guidance against treating it as a confirmed decision. The marker survives prompt trimming; saved transcripts remain unchanged. (#164)
- History search reuses unchanged passage vectors when a conversation is saved, including after summary insertion. Changed text or transcription language is re-indexed on-device; duplicate passages share one embedding attempt per save, including unsupported text. Existing indexes rebuild once. Semantic language coverage is unchanged. (#223, partial)

- OpenAI-compatible servers can use an optional per-server context limit. Answer space is reserved and oversized requests stop before sending; Mac prompt trimming includes a visible notice. Unknown capacity preserves server-managed behavior. (#210)

- Validation: simulator UI journeys wait for permission and correction state changes under load; the test target runs serially. No app behavior or binary release change. (#176)

- Automatic language detection can start and re-check from microphone audio activity even when the current transcriber recognizes no words. Silence skips inference, isolated sounds do not download the model, and Stop remains responsive. All analysis stays on-device using the existing temporary buffer. (#216)

- iPhone Duo lets you give more space to Transcript or Quick Summary and remembers your choice. A compact transcript actions menu keeps the landscape toolbar readable.

- Local Ollama requests size their context window to the full prompt instead of relying on a small server default. Prompts beyond the safe model capacity show an error before an answer request; cloud context remains server-managed. (#230)

- Vocabulary presets added to a conversation are saved and restored when you reopen it. Auto Quick now uses its domain and glossary, while new conversations keep only your device-wide defaults. (#237)

## iOS 1.16.0 (33) — 2026-10-24

- Prompt below Notes supports one-time Ask, saved summary instructions, and editable domain presets. Instructions stay with each conversation and apply to manual and automatic summaries. (#257)
- Transcription and speaker Settings correctly explain that audio is kept only when Save audio recordings is enabled, and is never sent. (#251)

- Release workflow now requires fresh screenshots across supported device categories, with source provenance and App Store Connect screenshot verification before submission. (#255)

- A two-pane Live workspace on wide iPhone layouts: Transcript and Quick Summary sit side by side with independent scrolling and compact controls. Rotation preserves the selected page and conversation; portrait and accessibility text keep a readable stacked layout. (#253)

- Simplified Chinese vocabularies for all seven presets: the transcription language selects the terms for recognition, correction and prompts; suggestions understand continuous Mandarin text, use a Chinese on-device embedding when available and fall back to term matching. My terms remains in any language; other transcription languages keep the English presets. (#238)

- Settings → Privacy now explains that optional Ollama, Cloud AI and OpenAI-compatible requests send text and included context to the provider you choose; Apple Intelligence stays on-device. (#247)

## macOS (unreleased since 1.4.4)

- Fix audio imports remaining at Finalizing or Stopping when a prepared speech channel received
  no audio. Close unused channels promptly while preserving final words and timestamps. (#335)

- Prevent live SpeechAnalyzer input from stopping on overlapping buffer timestamps caused by
  resampling and small capture-clock jitter. Preserve source offsets, real gaps and converted frames;
  reject stale input explicitly and discard converters cancelled during conversion. (#333)
- Prepare a separate sandboxed Mac App Store configuration, sharing the iOS listing's bundle ID
  while preserving the existing DMG and Dev identities. The preliminary 1.5.0 (15) archive builds
  for Intel and Apple silicon with US English. This is not an App Store upload or submission.
- Add a release-optimized local sandbox acceptance build under the existing Dev identity, with
  explicit signing setup, separate output and normal app-scoped cleanup. Store distribution
  artifacts and their provisioning remain untouched; local checks do not establish Store installation.
- Persist native security-scoped grants for the selected Markdown vault and reference files/folders,
  retain access throughout reads, and show reselection guidance for broken saved reference grants.
  Sandboxed picker/relaunch, recording and fresh Mac screenshot acceptance remain required.
- Add opt-in on-device translation beneath finalized transcript lines, plus **Translate summary**
  on the Summary page with its own target language and original summary retained. Check exact
  installed language pairs, offer explicit preparation and preserve original speech, speakers,
  audio timing and AI-provider choices. Derived text is not archived as the original. (#330)

- Mac pane buttons, prompts, chips, menus and hotkeys register their cancellable response immediately, preventing an immediate Stop from letting an answer begin later. New and import task ownership now live in Core; cancelling before an import starts opens no media. Pending device/Calendar/speaker follow-ups cannot publish after cancellation or supersession. Root-view construction and layout are separated from these tested owners. (#134)

- AI-off no longer queries model catalogs or changes saved model choices. Model refreshes are cancelled when editing Settings or closing the window; replies from an obsolete route cannot update the current route. Explicit cloud/custom choices and verified-local Ollama defaults remain unchanged. (#134, partial)

- Calendar and attachment loads now belong to the current conversation. Late Calendar results cannot overwrite edited notes or a newer conversation, and cancelled attachment reads cannot restore cleared grounding. Cancelling a close keeps pending context available; accepted close invalidates it. Context/title formatting, local file limits and privacy settings are unchanged. (#134, partial)

- Check the selected speech engine/language and permissions before Start, with explanatory settings/permissions recovery and supported engine alternatives. Unavailable Apple Intelligence is not offered as a working AI choice; saved preferences remain intact and capture stays independent of AI. Language changes clear stale engine choices; late checks and retained menu actions cannot restore an unsupported selection.
- Stop, New and window close cancel pending capability/permission checks without waiting for an unanswered OS callback. Late grants cannot start capture and late denials cannot show an error in a newer conversation. Cancelling does not dismiss an OS consent prompt.

- Delete one saved conversation from its History row menu or detail view, with confirmation. Its saved audio, search entry and pending folder-save work are removed while other conversations stay intact; deleting the open conversation prevents it from being saved again. Exported copies remain where you saved them. (#131)
- Custom-server Settings can check the Quick model's Auto compatibility with a synthetic exchange. A format failure pauses Auto for that server/model until a successful recheck; network errors and cancellation preserve prior results. (#209)
- Failed model discovery preserves pinned choices and reports uncertainty. MiniMax is no longer ranked as a “mini” model. Verified local Ollama requests allow cold loads up to five minutes. (#141)
- Audio imports report read failures and keep partial transcripts marked incomplete across reopening. Legacy speech waits for final callbacks with a 30-second deadline; system capture rejects failed PCM copies and minimizes unused video work. (#141)
- Calendar context selects the most recently started overlapping meeting. Reference attachments reject symbolic links, heading whitespace renders correctly, and Markdown exports keep speech literal. Release discovery/signing and real-contract test gates now fail safely. (#141)
- The global ⌘⇧Space shortcut registers only that key combination and no longer asks for Accessibility access. Conflicts show a notice while the in-app shortcut remains available. (#124)

- Capture failures and file/Calendar failures have separate dismissible messages. Retrying export, import or Calendar work clears only that operation’s message; microphone and Calendar privacy actions stay attached to the relevant error. (#173)
- Summary can render Open / To-do / Decided cards when the model returns validated structured output. Expand Sources for verbatim evidence and speaker labels; times appear only when the engine supplied them. Explicit owner/deadline fields require matching source text. Unsupported or invalid output remains readable as freeform text. Structured records retain readable exports and reopen on Mac. (#62)

- Automatic reviews count the complete request toward their 60,000-character limit, including instructions and any attached references. Oversized requests stop before sending and explain what to shorten. Changing directives alone keeps the existing review; new context or manual generation uses the new settings. (#148)
- The rail shows measured microphone and system-audio RMS levels, distinguishing silence, missing audio and unavailable channels. AI panes show first-answer-content and total request timing, including automatic reviews, with separate completion, cancellation and failure states. Metrics stay on-device and are not saved. (#56)

- SpeechAnalyzer lines use recognition audio ranges on the capture timeline, enabling timestamped exports, saved-audio seeking and speaker labels. Delayed callbacks preserve capture time. Transcript follow-latest survives text growth and resizing, pauses for user scrolling, and resumes with Latest. (#68)

- Select and copy transcript text, double-click a finalized line to edit it, or delete it with confirmation. Manual edits preserve the recognized original in exports and refresh existing summaries; stale AI answers are cleared. Saved audio and exported copies are unchanged. (#126)

- Changing speaker labels or names no longer generates a first Listener summary when Auto is off. Existing summaries are rebuilt with the updated labels; interrupted summaries cannot restore old names. Explicit Refresh remains available. (#167)
- Import MP4/MOV meeting recordings directly, reading their first audio track on-device. Choose You or Others for imported speech; video without audio shows a clear error. Audio/video imports share progress and cancellation controls. (#128)

- Stop a streaming pane answer while keeping its partial text. File imports show the filename, source-reading progress and a Cancel button; cancelling keeps recognized lines and marks the import incomplete. (#127)

- Failed model discovery preserves pinned choices and reports uncertainty. MiniMax is no longer ranked as a “mini” model. Verified local Ollama requests allow cold loads up to five minutes. (#141)
- Audio imports report read failures and keep partial transcripts marked incomplete across reopening. Legacy speech waits for final callbacks with a 30-second deadline; system capture rejects failed PCM copies and minimizes unused video work. (#141)
- Calendar context selects the most recently started overlapping meeting. Reference attachments reject symbolic links, heading whitespace renders correctly, and Markdown exports keep speech literal. Release discovery/signing and real-contract test gates now fail safely. (#141)
- Custom-server Settings can check the Quick model's Auto compatibility with a synthetic exchange. A format failure pauses Auto for that server/model until a successful recheck; network errors and cancellation preserve prior results. (#209)
- WhisperKit offers explicit multilingual Tiny, Base and Small models. Base remains the default; saved choices apply on the next capture, with the selected model named during loading and on failure. Loaded model identity is checked before use. (#58)

- Engine → Compute details separates configured compute units from runtime accelerator information. WhisperKit displays the exact policy passed to the model; Apple Speech manages its own policy. Hardware activity is shown as Not exposed rather than inferred from configuration. (#60)
- Maintenance: checkpoint saves now use a tested Core coordinator. Failed writes remain retryable, unchanged timer ticks avoid rebuilding transcripts, and reopened conversations retain their original date. Saving and privacy controls are unchanged. (#134, partial)

- Speaker identification retries stay bound to their recording. A cancelled model retry cannot resume into a newer recording or clear its speaker status. (#134, partial)

- Maintenance: the Markdown renderer now lives in the shared platform target, with unchanged rendering. (#134, partial)

- Automatic conversation naming now shares one task coordinator across Mac and iOS. Repeated requests for the same conversation join the existing task; a cancelled older task cannot clear or apply over a replacement. Typed/calendar names and on-device/local-provider privacy rules are preserved. (#134, partial)

- Recording Start, Stop and language restarts now use the shared capture coordinator. Stop interrupts pending model preparation, superseded language restarts cannot resume capture, and the final checkpoint completes before a new recording can start. Optional speaker analysis stays bound to the stopped run. (#134, partial)

- Validation: add headless Mac file-loading and audio-buffer tests. Archive save/read/clear orchestration now uses a shared tested repository while retaining existing error messages and secondary-data cleanup ordering. No new UI or permission behavior. (#134, partial)

- History search keeps its records when SwiftUI recreates a view, instead of replacing matching rows with an empty asynchronous result. (#223 acceptance fix)

- History search reuses unchanged passage vectors when a conversation is saved, including after summary insertion. Changed text or transcription language is re-indexed on-device; duplicate passages share one embedding attempt per save, including unsupported text. Existing indexes rebuild once. Semantic language coverage is unchanged. (#223, partial)
- Re-transcribe saved audio in a chosen language, preview the result, then replace the transcript or keep the original. Notes, attachments and summaries stay; speaker names and corrections reset while Apple Watch device labels remain. Recognition stays on-device. (#224)
- History search keeps its records when SwiftUI recreates a view, instead of replacing matching rows with an empty asynchronous result. (#223 acceptance fix)

- History search reuses unchanged passage vectors when a conversation is saved, including after summary insertion. Changed text or transcription language is re-indexed on-device; duplicate passages share one embedding attempt per save, including unsupported text. Existing indexes rebuild once. Semantic language coverage is unchanged. (#223, partial)
- Local Ollama setup distinguishes an unreachable server, an empty installation and unverified model capabilities. Onboarding and the status rail offer Retry, installation guidance and a copyable model-download command; pickers identify unavailable choices without discarding pinned models after failed checks. (#129)
- Optional current-calendar meeting suggestions offer **Use context and Start** in a new, empty conversation. Recording requires that click; passive checks never request Calendar permission. Dismissal persists for that event occurrence. Disabled by default. (#54)

- Failed model discovery preserves pinned choices and reports uncertainty. MiniMax is no longer ranked as a “mini” model. Verified local Ollama requests allow cold loads up to five minutes. (#141)
- Audio imports report read failures and keep partial transcripts marked incomplete across reopening. Legacy speech waits for final callbacks with a 30-second deadline; system capture rejects failed PCM copies and minimizes unused video work. (#141)
- Calendar context selects the most recently started overlapping meeting. Reference attachments reject symbolic links, heading whitespace renders correctly, and Markdown exports keep speech literal. Release discovery/signing and real-contract test gates now fail safely. (#141)

- OpenAI-compatible servers can use an optional per-server context limit. Answer space is reserved and oversized requests stop before sending; Mac prompt trimming includes a visible notice. Unknown capacity preserves server-managed behavior. (#210)

- Local Ollama requests size their context window to the full prompt instead of relying on a small server default. Prompts beyond the safe model capacity show an error before an answer request; cloud context remains server-managed. (#230)

- Vocabulary presets added to a conversation are saved and restored when you reopen it. Auto Quick now uses its domain and glossary, while new conversations keep only your device-wide defaults. (#237)

- Context now offers Ask Quick/Deep and saved summary instructions with optional domain presets. Modern History records can be reopened with their instructions. (#257)


- All seven vocabulary presets add focused Simplified Chinese terms selected by the transcription language, with on-device Chinese suggestions and the original English lists as fallback. My terms keeps its spelling and language. (#238)

- Export adds plain text, SRT and WebVTT subtitles and versioned JSON beside Markdown, recap and PDF, in the top bar and in a History conversation's detail sheet (which gains recap and PDF too). Files are named after the conversation's title and date instead of the clock time. With WhisperKit, exports carry `[mm:ss]` timestamps and subtitle cues, and each Listen in the same conversation now continues its timeline instead of restarting at 0:00; the default SpeechAnalyzer reports no times yet (#68), so its exports omit them and subtitles are unavailable. (#130)
- Save to folder notes record the language the conversation was transcribed in, kept with the conversation, instead of the current setting; Retry and Save all use each conversation's own. (#206)
- Conversations name themselves. A saved conversation still titled "Conversation — <date>" gets a short title after Stop, Save or New conversation, once it has about 30 words of transcript. The title comes from the finished Summary, from the Summary model when it is Apple Intelligence or local Ollama, or from keywords found on this Mac. With Ollama Cloud, a cloud AI service or an OpenAI-compatible server nothing is sent for a title. A typed title is never replaced; Load from Calendar replaces a default or automatic one. A Save to folder note updates in place. Settings → Name conversations automatically (on by default). (#221)
- On-demand Quick and Deep answers stay grounded with Auto off (the default). They used to read the last 4,000 characters (about four minutes; in practice half of that) and no summary, without saying so. Quick now reads up to about 16,000 characters and Deep 32,000 on Ollama and cloud models, and everything Apple Intelligence's window holds; in a longer meeting the Listener summary stands in for exactly the speech its ledger read (never one cut off at the output limit), the start and the latest part of the speech it did not read are sent, an oversized latest line keeps its most recent words so the window always holds, and the pane says what was used ("Using the Listener summary of the first ~10 min, the ~4 min after it and the last ~12 min of the conversation (~19 min in between left out)."). The line belongs to the answer it describes and disappears when a recap or a failed retry replaces that answer. (#114)
- An answer or summary that stops at the model's output limit (`finish_reason`/`done_reason` `length`, Claude `max_tokens`) keeps its text, and the pane says "The answer was cut off at the model's output limit." instead of showing it as complete. (#215)
- Domain vocabularies and My terms (Settings → Vocabularies): the same seven presets and your own list as on iPhone. They bias SpeechAnalyzer while you listen (live, no restart; the legacy recognizer from the next utterance), add the domain and a glossary to Listener, Quick and Deep, and lay the Listener summary out by domain. A banner above the transcript offers a preset when the conversation sounds like one — decided on this Mac, never turned on by itself — and right-clicking a transcript line adds a word to My terms. (#222)
- **Suggested · from context** chips above the fixed Quick actions: with Auto on, two or three one-tap prompts drawn from the conversation, carried by the Auto Quick check at no extra model call. A click sends the literal text through Quick (right-click → **Ask in Deep**); nothing is sent by itself. They refresh at most every 20 seconds, a used chip is not suggested again, and a new conversation, a model change, Auto off or AI off clears them. (#61)
- History (⌘F) search ranks by meaning as well as words with an on-device index (Apple NaturalLanguage), shows the matching excerpt under each result and marks conversations found only by meaning as "Related". The index sits beside the conversations (Dev and Release builds keep separate ones), is excluded from backups, rebuilds itself when damaged, and Clear history deletes it. Languages without an on-device model keep the keyword search. (#57)
- **Ask your history** in the History sheet answers the search text as a question from the best matching excerpts, citing the conversations it used (click a source to open it). It uses the Deep pane's model on the current AI mode: local Ollama and Apple Intelligence stay on this Mac, AI off disables it, and Ollama Cloud, Cloud AI and OpenAI-compatible routes are named as receiving the excerpts before you ask. (#57)
- Save audio recordings, off by default (Settings): each recording keeps the microphone and system audio as two labelled `.m4a` files beside the conversation; History plays them and, with WhisperKit, jumps to a line's time; share them from the player. Clear history deletes them, Settings has Delete all saved audio and automatic deletion after 7, 30 or 90 days, and a full disk stops the audio, never the transcript. Audio is saved only for conversations History keeps; Discard and Close without saving delete it, and a second recording in the same conversation seeks correctly. (#55)
- New AI mode **Cloud AI service**: OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, Groq, Mistral or xAI Grok with your own API key (Check key lists the vendor's models; Get a key and privacy-policy links). Each service is labelled "Sends your transcript to <vendor>", keeps its own Keychain key sent only to that vendor, and pane pickers list its models without ever picking one. Claude uses Anthropic's own Messages API. (#214)
- New AI mode **OpenAI-compatible**: point the panes at LM Studio, vLLM, llama.cpp, Ollama's /v1 API or OpenRouter with an optional Keychain key bound to that server; pane pickers list its /v1/models and never pick one for you; labelled "your server" or "may leave this device", never local; redirects are not followed. Plain http to `.local` names now works. (#52)
- Speaker identification matches voices across its periodic passes, so a participant who is silent for minutes keeps their Speaker N label and edited name; voice embeddings stay in memory for the run only. (#171)
- The transcription-language picker lists every language this Mac can transcribe on-device (Portuguese, Italian, Hindi, Arabic and more), grouped as Installed and Downloadable with the common languages first. (#172)
- Save to folder, off by default (Settings): each conversation is written as one Obsidian-friendly Markdown note into a folder you choose once capture stops, and updated in place as summaries change; failures show beside the saved time with Retry. (#53)
- Mic recovers from input-device changes and sleep/wake; a denied microphone is detected before Listen. (#107, #110)
- Ollama's own error text on HTTP failures; Apple Intelligence prompts bounded with a visible notice. (#118, #119)
- Automatic reviews survive notes typing, never overwrite a fresh manual answer, and use size-scaled deadlines. (#111, #115, #117)
- Manual prompts include provisional speech; live path no longer rebuilds the transcript per partial. (#113, #116)
- Panes keep their output on failure, "Thinking…" status for reasoning models, proactive Quick answers re-wired with a toggle. (#137, #112)
- SpeechRecognizer task identity, bounded speaker-audio memory, latched diarizer failures. (#108, #109)
- Preparing state, Session menu shortcuts, calendar title, and other lifecycle papercuts. (#136, #147)
- History stays readable when one saved conversation file is damaged: that file is set aside (renamed, never deleted) and History shows a warning instead of failing. Search matches notes and speaker names and ignores accents and full-width differences; reference files read `.rtf` and non-UTF-8 text, and a file that cannot be read shows "Not included" with the reason. (#120, #139)
- Model prompts fence transcript, notes and reference text as data. (#140)

## iOS 1.15.0 (32) — 2026-10-24

- Summarize selection: tap the checklist button on the Live transcript, pick lines (tap, or drag down their circles), and tap Summarize selection — or touch and hold a line for Summarize from here / Select from here. Only the selected lines, with their times and speakers (and your vocabulary and My terms), go to your chosen summary provider (on-device with Apple Intelligence by default; with another provider the sheet names it and sends only when you tap Summarize). The sheet offers Copy, Share and Add to notes; the last five are saved with the conversation under its Summary and included in exports (Markdown, plain text, JSON) and Save to folder notes. Cancel stops one mid-answer. A long selection is shortened to its first and latest lines and says so. (#234)
- The iPhone and iPad app now has two answers, Quick Summary and Summary; the Deep tab is gone (Deep stays on the Mac). Auto no longer runs Deep reviews, and Settings no longer asks for a Deep model for Apple Intelligence, Ollama, an OpenAI-compatible server or a Cloud AI service. A conversation saved with a Deep analysis keeps it: open it from History and expand **Earlier deep analysis** under the Summary (read-only). It stays in shared text, exports and Save to folder notes. (#235)
- Conversations name themselves. A conversation still called "New conversation" (or "Apple Watch · <date>") gets a short title after you stop or save, once it has about 30 words of transcript. The title comes from its summary when there is one; otherwise Apple Intelligence on this device (the default) or your own Ollama server writes it; with Ollama Cloud, a Cloud AI service or an OpenAI-compatible server nothing is sent for a title, and keywords found on this device name it, as they do without AI. A title you type is never replaced; Import from Calendar still replaces a default or automatic name with the meeting's. Naming never delays Stop, never runs while recording, and is not retried until the conversation has grown. Watch recordings are named too, and a Save to folder note updates in place. Turn it off in Settings → Conversations → Name conversations automatically. (#221)
- Delete all conversations, at the bottom of History and in Settings → Privacy. It asks first, naming how many conversations go and that it cannot be undone, and is unavailable while recording. It removes every conversation's transcript, notes, attachments, AI outputs and Apple Watch audio from this device, and the open conversation starts over. Recordings still waiting from Apple Watch are kept. Notes that Save to folder already wrote stay in your folder. (#220)
- Domain vocabularies and My terms (More → Settings → Vocabularies): Medical, Legal, Software & Cloud, Engineering, Finance, Sales and Education & Research presets, each a few hundred English-first terms written for the project, plus your own list of names, products and jargon in any language (add, edit, swipe to delete, import or export as plain text; long-press a transcript line → Add to My terms…). Up to 100 of them help on-device speech recognition, and change mid-recording without restarting the microphone; AI speech correction fixes near-misses to their spelling; Summary and Quick get the domain and a glossary, and only Summary follows the domain's headings (Medical: History / Findings / Plan). After about a minute of speech the phone may ask "Sounds like a medical conversation — add the Medical vocabulary?" with Add, Not now and Don't suggest again; the check runs on the device, nothing turns on by itself, and each preset is offered once per conversation. Medical is marked as not a medical device. (#222)
- History search understands meaning as well as words: a search for "money" can also find the conversation where you discussed the budget, marked "Related", and every result shows the matching excerpt (summary, notes or transcript). The search index is built on this iPhone with Apple's on-device language models, is never backed up and never leaves the device; deleting a conversation deletes its index entry. Languages without an on-device model keep the keyword search. (#57)
- Ask your history: type a question in the History search field and tap Ask to get an answer from the best matching excerpts of your saved conversations, with tappable sources. With Apple Intelligence it stays on this iPhone; with Ollama, an OpenAI-compatible server or a cloud AI service, History says before you ask that the excerpts (not whole conversations) and the question are sent to that service. (#57)
- Export as (More, and a History row's context menu) saves the conversation as a Markdown, plain-text, SRT or WebVTT subtitle, or JSON file through the share sheet, named after its title and date; the file is removed again when you delete conversations. Markdown, text and subtitles carry the recording's `[mm:ss]` / cue times, including Apple Watch recordings; subtitles name speakers when more than one person talks and split long lines. The JSON format is versioned and documented. (#130)
- Each conversation keeps the language it was actually transcribed in, including an Automatic switch and its Undo; Save to folder notes and exports use it instead of the current language setting, and a conversation lists every language its lines are in (an Undo keeps the language of speech after the switch). (#206)
- Quick and Deep no longer refuse a long conversation ("exceeds the selected provider's summary limit"), which on Apple Intelligence happened after about seven minutes. A Summary generated in this session stands in for exactly the speech it read; of the rest (with no Summary, the whole conversation) the start and the latest speech are sent, an oversized latest line keeps its most recent words, and the panel says what was used ("Using the opening ~2 min and the last ~5 min of the conversation (~38 min in between left out)."). A Summary restored from History, edited, cut off or shortened is sent but never claimed to cover anything. Summary still covers the whole conversation or says it does not fit. (#114)
- An answer or summary that stops at the model's output limit keeps its text, and the panel says "The answer was cut off at the model's output limit." Claude's partial text is now kept too; before, it was discarded while the message said it was shown. (#215)
- **Suggested · from context** under Quick Summary: two or three short questions drawn from the conversation, shown after an Auto check or a Quick refresh (Apple Intelligence included) at no extra request. Tap one to ask it: the answer appears in a small card under Quick Summary, below the question, and never replaces a summary; nothing is sent without a tap. They change at most every 20 seconds and clear on a new conversation or a provider change. (#61)
- Save audio recordings, off by default (Settings → Audio recordings): each recording also keeps its microphone audio with the conversation on this device, about 12 MB per hour, always left out of iCloud and Finder backups and never uploaded. Play it from the transcript — tap a line's time to hear it — and share the `.m4a` from the share sheet. Low or full storage stops the audio, never the transcript, with an orange note. Deleting a conversation deletes its audio; Settings has Delete all saved audio and Keep audio for 7, 30 or 90 days. Apple Watch recordings keep no audio. Turning it off stops saving at once, even mid-recording; a part the app was killed in still plays up to its last seconds. (#55)

## iOS 1.14.0 (31) — 2026-10-23

- Cloud AI services in Settings → Summary provider → Cloud AI: OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, Groq, Mistral and xAI Grok. Pick a service, paste your own API key (with a link to the vendor's key page) and choose a model for each role from the vendor's list; nothing is chosen for you and Apple Intelligence stays the default. Each service is labelled "Sends your transcript to <vendor>" with its privacy policy, keeps its own key in the Keychain and sends it only to that vendor. Claude uses Anthropic's own Messages API, with structured output for Auto Quick. The custom server is now listed as "Custom server (OpenAI-compatible)". (#214)

## iOS 1.13.0 (30) — 2026-10-23

- Save to folder, off by default (Settings → Save to folder): after you stop or save, each conversation is written as one Obsidian-friendly Markdown note — front matter with date, duration, language, speakers and tags, then summary, notes and a timestamped transcript — into a folder you pick in Files, such as an Obsidian vault or iCloud Drive. The note is updated in place when a summary or the title changes, never duplicated. A missing folder, lost access, a full disk or a file still in iCloud shows an orange line under the title and in Settings, with Retry. (#53)
- Automatic transcription language now re-checks the spoken language about once a minute while people talk, so a recording that changes language part-way switches too and transcribes again only the part since the change ("Detected French from 2:05 · switched"). A different language must be heard twice in a row before it switches, so a short phrase does not switch, and Undo goes back one switch. Re-checks run on this device and pause in Low Power Mode, in the background, when the device is hot and during silence. The app now holds only the latest two minutes of audio in memory for this. Words of two languages mixed within one sentence are not supported (#205). (#199)
- Settings → Transcription → Language lists every language this device can transcribe on-device, not a fixed eight, grouped as Installed and Downloadable with the common languages first; Automatic stays the default. (#172)
- Speaker labels recognize a returning voice: someone who stays quiet for minutes keeps their label and edited name instead of becoming a new Speaker N. Voices are compared on the device and only for the current recording; nothing about a voice is saved. (#171)
- Summaries can use any OpenAI-compatible server you enter — LM Studio, vLLM, llama.cpp, Ollama's /v1 API or OpenRouter (Settings → Summary provider). Settings says "your server" for this device or your network and "may leave this device" otherwise; the optional key stays in the Keychain, is sent only to that server and is removed when you change servers. Test this model on the Quick role checks the Auto format and pauses Auto with a reason if the model cannot follow it. (#52)
- Settings → About → Acknowledgements lists every open-source package in the app (WhisperKit, FluidAudio and their dependencies) with its full license text. (#202)

## iOS 1.12.0 (29) — 2026-10-23

- Speaker labels follow-up to 1.11.0: Identify speakers is now on by default (turning it off is remembered). Its models download as soon as the setting is on — at launch, when you turn it on, or when you start recording — so a short first recording is labeled at Stop. Recording never waits for the download. Settings → Speakers shows download progress, ready or failed with Retry. The status under the title says when labels are on, a line explains a download or failure, and Status details lists the speaker fields. Notes lists add-to-conversation tools before Speakers. (#195)
- Automatic transcription language, the new default (Settings → Transcription → Language): the iPhone detects the spoken language on the device from the first seconds of speech, switches once and transcribes the recording again, with Undo to keep the original language. A language you had already chosen stays fixed. The detection model (about 75 MB) downloads once from huggingface.co; audio never leaves the device. (#197)

## iOS 1.11.0 (28) — 2026-10-23

- Optional speaker identification, off by default (Settings → Speakers → Identify speakers): lines are labeled Speaker 1, Speaker 2… on this device, and Notes → Speakers renames them everywhere — the saved conversation, History search and exports. Speaker models download once from huggingface.co; it uses more battery while listening. (#180)

## iOS 1.10.5 (27) — 2026-09-15

- Settings → Privacy links the privacy policy and support pages required for the App Store. (#145)
- History warns about an unreadable saved conversation (quarantined, never deleted) instead of hiding the whole list; search covers notes and matches accents and full-width text. (#120, #139)
- Model prompts fence transcript, notes and reference text as data. (#140)

## iOS 1.10.4 (26) — 2026-09-14

- What's New appears only when the bundled notes change; first installs no longer see "In this update". (#138)
- Share imports: stale or failed batches are set aside and deleted after 24 hours instead of blocking later imports. (#138)
- Transcription language is remembered across launches; History is searchable. (#138)
- Conversations and attachments are written with device data protection, and a Settings toggle keeps them (and shared imports) out of iCloud and Finder backups. (#138)
- An Apple Intelligence install never contacts ollama.com; the model catalog refreshes only after you choose Ollama with a key or your own server. (#138)

## iOS 1.10.3 (25) — 2026-09-14 — Recording that survives the real world

- Calls, AirPods and switching apps no longer end a recording silently; you are told why it stopped
  and can resume.
- Calendar imports keep meeting links private, Apple Intelligence Quick answers are plain bullets,
  and typing no longer costs a save per keystroke.

## iOS 1.10.2 (24) — 2026-09-14 — On-device by default, or your own server

- New installs summarize on-device with Apple Intelligence. A provider you already chose is kept.
- Optional Ollama server URL: use a server you run. Your cloud key is never sent there.
- Summaries now say who said what, and never read your typed notes as speech.

## macOS 1.4.4 — 2026-09-14

- **First-run speech model download now happens before capture, and you can cancel it.** The first
  time you start listening, ListenToMe downloads the on-device speech model before any audio is
  captured, so the opening seconds of a meeting are no longer lost. The download is cancellable from
  Stop, New conversation, closing the window, or ⌘Q; it no longer freezes teardown until it
  finishes. (#99)
- **Auto follows your settings and knows who said what.** Automatic Summary and Deep reviews now
  honor the response language, use-case preset persona and (for Deep) attached reference files you
  chose for manual Generate, and every transcript line they see is prefixed with its speaker's
  label; a line prefixed "Notes: " is your typed note and is never reported as something said in
  the meeting. (#100, #101)
- CI now runs the `ListenToMeCore` test suite and the 95% coverage floor on every pull request, and
  `main` requires those checks. (#105)

## iOS 1.10.1 (23) — 2026-09-13 — Know what changed

- See the installed version and release highlights after an update.
- Reopen this changelog anytime from More → What's New.

## iOS 1.10.0 (22) — 2026-09-13 — Automatic reviews

- Auto updates Quick, Summary and Deep when new speech calls for a review. Manual Generate is still
  available.
- Quick stays concise, with clearer progress and recovery when a model response needs another try.

## macOS 1.4.3 — 2026-09-13

- Quick now publishes its first concise recap when a clear topic, problem or question appears; a
  decision, owner or deadline is no longer required. Questions are summarized without inventing
  answers or expanding ambiguous acronyms. Repetition still keeps the recap unchanged.
- An empty checked result now says "Speech checked · No takeaway yet" instead of "Summary
  unchanged."

## macOS 1.4.2 — 2026-09-13

- Automatic Quick Summary now reacts to substantial live recognition text before a phrase is
  finalized. Both platforms use the same five-second batching logic. Corrections replace
  provisional wording, and unchanged text or silence does not trigger model polling.
- Quick remains limited to three concise takeaways. Summary and Deep reviews remain manual.
- iOS 1.9.3 (20) also adds copyable Status details for speech events, timer checks and model reads.

## macOS 1.4.1 — 2026-09-13

- Quick Summary now shows useful interim recaps while catching up with a long conversation. A
  "Catching up" status indicates that remaining speech is still being processed. Automatic Quick
  recaps are limited to three short bullets and 480 characters, prioritizing the main takeaway,
  latest decision and next action. Summary and Deep reviews remain manual.

## macOS 1.4.0 — 2026-09-13

- Introduces the same event-driven live-summary scheduler used on iPhone and iPad.
- Opt-in Auto Quick Summary batches new finalized speech and notes, keeps unchanged output, and
  applies factual revisions.
- Summary and Deep Think recommendations include a reason and confidence; reviews run when
  requested.
- Ollama remains the default. Apple Intelligence is available for manual summaries on supported
  Macs; selecting it pauses Auto without a Cloud fallback.
- Stop, provider changes and Auto off cancel obsolete work. Failed evaluations preserve the current
  summary and retry unread input.

---

Earlier macOS releases (1.3.x and before) and iOS releases (1.9.x and before) are documented in the
[GitHub releases page](https://github.com/tomqwu/ListenToMe/releases) and
[`docs/IOS.md`](docs/IOS.md) respectively.
