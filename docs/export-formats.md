# Export formats

ListenToMe exports a conversation in five formats, all built on the device by
`SessionExporter` in `ListenToMeCore` ([#130](https://github.com/tomqwu/ListenToMe/issues/130)):

| Format | Extension | What it holds |
| --- | --- | --- |
| Markdown | `.md` | Title, recording date and language, context notes, the transcript with `[mm:ss]` timestamps, speech corrections, summaries and attachment names |
| Plain text | `.txt` | The same content without Markdown: one `[mm:ss] Speaker: text` line per transcript line |
| Subtitles (SRT) | `.srt` | Numbered cues with `HH:MM:SS,mmm` times |
| Subtitles (WebVTT) | `.vtt` | `WEBVTT` cues with `HH:MM:SS.mmm` times and `<v Speaker>` voice tags |
| JSON | `.json` | A versioned document for scripts and other tools (schema below) |

Where to find them:

- **macOS** — **Export** in the top bar (Markdown, plain text, SRT, WebVTT, JSON, plus Recap and PDF
  and Copy conversation), and the same **Export** menu in a History conversation's detail sheet.
  ⌘E exports Markdown.
- **iPhone** — **More → Export as** for the open conversation, and **Export as** in a History row's
  context menu (touch and hold). Each item opens the share sheet with a file, so **Save to Files**,
  Mail or AirDrop receive a real `.srt`/`.json`/… file.

## File names

Files are named after the conversation and its date: `Weekly sync 2026-10-23 1435.srt`. Characters
that file systems reject (`/ \ : * ? " < > |`, line breaks, control characters) become spaces, leading
dots and dashes are dropped, and long titles are cut at 60 characters. A title still at its generated
default ("Conversation — …", "New conversation") becomes `Conversation`. The recap is
`… 2026-10-23 1435 recap.md`.

## Timestamps: which recordings have them

Only some transcription engines report where each line sits in the recording, and no time is ever
estimated for the others.

| Source | Timestamps |
| --- | --- |
| iPhone recording (live) | Yes — the recognizer's audio range, cumulative across resumed recordings |
| Apple Watch recording, transcribed on the iPhone | Yes — relative to the watch recording |
| macOS WhisperKit | Yes |
| macOS SpeechAnalyzer / SpeechRecognizer (default engines) | No, until [#68](https://github.com/tomqwu/ListenToMe/issues/68) |
| Imported notes, typed text, records saved before segments were kept | No |

A line without a time is exported without a `[mm:ss]` prefix (Markdown, plain text) and without
`start`/`end` (JSON), and it is left out of subtitles. A conversation with no timed lines does not
offer SRT or WebVTT at all; `SessionExporter.formats(for:)` decides this for both apps.

## Subtitle cues

- Only timed lines with words become cues, in recording order.
- Consecutive lines by the same speaker less than a second apart are merged into one cue while it stays
  within 84 characters and 7 seconds.
- A longer line is split at word boundaries (at characters for Chinese, Japanese, Thai, Lao, Khmer and
  Burmese) into cues of similar length, sharing the line's time in proportion to their length.
- Each cue is at most two balanced lines of 42 characters (16 for unspaced scripts).
- A line its engine timed with no length is shown for one second, or until the next cue.
- Times always carry hours, so recordings over an hour (or over 99 minutes) stay valid.
- Speaker names appear only when more than one person speaks: `Alice: …` in SRT, `<v Alice>…` in
  WebVTT. WebVTT text escapes `&`, `<` and `>`; SRT text never contains `-->`.

## Language

Every conversation keeps the transcription language it was actually recorded in
([#206](https://github.com/tomqwu/ListenToMe/issues/206)): the fixed language, or the one Automatic
switched to, including a switch part-way through a recording, and Undo. It is stored on the saved
record as `language` (the latest) and `languages` (all, in order of first use), as BCP-47 tags such as
`fr-FR`. Exports and Save to folder notes use it, so editing a conversation after changing the language
setting never rewrites it. A conversation that was never transcribed, or that was saved before this
was kept, has no language: the Markdown and plain-text header leave it out and JSON says `null`.
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
| `language` | string or `null` | BCP-47 tag of the latest recording's language |
| `languages` | array of strings | Every language it was transcribed in, in order of first use |
| `hasTimestamps` | boolean | Whether any segment carries `start`/`end` |
| `duration` | number or `null` | Seconds from the first timed line's start to the last one's end |
| `speakers` | array | `{ "name", "source", "id"? }` in order of first speech; `source` is `"you"` (microphone) or `"others"` (system audio); `id` is the speaker-identification ID when there is one |
| `summary`, `quickSummary`, `deepSummary`, `notes` | string | Empty when absent |
| `segments` | array | `{ "speaker", "source", "text", "start"?, "end"?, "speakerID"?, "originalText"? }`; times in seconds (millisecond precision), present only for timed lines; `originalText` is the recognizer's wording before an opt-in speech correction |
| `transcript` | string | Only for a conversation saved before segments were kept |
| `attachments` | array | `{ "name" }` — names only, never the files |

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
destination, and the previous export's file is removed at the next export; where it goes after that is
up to the destination you chose.
