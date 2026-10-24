# Export formats

ListenToMe exports a conversation in five formats, all built on the device by
`SessionExporter` in `ListenToMeCore` ([#130](https://github.com/tomqwu/ListenToMe/issues/130)):

| Format | Extension | What it holds |
| --- | --- | --- |
| Markdown | `.md` | Title, recording date and language, context notes, the transcript with `[mm:ss]` timestamps, speech corrections, summaries (Listener/Summary, Quick and Deep — on iPhone a conversation's read-only **Earlier deep analysis**, #235), saved selection summaries (iPhone, #234) and attachment names |
| Plain text | `.txt` | The same content without Markdown: one `[mm:ss] Speaker: text` line per transcript line |
| Subtitles (SRT) | `.srt` | Numbered cues with `HH:MM:SS,mmm` times |
| Subtitles (WebVTT) | `.vtt` | `WEBVTT` cues with `HH:MM:SS.mmm` times and `<v Speaker>` voice tags |
| JSON | `.json` | A versioned document for scripts and other tools (schema below) |

Where to find them:

- **macOS** (on `main`, unreleased since macOS 1.4.4) — **Export** in the top bar (Markdown, plain
  text, SRT, WebVTT, JSON, plus Recap and PDF and Copy conversation), and the same **Export** menu in a
  History conversation's detail sheet. ⌘E exports Markdown.
- **iPhone and iPad** (since iOS 1.15.0 (32)) — **More → Export as** for the open conversation, and
  **Export as** in a History row's context menu (touch and hold). Each item opens the share sheet
  with a file, so **Save to Files**, Mail or AirDrop receive a real `.srt`/`.json`/… file.

## File names

Files are named after the conversation and its date: `Weekly sync 2026-10-23 1435.srt`. Characters
that file systems reject (`/ \ : * ? " < > |`, line breaks, control characters, bidirectional
overrides) become spaces, leading dots and dashes are dropped, and long titles are cut at 60 characters
and, on whole characters, so the whole name stays within 200 UTF-8 bytes (file systems allow 255; a
title in Chinese or emoji reaches that well before 60 characters). A title still at its generated
default ("Conversation — …", "New conversation") becomes `Conversation`. The recap is
`… 2026-10-23 1435 recap.md`.

## Timestamps: which recordings have them

Only some transcription engines report where each line sits in the recording, and no time is ever
estimated for the others.

| Source | Timestamps |
| --- | --- |
| iPhone recording (live) | Yes — the recognizer's audio range, cumulative across resumed recordings |
| Apple Watch recording, transcribed on the iPhone (not shipped yet, [#181](https://github.com/tomqwu/ListenToMe/issues/181)) | Yes — relative to the watch recording |
| macOS WhisperKit | Yes — each Listen (and a language change that restarts capture) continues after the conversation's last timed line |
| macOS SpeechAnalyzer / SpeechRecognizer (default engines) | No, until [#68](https://github.com/tomqwu/ListenToMe/issues/68) |
| Imported notes, typed text, records saved before segments were kept | No |

A line without a time is exported without a `[mm:ss]` prefix (Markdown, plain text) and without
`start`/`end` (JSON), and it is left out of subtitles. A conversation with no timed lines does not
offer SRT or WebVTT at all; `SessionExporter.formats(for:)` decides this for both apps.

Each recording's engine times start at zero. iOS has always moved a resumed recording past the lines
already there; on the Mac, `MeetingSession.recordingOffset` now does the same for every capture,
for timed lines only. Mac conversations saved before that restart at zero for every Listen, so the
exporter splits the lines into recordings wherever a line starts more than 10 seconds before the
recording so far has ended (`TranscriptTimestamp.recordings`): subtitles never merge or interleave
across recordings, and `duration` adds up the recordings instead of reporting the longest.

## Subtitle cues

- Only timed lines with words become cues, recording by recording, in time order within each.
- Consecutive lines by the same speaker less than a second apart are merged into one cue while it stays
  within 84 characters and 7 seconds; nothing is merged across recordings.
- A longer line is split at word boundaries (at characters for Chinese, Japanese, Thai, Lao, Khmer and
  Burmese) into cues of similar length, sharing the line's time in proportion to their length.
- Each cue is at most two balanced lines of 42 characters (16 for unspaced scripts). In SRT the
  `Speaker: ` prefix counts toward that limit.
- A line its engine timed with no length (start = end) is given about its reading time at 15
  characters a second (at least one second), never past the next line's start, and its pieces follow one
  another instead of stacking at one instant.
- Times always carry hours, so recordings over an hour (or over 99 minutes) stay valid.
- Speaker names appear only when more than one person speaks: `Alice: …` in SRT, `<v Alice>…` in
  WebVTT. WebVTT text escapes `&`, `<` and `>`. SubRip has no escapes and players read `<i>`-style tags
  and `&…;` entities, so SRT text shows `<`, `>` and `&` as `‹`, `›` and `＆`, which also means no cue
  text can contain `-->`.

## Language

Every conversation keeps the transcription language it was actually recorded in
([#206](https://github.com/tomqwu/ListenToMe/issues/206)): the fixed language, or the one Automatic
switched to, including a switch part-way through a recording, and Undo. It is stored on the saved
record as `language` (the current one: the latest recording's, switch's or Undo's) and `languages`
(every language its lines are in, in order of first use), as BCP-47 tags such as `fr-FR`. On iPhone each
line also keeps the language it was recognized in, so `languages` follows the lines: a first check that
transcribes the whole recording again in another language drops the starting one, and an Undo — which
brings back only the lines before the switch — keeps the switched-to language listed while speech after
the switch is still in it. Lines saved before languages were kept per line cannot say, so nothing
already listed is dropped for them. Exports and Save to folder notes use these fields, so editing a
conversation after changing the language setting never rewrites them. A conversation that was never
transcribed, or that was saved before this was kept, has no language: the Markdown and plain-text header
leave it out and JSON says `null`.
macOS WhisperKit in Automatic mode detects the language as it goes and reports none, so nothing is
recorded for it.

## JSON schema, version 1

UTF-8, pretty-printed, keys sorted. `schema` is always `"listentome.conversation"`; `version` changes
only for a change that is not purely additive, so a reader should accept unknown keys.

| Key | Type | Notes |
| --- | --- | --- |
| `schema` | string | `"listentome.conversation"` |
| `version` | integer | `1` |
| `id` | string | The conversation ID |
| `title` | string | |
| `date` | string | ISO 8601 in UTC, e.g. `2026-10-23T14:35:00Z` |
| `language` | string or `null` | BCP-47 tag of the current language (latest recording, switch or Undo) |
| `languages` | array of strings | Every language its lines are in, in order of first use |
| `hasTimestamps` | boolean | Whether any segment carries `start`/`end` |
| `duration` | number or `null` | Recorded seconds: each recording's span from its first timed line's start to its last one's end, added up |
| `speakers` | array | `{ "name", "source", "id"? }` in order of first speech; `source` is `"you"` (microphone) or `"others"` (system audio); `id` is the speaker-identification ID when there is one |
| `summary`, `quickSummary`, `deepSummary`, `notes` | string | Empty when absent. `deepSummary` is the Mac's Deep pane; iPhone has no Deep tab since 1.15.0 (#235), so there it is only an **Earlier deep analysis** saved before then |
| `segments` | array | `{ "speaker", "source", "text", "start"?, "end"?, "speakerID"?, "originalText"?, "language"? }`; times in seconds (millisecond precision) on the conversation's timeline, present only for timed lines; `originalText` is the recognizer's wording before an opt-in speech correction; `language` is the BCP-47 tag the line was recognized in, when the app kept it (iPhone) |
| `transcript` | string | Only for a conversation saved before segments were kept |
| `attachments` | array | `{ "name" }` — names only, never the files |
| `selectionSummaries` | array | Saved summaries of selected lines (iPhone, #234), newest first: `{ "date", "start", "end", "lineCount", "shortened", "text" }`; `date` ISO 8601 in UTC, `start`/`end` in seconds on the conversation's timeline; `[]` when none |

Example (abridged):

```json
{
  "date" : "2026-10-23T14:35:00Z",
  "hasTimestamps" : true,
  "language" : "fr-FR",
  "languages" : [ "en-US", "fr-FR" ],
  "schema" : "listentome.conversation",
  "segments" : [
    { "end" : 5.2, "source" : "others", "speaker" : "Alice", "speakerID" : "spk-1", "start" : 3,
      "text" : "Can we ship Friday?" }
  ],
  "version" : 1
}
```

The exact bytes of every format are pinned by golden files in
[`Tests/ListenToMeCoreTests/Golden/Export/`](../Tests/ListenToMeCoreTests/Golden/Export/).

## Privacy

Exports are built on the device. On macOS the file goes where you save it. On iPhone the file is written
to the app's own temporary folder, with the same data protection as History, only when you pick a share
destination. It is removed at the next export, at the next launch, and when you delete any conversation
or use Delete all conversations; where a copy goes after you share it is up to the destination you chose.
