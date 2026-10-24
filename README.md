<div align="center">

<img src="docs/images/icon.png" width="120">

# ListenToMe

**The free, open-source, fully on-device meeting copilot for macOS — with a private capture-and-recall companion for iPhone and iPad. Bring your own model, stay private, shape it to any conversation.**

[![CI](https://github.com/tomqwu/ListenToMe/actions/workflows/ci.yml/badge.svg)](https://github.com/tomqwu/ListenToMe/actions/workflows/ci.yml)
![Coverage](https://img.shields.io/badge/Core_coverage-96%25-brightgreen)
![Platform](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Release](https://img.shields.io/github/v/release/tomqwu/ListenToMe?include_prereleases&sort=semver)

</div>

ListenToMe listens to your mic and the other participants' system audio, transcribes live, and gives
real-time AI help — all on your Mac. It runs transcription on-device with Apple's SpeechAnalyzer and
routes AI inference through [Ollama](https://ollama.com), so with a local model **your audio and
transcript never leave the machine**.

## iPhone and iPad

**The iPhone and iPad app is a personal capture and recall companion, not a port of the Mac copilot.**
It transcribes what the device's own microphone hears — an in-person conversation, a lecture, an
interview, a phone on the table — summarizes it on-device by default, and keeps conversations local,
searchable and shareable. It is deliberately not a copilot for calls or video meetings: iOS does not
let an app capture another app's audio, so the dual-channel "You / Others" experience stays
macOS-only, and there is no Mac↔iOS sync. See
[what this app is for](docs/IOS.md#what-this-app-is-for),
[parity with macOS](docs/IOS.md#parity-with-macos) and
[the version policy](docs/IOS.md#version-policy).

The standalone iOS/iPadOS 26 app is the **ListenToMeIOS** target: microphone transcription, a live
transcript with Quick Summary plus a Summary tab (Deep is macOS-only), **Summarize selection** for just
the lines you pick (Select, or touch and hold a line → Summarize from here), local conversations with search, photo/file
attachments, Apple Notes and share-sheet imports, calendar import with e-mail and join-link
redaction, Markdown sharing, and an opt-in **Save to folder** that writes each conversation as a
Markdown note into a folder you pick in Files, such as an Obsidian vault. On-device speaker identification (on by default; turn it off in
Settings) labels transcript lines Speaker 1, Speaker 2… for the people one phone hears, and you can
rename them; its models download once from `huggingface.co`. The transcription language defaults to
Automatic: the phone detects the spoken language on-device from the first seconds of speech and, if it
differs from the device language, switches and transcribes the recording again; it re-checks about once
a minute while people talk, so a meeting that changes language part-way switches too (its small Whisper
model downloads once from `huggingface.co`; audio never leaves the device). Choose on-device Apple
Intelligence — the default on capable devices — or Ollama: Ollama Cloud with your own key, or an
Ollama server you run on your own network — or a cloud AI service with your own key (OpenAI,
Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, Groq, Mistral, xAI), each labelled "Sends your
transcript to <vendor>" — or any OpenAI-compatible server you enter (LM Studio,
vLLM, llama.cpp, OpenRouter), labelled "your server" on your own network and "may leave this device"
elsewhere. Presets, reference files, audio-file import and WhisperKit
transcription are macOS-only.
See [iOS setup, validation and distribution](docs/IOS.md).

```sh
make ios-build
make ios-test
```

## Screenshot

![ListenToMe — four-pane meeting copilot](docs/images/screenshot.png)

## Why ListenToMe

- **On-device & private.** Transcription runs locally via Apple SpeechAnalyzer, and AI help can run
  entirely against a local Ollama model — audio and transcript need never leave your Mac.
- **Bring your own model.** Pick any Ollama model, local or cloud, a cloud AI service with your own
  key (OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Groq, Mistral, xAI), or point the app at any
  OpenAI-compatible server (LM Studio, vLLM, llama.cpp, OpenRouter), instead of being locked to a
  single undisclosed backend LLM.
- **Multi-pane, multi-model.** Four panes, and each AI pane runs its own model — picked from the
  left status rail — run a fast model for live notes and a stronger one for deep analysis, side by
  side, in the same conversation.
- **Multi-purpose presets.** Use-case presets (Meeting, Interview, and more) plus file/folder
  reference context let one app serve meetings, interviews, study, support, and beyond.
- **Free & open-source.** No subscription, no seat pricing, no closed pipeline — the code is open
  for inspection.

## How it compares

Distilled from [`docs/competition-analysis.md`](docs/competition-analysis.md); facts are stated as of
2026 and qualified where they couldn't be confirmed from a primary source.

| Tool | On-device | BYO model | Multi-pane | Presets | Price |
|---|---|---|---|---|---|
| **ListenToMe** | Yes — transcription + local AI | Yes — Ollama local + cloud, OpenAI/Claude/Gemini/DeepSeek/OpenRouter/Groq/Mistral/xAI with your key, any OpenAI-compatible server | Yes — per-pane model | Yes | Free & open-source |
| Granola | No — local capture, cloud ASR + AI | Reported, unconfirmed | No | Templates (29+) | Free; ~$14–35/user/mo |
| Otter.ai | No — cloud | No | No | Limited | Free; ~$8–30/user/mo |
| Fireflies.ai | No — cloud | No (export via MCP) | No | Limited | Free; ~$10–39/seat/mo |
| Cluely | No — cloud | No / undisclosed | No | No | Free; $19.99–149.99/mo |
| MacWhisper | Yes — on-device by default | Yes — BYO keys (Gumroad) | No | Prompts | Free; ~$69 one-time / subs |
| Natively (OSS) | Yes — STT on-device; AI local or cloud | Yes — Gemini, OpenAI, Claude, Groq, Ollama | No | No | Free personal; paid Pro |
| Hyprnote (OSS, now Anarlog) | Partial — on-device STT option; AI local or cloud | Yes — Ollama, LM Studio, OpenRouter | No | No | Free (MIT); paid enterprise |
| Meetily (OSS) | Yes — local by default; cloud LLMs optional | Yes — Ollama local, or cloud APIs | No | No | Free (MIT); paid Pro/Enterprise |

## Features

**Live capture & transcription**
- Dual-channel capture: your mic + the other participants' system audio, source-labeled.
- On-device transcription via **Apple SpeechAnalyzer** (default) or the legacy **SpeechRecognizer**.
- **Transcription-language** picker listing every language your Mac can transcribe on-device, and
  **audio-file import** to transcribe an existing recording.
- **Survives device changes:** connecting AirPods, docking/undocking or sleep/wake re-installs the
  microphone tap and restarts capture in place ("Mic: input changed — resumed"); a stopped
  system-audio stream gets the same one-shot restart. If a channel really cannot be recovered, the
  capture line turns red with ⚠️ instead of leaving a dead channel under a running timer.
- **No silent recordings:** Listen checks microphone authorization first. If access is denied (or
  restricted by device management), the app explains it and offers **Open Settings** rather than
  reporting "Mic: active" while recording silence.

**Four-pane AI copilot**
- **Transcript** — live, source-labeled, no model.
- **Listener** — rolling summary plus open questions / action items.
- **Quick** — fast suggestions on the global hotkey, buttons, or proactively when someone asks a
  question. **Proactive** (the checkbox in the Quick pane header, on by default) answers a finalized
  question from **Others** automatically: your own questions never trigger it, repeat questions are
  debounced, and an answer you asked for is never cut off mid-stream. It is independent of **Auto**,
  which writes the periodic recap.
- **Deep** — on-demand, detailed long-reasoning answers.
- On-demand Quick and Deep answers stay grounded in the meeting even with Auto off (the default).
  They read the whole conversation when it fits — up to about 16,000 characters (~18 minutes of
  speech) for Quick and 32,000 for Deep on Ollama and cloud models, and whatever fits Apple
  Intelligence's small window. In a longer meeting the Listener summary stands in for exactly the
  speech it has read; of the speech it has not read (with no summary, the whole meeting), the start
  and the most recent part are sent, at no extra model call. A summary that stopped at the output
  limit is sent but never treated as covering anything. The pane says what was used, for example
  "Using the Listener summary of the first ~10 min, the ~4 min after it and the last ~12 min of the
  conversation (~19 min in between left out)." Listener context is shared into Quick and Deep
  whenever a summary exists (after **Refresh**, or automatically with **Auto**).
- An answer or summary that stops at the model's output limit keeps its text, and the pane says "The
  answer was cut off at the model's output limit."
- **Auto** writes Quick, Listener and Deep automatically while you listen, from the same
  speaker-labeled transcript and under the same settings as a manual Generate: your AI
  response-language and the selected use-case preset. Attached reference files reach automatic
  Deep only, matching manual Deep; automatic Quick and Listener get none. Auto output cannot flip
  the pane's language or drop your persona.
- An answer you asked for in Quick ("Draft reply", "Key terms"…) stays on screen: the automatic
  recap keeps updating behind it and **Show recap** switches back. Typing in Notes never cancels a
  running automatic review, and a review that exceeds its deadline says so instead of repeating the
  same request — the deadline scales with the conversation's length and is exactly twice as long for
  Deep. A dropped or stalled connection is still retried normally.

**Bring-your-own-model**
- Each AI pane's model is set from a **model picker in the left status rail**, listing chat-capable
  models discovered from your Ollama server — local and Ollama-cloud (`:cloud`) models alike.
- **OpenAI-compatible servers.** Choose the **OpenAI-compatible** AI mode and enter a server URL —
  LM Studio (`http://localhost:1234/v1`), vLLM, llama.cpp, Ollama's own `/v1` API, or
  `https://openrouter.ai/api/v1` — plus an optional key. The pane pickers list the server's
  `/v1/models`; panes stay unset until you pick a model, because a hosted catalog can list hundreds
  of vendors' models. See [OpenAI-compatible servers](#openai-compatible-servers).
- **Cloud AI services.** Choose **Cloud AI service**, pick OpenAI, Anthropic Claude, Google Gemini,
  DeepSeek, OpenRouter, Groq, Mistral or xAI Grok and paste your own key; each pane's model is your pick
  from that vendor's list. See [Cloud AI services](#cloud-ai-services).
- **AI response-language** setting, independent of the transcription language.

**Make it yours**
- **Use-case presets** (Meeting, Interview, etc.) tune the copilot's behavior.
- **File & folder reference context** with a configurable token budget.
- **Markdown session export** for sharing or review.
- **Save to folder** (off by default, Settings): after each conversation stops, writes one
  Obsidian-friendly Markdown note (YAML front matter, summary, notes, timestamped transcript) into a
  folder you choose, and updates the same note when summaries or the title change.
- **First-run onboarding**, a global **⌘⇧Space** hotkey for instant suggestions, and keyboard
  equivalents for every frequent action (see [Keyboard shortcuts](#keyboard-shortcuts)).

## Requirements

- **macOS 26+**
- [Ollama](https://ollama.com) — running locally for local models, and/or an Ollama Cloud API key
  for cloud models. The app auto-picks an installed model on first launch. Alternatively, any
  OpenAI-compatible `/v1/chat/completions` server (LM Studio, vLLM, llama.cpp, OpenRouter), or your
  own API key for a cloud AI service (OpenAI, Anthropic, Google Gemini, DeepSeek, OpenRouter, Groq,
  Mistral, xAI).
- To build from source: Xcode 26+, `brew install xcodegen` (optionally `swiftlint`, `xcbeautify`).

## Install

**Download (recommended)**
- Grab the notarized `.dmg` from [Releases](https://github.com/tomqwu/ListenToMe/releases),
  open it, and drag **ListenToMe** to **Applications**. See [`CHANGELOG.md`](CHANGELOG.md) for
  what changed in recent macOS and iOS releases.

**Build from source**
```bash
brew install xcodegen
make run
```

## Build & run

```bash
make test     # run the ListenToMeCore test suite (unit + integration)
make build    # generate the Xcode project and build the app
make run      # build and launch
make pre-push # lint + tests + build (the CI-equivalent gate)
```

Optional: copy `signing.local.mk.example` to `signing.local.mk` (gitignored) and set your
code-signing identity so granted macOS permissions (mic/screen/accessibility) persist across
rebuilds (otherwise each rebuild re-asks). Find it via `security find-identity -v -p codesigning`.

On first run, grant Microphone, Speech Recognition, Screen Recording (for system audio), and
Accessibility (for the global hotkey) in System Settings → Privacy & Security. The app shows an
onboarding sheet on first launch; grant these permissions from **More → Permissions…** at any time
after that. **Quit & Reopen** (offered after granting Screen Recording) finalizes and saves the
current conversation first — if you cancel that save, nothing is relaunched, so you never end up
with two copies of the app competing for the microphone. Microphone access is also re-checked every
time you press **Listen**: without it macOS
hands the app silence rather than an error, so the app refuses to start and points you at the
Microphone pane (a managed/restricted Mac gets the explanation without the Settings shortcut).

### Dev builds are a separate app

Debug builds use bundle id `com.tomwu.ListenToMe.dev` and appear as **ListenToMe (Dev)**; the
released dmg uses `com.tomwu.ListenToMe`. macOS keys permission grants by bundle id *and*
code-signing requirement, and the two are signed with different certificates (Apple Development vs
Developer ID), so a shared bundle id would make each install silently invalidate the other's
grants. With separate ids they get their own rows in System Settings → Privacy & Security and can
be installed side by side — you grant permissions once per app.

The Ollama API key stays shared: `KeychainStore` uses a fixed service name, so you paste the key
once. macOS asks each binary for keychain access the first time it reads the item — choose
**Always Allow**.

## Models, presets & languages

- **Per-pane models.** Each of Summary, Quick, and Deep has a model picker in the left status
  rail; the pane header shows the currently selected model as read-only text. Choices persist
  across launches; **More → Refresh models** re-scans installed models (e.g. after `ollama pull`).
  On first launch any role whose saved model isn't installed auto-switches to one that works — no
  manual config needed. Auto-picks are local-first: only models Ollama's own `/api/show` metadata
  verifies as downloaded are considered while any exist, so an unpinned pane is never silently
  assigned a cloud-hosted model.
- **Summary refresh.** The Summary pane's **Refresh** button is enabled only when there is speech it
  has not summarized yet — refreshing with nothing new would just have the model rewrite the record
  already on screen.
- **AI processing mode.** In **Settings**, explicitly choose **Local only**, **Apple Intelligence**,
  **Cloud**, **Cloud AI service**, **OpenAI-compatible**, or **AI off**.
  Local mode verifies downloaded-model metadata before every request and rejects remote/cloud-backed
  models and redirects. Apple Intelligence runs entirely on this device; because its on-device model
  has a small context window, every prompt is capped at 8,000 characters — long meetings are answered
  from the summary or the opening plus the most recent speech, each pane says which part it read, and
  the status line says when material was trimmed. Cloud mode uses
  `https://ollama.com` and the key stored in macOS Keychain.
  It sends transcript, notes, summary and attached reference context to Ollama Cloud. Adding a key
  alone does not switch modes. AI off leaves capture, transcription and saving available.
  When Ollama refuses a request, the pane shows the server's own explanation with its HTTP status —
  a rejected API key and an exhausted quota read as such, not as a missing local model. A failed
  request keeps the text the pane was already showing and reports the error as a banner beside it,
  so a transient failure never blanks a summary or answer you were reading. Reasoning models show
  "Thinking…" in the pane header while they reason; that reasoning is never added to the answer.
- **Prompts separate data from instructions.** Transcript, rolling summary, Context notes and
  attached reference material are wrapped in labelled `<transcript>`/`<summary>`/`<notes>`/
  `<reference>` blocks, and every system prompt states that text inside them is data to read and
  summarize, never instructions to follow. This hardens the panes against instruction-like text
  spoken by another participant or embedded in an attached file; it cannot fully prevent it, so
  treat pane output — including any links it contains — with the same care as the source material.
- **Presets.** Pick a use-case preset to tailor how the copilot responds.
- **Languages.** Independent **transcription-language** and **AI response-language** pickers. The
  transcription list is not hard-coded: at launch the app asks the OS which languages on-device
  transcription supports (`SpeechTranscriber.supportedLocales`) and which of their speech models are
  already installed (`AssetInventory`), and lists them as **Installed** and **Downloadable**, common
  languages first (`TranscriptionLanguageCatalog` in Core, shared by macOS and iOS). A downloadable
  language's model downloads from Apple the first time you record in it. If the language you pick (or
  your system language under "Auto") still isn't supported, the status line says so by name and
  names the language it is transcribing in instead — it never silently substitutes English.
- **Reference files.** Add files/folders as context, with a configurable token budget. `.rtf` is read
  as its text (never `\rtf1` markup), and non-UTF-8 files (Windows-1252, UTF-16 exports) are decoded
  instead of dropped. Anything that still cannot be included is listed next to the attachments as
  "Not included", with the reason — a file the model never saw is never invisible.
- **Audio import.** Import an audio file to transcribe it.
- **Save conversation (⌘S).** Saves finalized transcript, speaker names, notes and available AI outputs
  without stopping capture. A visible saved time acknowledges success. Failed saves offer Retry / Save As.
- **New conversation (⌘N).** Finishes and saves the current conversation, then clears transcript,
  AI context, notes, names and attached references. Model/language/appearance preferences remain.
- **History (⌘F).** Search saved conversations, open their full contents, and copy/export Markdown.
  Search is case-, accent- and width-insensitive ("cafe" finds "café", "ai" finds "ＡＩ"), splits the
  query on any whitespace including tabs, ranks whole-word matches above matches inside longer words,
  and covers title, summary, notes and the transcript's own words (not the "You:"/"Others:" prefixes).
- **Export (⌘E).** Export the current conversation as Markdown; PDF and recap are also in Export.
  With autosaving off, Save opens Save As and New/Close offers Save As, Cancel or explicit discard.
- **Load from Calendar.** Fills Context notes from your current or next meeting *and* titles the
  conversation after the event (only while the title is still the generated "Conversation — <date>",
  so a title you typed is kept). If Calendar access is denied the banner says so and offers **Open
  Calendar privacy settings**; "no meeting right now" is a separate, distinct message. Every banner
  message can be dismissed with its ✕.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⇧L | Start / Stop listening |
| ⌘⇧Space | Quick answer (global — works while another app is front, needs Accessibility) |
| ⌘⇧D | Deep answer |
| ⌘⇧R | Recap so far |
| ⌘⇧U | Refresh summary |
| ⌘S | Save conversation |
| ⌘N | New conversation |
| ⌘E | Export conversation |
| ⌘F | Conversation history |
| ⌘, | Settings |

All of these except ⌘⇧Space are menu items, so they act on the key window. With the main window
closed (the app still in the Dock) they are shown disabled rather than silently doing nothing —
reopen the window from the Window menu or the Dock icon first. ⌘⇧Space is a fixed global hotkey.

Autosaving checkpoints finalized text as it changes and available outputs once per second. Current
partial speech is not acknowledged as saved. An interrupted session is available in History through
its last successful checkpoint. Release history lives in `~/Library/Application Support/ListenToMe/Conversations`;
Debug uses `ListenToMe Dev/Conversations`. Legacy `sessions.json` imports once and remains for rollback
until **Clear history** deletes it in the Release app. Turning autosaving off keeps existing history.
A single damaged conversation file no longer hides the rest: it is renamed to
`<id>.json.corrupt-<timestamp>` (never deleted), the remaining conversations still list, and History
shows a one-line note saying what was set aside. An unreadable legacy `sessions.json` is set aside the
same way, so saving, autosave checkpoints and **Clear history** keep working instead of failing forever.
History is local, unencrypted JSON and currently reopens for reading/export, not editing or resuming.

**Save to folder** (Settings, off by default) additionally writes each conversation as one Markdown
note into a folder you choose, for example an Obsidian vault. It follows autosaving: the note is
written once capture stops and rewritten whenever a later checkpoint changes it (a summary, the title,
notes). The file name is keyed by the conversation ID — `2026-10-23 1430 ListenToMe 1a2b3c4d.md` —
so renaming a conversation updates the same note instead of creating a duplicate. A file is replaced
only when its front matter carries this conversation's `listentome_id`; another note with a matching
name is never overwritten (a short-key collision gets the longer, whole-ID name instead), and a note
you rename yourself is left alone, so the next update writes a new note under the usual name. The note's
date is the conversation's first checkpoint. Writes are atomic; a missing folder, lost permission, a
full disk or a file still in iCloud shows an orange note beside the saved time with Retry, and one bad
note never holds up the others. Quitting waits up to five seconds for the last note; notes left
unwritten are retried at the next launch. Deleting a conversation from History does not delete its
note, and **Clear history** drops any notes still waiting so they are never written.

### Automatic speaker identification (experimental)

In Settings, enable **Automatic speaker identification** and choose **WhisperKit** before
pressing Listen. The app analyzes captured system audio on-device about every 20 seconds
(longer when analysis takes more time), and runs a final pass after Stop. The first use downloads
speaker models. Open **Speakers / edit names** to name voices, for example Speaker 1 → Alice.

Names appear in transcript lines and flow into subsequent AI prompts, refreshed listener summaries,
saved-session search, and Markdown/PDF exports. Saving a name clears older Quick/Deep answers;
request them again to use the new name. Speaker identities are matched across analysis passes by
shared audio timing first, then by voice. Ambiguous splits or merges may receive new labels instead
of inheriting an incorrect name. Labels and names are scoped to each recording run; starting another run preserves
older transcript labels but does not recognize people from past runs.

Enable **Identify people sharing my microphone** to also separate voices on the microphone channel.
The two audio channels are analyzed independently; the same person heard on both is not automatically
merged. Without this option, microphone speech remains **You**. SpeechAnalyzer and SpeechRecognizer
support the voice breakdown only; per-line attribution requires WhisperKit timestamps.

This is delayed, periodic identification, with one speaker assigned per transcript line. Overlapping
speech can be misattributed. Analysis covers the first approximately two hours of each enabled channel.
Imported audio files do not use this live-capture speaker analysis. Audio is buffered in memory for
analysis; speaker names are included in saved transcript text when session saving is enabled.

Each periodic pass re-analyzes only the most recent audio (a trailing window of at most ten minutes,
overlapping the previous pass so identities carry over), so identification cost stays flat instead of
growing with the meeting. A pass first carries over the speakers it shares audio with; each speaker
also keeps a running voice embedding for the recording, and the voices left over are matched to it,
one person per label, so someone who stays quiet for minutes keeps their label and edited name when
they speak again
([issue #171](https://github.com/tomqwu/ListenToMe/issues/171)). Two very similar voices, or one
person heard in very different conditions, can still be split or given a new label. The voice
embeddings stay in memory for that recording only and are never saved, so people are not recognized
across runs. Captured audio is held in fixed 10-second blocks, so a pass never copies the
whole session. Memory ceiling: up to about 460 MB per enabled channel for a full two hours — roughly
920 MB with microphone identification also enabled.

If the speaker models cannot be loaded (for example offline on their first use), automatic
identification stops instead of retrying every 20 seconds, and the Speakers rail shows one line
saying so. Press **Speakers / edit names** to retry once the network is available.

## Privacy

- **On-device transcription.** Speech-to-text runs locally via Apple SpeechAnalyzer (or
  SpeechRecognizer) — both on-device.
- **Local-only AI.** The app accepts only models whose local Ollama metadata identifies downloaded
  weights without a remote destination. Unknown routing is rejected, including cloud model aliases
  served through a local daemon. This trusts the installed local Ollama service and its metadata.
- **Explicit cloud choice.** Select Cloud in Settings to send AI prompt context to Ollama Cloud.
  Audio transcription and experimental speaker processing remain on-device; their models may download
  on first use. Select AI off to stop model requests while continuing to capture and save.
- **One-time model downloads, and which hosts they touch.** In Local-only mode the app otherwise
  contacts only `localhost:11434` (your Ollama daemon). The WhisperKit transcription engine and the
  FluidAudio speaker-identification models are fetched from `huggingface.co` the first time you
  enable them (on macOS, and on iPhone/iPad when Identify speakers is on), as is the iPhone/iPad's
  small Whisper language-detection model the first time an Automatic-language recording hears speech; Apple SpeechAnalyzer/SpeechRecognizer download their on-device language assets from
  Apple's own asset servers the first time you use them. None of these downloads carry audio,
  transcript, or key material — they fetch model weights only.
- **Sandbox and permissions.** The macOS app is **not sandboxed**
  (`com.apple.security.app-sandbox` is `false` in `App/ListenToMe.entitlements`), so it has
  unrestricted user-level file and network access rather than the narrower access a sandboxed app
  would be limited to. This is so file/folder reference context can read arbitrary paths you attach
  without security-scoped bookmarks. It still asks macOS for the Microphone, Speech Recognition,
  Screen Recording, and Accessibility permissions listed above, and only uses them for the features
  described in this README.
- **iOS storage and backup.** Conversations, attachments and queued share imports are written with
  iOS data protection (readable only after the device has been unlocked once since a restart). They
  are included in the device's normal iCloud/Finder backup by default, so a restored phone keeps
  them; **Settings → Privacy → Exclude conversations from iCloud backup** keeps them off any backup.
  Model catalogs are fetched only from a destination you configured — never anonymously.
- **iOS privacy policy and support.** The App Store pages are checked in and linked from the app in
  **More → Settings → Privacy**: [privacy policy](docs/ios-privacy.md) and
  [support](docs/ios-support.md).

## Architecture

- **`ListenToMeCore`** (Swift package): all testable logic — conversation state, VAD, question
  detection, prompt building, Ollama provider, model router, context engine, `MeetingSession`.
- **`iOS/`**: iPhone/iPad SwiftUI app, foreground microphone capture with SpeechAnalyzer, optional Foundation Models summaries.
- **`App/`**: macOS glue — `DualChannelCapture`, `SpeechRecognizerTranscriber`, SwiftUI UI, hotkey.

See [`docs/reviews/2026-09-10/design-and-gap-review.md`](docs/reviews/2026-09-10/design-and-gap-review.md)
for the current architecture and gap review. The original
[`docs/superpowers/specs/2026-06-18-listentome-design.md`](docs/superpowers/specs/2026-06-18-listentome-design.md)
and [`docs/superpowers/plans/2026-06-18-listentome-mvp.md`](docs/superpowers/plans/2026-06-18-listentome-mvp.md)
are historical: the June MVP spec/plan predate Save/New/History, presets, speaker diarization,
explicit AI processing modes, and the iOS app.

### CI

GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs checks for PRs to `main` on
`macos-26` runners: both app targets compile with the checked-in dependency lock, and the full
`ListenToMeCore` test suite (unit + headless integration/e2e) runs with a **coverage floor of 95%**
enforced by `scripts/check-coverage.sh`. SwiftLint, iOS simulator UI tests, GUI/audio acceptance, and
distribution checks require local validation via [`docs/manual-smoke-test.md`](docs/manual-smoke-test.md).

`make e2e` runs the checks CI can't (it needs a real Mac + Ollama): it builds the app target,
verifies `make run`'s app-path resolution, and runs a real LLM contract test against your local
Ollama through the actual `OllamaProvider`, auto-selecting an installed chat model (override with
`LTM_E2E_MODEL=...`). Mic/system-audio capture and live speech-to-text remain manual — see
[`docs/manual-smoke-test.md`](docs/manual-smoke-test.md).

## Known limitations

- **Transcription engine (Settings):** the default **SpeechAnalyzer** (macOS 26) transcribes both
  channels concurrently. The legacy **SpeechRecognizer** option uses one `SFSpeechRecognizer` per
  source and may hit a process-global active-recognition limit (`kAFAssistantErrorDomain 1100`) on
  some systems. SpeechAnalyzer downloads its language model on first use. Both are on-device.
- **First run downloads the speech model before listening starts.** Pressing Listen the first time
  shows **PREP** in the rail (not REC) and "Transcription: preparing on-device speech model…"; no
  audio is captured and automatic AI reviews are paused until the model is ready, so nothing said
  afterwards is lost and no recap is generated from the previous conversation. The download can
  take several minutes on a slow connection; Stop, New conversation, closing the window and Cmd-Q all cancel it immediately.
- A short utterance spoken entirely within the brief recognizer-finalization gap may merge into the
  next finalized segment.
- **Ollama, Apple Intelligence and OpenAI-compatible servers.** Ollama Cloud exposes
  GPT/DeepSeek/Qwen/etc. through one key, Apple Intelligence covers on-device inference without
  Ollama, the Cloud AI service mode reaches eight vendors with your own key (#214), and the
  OpenAI-compatible mode reaches any `/v1/chat/completions` server (#52) — see below.
- **WhisperKit engine (opt-in):** an opt-in third transcription engine for true multilingual
  code-switching (e.g. Mandarin↔English mid-sentence) that Apple's on-device Speech can't do. It
  downloads a model on first use (before capture starts, same as above), emits finalized segments
  only (no live partials), and its
  dual-channel finals may occasionally interleave out of chronological order.

### Cloud AI services

Choose **Cloud AI service** in **Settings → AI processing** (on iPhone: **Summary provider → Cloud AI**),
pick a service — **OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter, Groq, Mistral or
xAI Grok** — and paste your own API key (**Get a key** opens the vendor's key page). No URLs to type
(#214). Nothing is selected by default: local Ollama stays the macOS default and Apple Intelligence the
iPhone default, and the app ships with no keys.

- **Labelled.** Each service says **"Sends your transcript to <vendor>"**, names the host and links the
  vendor's privacy policy. The vendor's terms apply and you pay it for what you use.
- **One key per vendor.** Each service has its own Keychain item, bound to that vendor's fixed address;
  switching services keeps every key and never sends one vendor's key to another.
- **You pick every model.** Models come from the vendor's own list (**Check key** on macOS, **Refresh
  models** on iPhone) and are never assigned for you; suggestions such as Claude Opus 5.5 are only
  highlighted.
- **Same guarantees as a custom server.** Redirects refused, strict stream termination, a 16 MiB cap and
  keys masked in errors. Vendor quirks are handled: Gemini's OpenAI path, OpenAI's
  `max_completion_tokens`, DeepSeek's `reasoning_content`, OpenRouter's attribution headers.
- **Claude speaks Anthropic's own Messages API**, not an OpenAI shim, over plain `URLSession` (no vendor
  SDK is linked): no sampling parameters, effort `low` for Auto Quick and `medium` for Summary/Deep,
  structured output so Auto Quick always gets valid JSON, refusals (partial text discarded) and length
  cut-offs shown clearly, one retry on 429/529 when `retry-after` asks, and server-side refusal
  fallbacks on Opus 5.5 and Sonnet 5.5 Summary and Deep requests (another Claude model continues a
  declined answer).

### OpenAI-compatible servers

Choose **OpenAI-compatible** in **Settings → AI processing** (or **Summary provider** on iPhone) and enter
the server's base URL: LM Studio (`http://localhost:1234/v1`), vLLM or llama.cpp, Ollama's own
`http://localhost:11434/v1`, or a hosted API such as `https://openrouter.ai/api/v1`. A bare origin gets
`/v1`; a pasted `…/chat/completions` is trimmed. Nothing is chosen for you and nothing is discovered.

- **Honest about where it goes.** The address decides the label: this machine, a `.local` name or a
  private address reads **your server**; anything else reads **may leave this device**. A custom server
  is never called local or on-device — ListenToMe cannot verify where it runs the model, and a server
  on `localhost` can relay to a cloud service (Ollama's `/v1` serves `:cloud` models from `localhost`).
  Local-only mode's downloaded-weight verification does not apply on this route.
- **Plain `http://` only for this machine or a `.local` name**; every other host needs `https://`.
  URLs carrying a user name, password, query or fragment are refused.
- **Credentials.** The optional key is stored in the Keychain (account `openai-compatible`), sent only
  to the server it was saved for, removed when you change servers, and masked if a server echoes it in
  an error. The Ollama key is never sent there.
- **Strict streams.** Requests stream server-sent events; an answer counts only with `[DONE]` or a
  `finish_reason`. Truncated streams, `error` objects, empty or reasoning-only answers, non-event-stream
  pages (captive portals), oversized responses and timeouts fail with a clear message and keep the
  previous output. A `finish_reason` of `length` keeps the partial answer and marks it as cut off at
  the model's output limit. Redirects are never followed.
- **Never picks a model for you.** On this route the pane pickers list the server's models but no
  pane is assigned one until you choose it, and these choices are stored apart from your Ollama picks.
- **Auto needs the JSON contract.** Auto and Quick use the same strict JSON evaluator as on Ollama,
  with best-effort reasoning-off hints (`reasoning_effort: "none"`, `enable_thinking: false`) instead
  of Ollama's `think: false`; a model that cannot hold it shows "did not return a usable Quick Summary update" and keeps the
  previous recap. On iPhone, **Test this model** on the Quick role checks this up front and pauses
  Auto with the reason if it fails.
- `make e2e` runs the provider contract against a real server: Ollama's own `/v1` API.

## Contributing

PRs welcome. Before pushing, run the CI-equivalent gate:

```bash
make pre-push
```

**Releasing.** Maintainers build the signed + notarized `.dmg` locally with `make release` —
see [`docs/RELEASING.md`](docs/RELEASING.md) for prerequisites, the env vars it reads, and the
publish step.

## License

[MIT](LICENSE) © 2026 Tom Wu
