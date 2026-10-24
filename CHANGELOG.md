# Changelog

All notable user-facing changes to ListenToMe (macOS) and ListenToMeIOS, in one place. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/); versions are listed newest first, macOS and
iOS interleaved by release date.

macOS entries are drawn from the [GitHub releases](https://github.com/tomqwu/ListenToMe/releases).
iOS entries are drawn from [`iOS/MobileReleaseNotes.swift`](iOS/MobileReleaseNotes.swift), the
in-app "What's New" copy shown once per set of bundled release notes — a build that changes no notes
does not show it again, and a fresh install does not see it at all; see
[`docs/IOS.md`](docs/IOS.md) for the fuller per-build technical notes and
[`metadata/ios/en-CA/`](metadata/ios/en-CA/) for TestFlight "What to Test" text.

## iOS (unreleased since 1.14.0 (31))

- Conversations name themselves. A conversation still called "New conversation" (or "Apple Watch · <date>") gets a short title after you stop or save, once it has about 30 words of transcript. The title comes from its summary when there is one; otherwise Apple Intelligence on this device (the default) or your own Ollama server writes it; with Ollama Cloud, a Cloud AI service or an OpenAI-compatible server nothing is sent for a title, and keywords found on this device name it, as they do without AI. A title you type is never replaced; Import from Calendar still replaces a default or automatic name with the meeting's. Naming never delays Stop, never runs while recording, and is not retried until the conversation has grown. Watch recordings are named too, and a Save to folder note updates in place. Turn it off in Settings → Conversations → Name conversations automatically. (#221)
- Delete all conversations, at the bottom of History and in Settings → Privacy. It asks first, naming how many conversations go and that it cannot be undone, and is unavailable while recording. It removes every conversation's transcript, notes, attachments, AI outputs and Apple Watch audio from this device, and the open conversation starts over. Recordings still waiting from Apple Watch are kept. Notes that Save to folder already wrote stay in your folder. (#220)
- Apple Watch companion, remote Start/Stop for the iPhone recorder (not yet shipped; ships with watch recording on the #181 train). (#181)
- iPhone transcribes recordings received from Apple Watch on-device and deletes the audio afterwards (not yet shipped). (#181)
- Record on Apple Watch with the iPhone elsewhere; the iPhone transcribes the audio on-device and deletes it (not yet shipped). (#181)
- Export as (More, and a History row's context menu) saves the conversation as a Markdown, plain-text, SRT or WebVTT subtitle, or JSON file through the share sheet, named after its title and date; the file is removed again when you delete conversations. Markdown, text and subtitles carry the recording's `[mm:ss]` / cue times, including Apple Watch recordings; subtitles name speakers when more than one person talks and split long lines. The JSON format is versioned and documented. (#130)
- Each conversation keeps the language it was actually transcribed in, including an Automatic switch and its Undo; Save to folder notes and exports use it instead of the current language setting, and a conversation lists every language its lines are in (an Undo keeps the language of speech after the switch). (#206)
- Quick and Deep no longer refuse a long conversation ("exceeds the selected provider's summary limit"), which on Apple Intelligence happened after about seven minutes. A Summary generated in this session stands in for exactly the speech it read; of the rest (with no Summary, the whole conversation) the start and the latest speech are sent, an oversized latest line keeps its most recent words, and the panel says what was used ("Using the opening ~2 min and the last ~5 min of the conversation (~38 min in between left out)."). A Summary restored from History, edited, cut off or shortened is sent but never claimed to cover anything. Summary still covers the whole conversation or says it does not fit. (#114)
- An answer or summary that stops at the model's output limit keeps its text, and the panel says "The answer was cut off at the model's output limit." Claude's partial text is now kept too; before, it was discarded while the message said it was shown. (#215)

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

## macOS (unreleased since 1.4.4)

- Export adds plain text, SRT and WebVTT subtitles and versioned JSON beside Markdown, recap and PDF, in the top bar and in a History conversation's detail sheet (which gains recap and PDF too). Files are named after the conversation's title and date instead of the clock time. With WhisperKit, exports carry `[mm:ss]` timestamps and subtitle cues, and each Listen in the same conversation now continues its timeline instead of restarting at 0:00; the default SpeechAnalyzer reports no times yet (#68), so its exports omit them and subtitles are unavailable. (#130)
- Save to folder notes record the language the conversation was transcribed in, kept with the conversation, instead of the current setting; Retry and Save all use each conversation's own. (#206)
- Conversations name themselves. A saved conversation still titled "Conversation — <date>" gets a short title after Stop, Save or New conversation, once it has about 30 words of transcript. The title comes from the finished Summary, from the Summary model when it is Apple Intelligence or local Ollama, or from keywords found on this Mac. With Ollama Cloud, a cloud AI service or an OpenAI-compatible server nothing is sent for a title. A typed title is never replaced; Load from Calendar replaces a default or automatic one. A Save to folder note updates in place. Settings → Name conversations automatically (on by default). (#221)
- On-demand Quick and Deep answers stay grounded with Auto off (the default). They used to read the last 4,000 characters (about four minutes; in practice half of that) and no summary, without saying so. Quick now reads up to about 16,000 characters and Deep 32,000 on Ollama and cloud models, and everything Apple Intelligence's window holds; in a longer meeting the Listener summary stands in for exactly the speech its ledger read (never one cut off at the output limit), the start and the latest part of the speech it did not read are sent, an oversized latest line keeps its most recent words so the window always holds, and the pane says what was used ("Using the Listener summary of the first ~10 min, the ~4 min after it and the last ~12 min of the conversation (~19 min in between left out)."). The line belongs to the answer it describes and disappears when a recap or a failed retry replaces that answer. (#114)
- An answer or summary that stops at the model's output limit (`finish_reason`/`done_reason` `length`, Claude `max_tokens`) keeps its text, and the pane says "The answer was cut off at the model's output limit." instead of showing it as complete. (#215)
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

## iOS 1.10.4 (26) — 2026-09-14

- What's New appears only when the bundled notes change; first installs no longer see "In this update". (#138)
- Share imports: stale or failed batches are set aside and deleted after 24 hours instead of blocking later imports. (#138)
- Transcription language is remembered across launches; History is searchable. (#138)
- Conversations and attachments are written with device data protection, and a Settings toggle keeps them (and shared imports) out of iCloud and Finder backups. (#138)
- An Apple Intelligence install never contacts ollama.com; the model catalog refreshes only after you choose Ollama with a key or your own server. (#138)

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

## iOS 1.10.3 (25) — Recording that survives the real world

- Calls, AirPods and switching apps no longer end a recording silently; you are told why it stopped
  and can resume.
- Calendar imports keep meeting links private, Apple Intelligence Quick answers are plain bullets,
  and typing no longer costs a save per keystroke.

## iOS 1.10.2 (24) — On-device by default, or your own server

- New installs summarize on-device with Apple Intelligence. A provider you already chose is kept.
- Optional Ollama server URL: use a server you run. Your cloud key is never sent there.
- Summaries now say who said what, and never read your typed notes as speech.

## iOS 1.10.1 (23) — Know what changed

- See the installed version and release highlights after an update.
- Reopen this changelog anytime from More → What's New.

## iOS 1.10.0 (22) — Automatic reviews

- Auto updates Quick, Summary and Deep when new speech calls for a review. Manual Generate is still
  available.
- Quick stays concise, with clearer progress and recovery when a model response needs another try.

---

Earlier macOS releases (1.3.x and before) and iOS releases (1.9.x and before) are documented in the
[GitHub releases page](https://github.com/tomqwu/ListenToMe/releases) and
[`docs/IOS.md`](docs/IOS.md) respectively.
