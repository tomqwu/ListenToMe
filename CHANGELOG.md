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

## iOS 1.10.5 (27) — 2026-09-15

- Settings → Privacy links the privacy policy and support pages required for the App Store. (#145)
- History warns about an unreadable saved conversation (quarantined, never deleted) instead of hiding the whole list; search covers notes and matches accents and full-width text. (#120, #139)
- Model prompts fence transcript, notes and reference text as data. (#140)

## macOS (unreleased since 1.4.4)

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
