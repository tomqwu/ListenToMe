# ListenToMe — Manual Smoke Test

> **Note:** `make e2e` already covers the app build, app-bundle path resolution, and a real LLM
> contract test (streaming through `OllamaProvider`). This document covers the audio/transcription
> path that cannot be automated: mic capture, system-audio capture, and live speech-to-text — all
> of which require a GUI session and manual permission grants.

Prereq: Ollama running with at least one chat-capable model installed (local or Ollama-cloud, e.g.
`deepseek-v4-flash:cloud`). The app auto-picks an installed model per pane on first launch.

1. `make run` — the window opens with **four panes**: **Transcript** (left) and **Summary**,
   **Quick**, **Deep** (right). This launches the Debug build, which is a separate app from any
   installed release: it appears as **ListenToMe (Dev)** (bundle id `com.tomwu.ListenToMe.dev`)
   and holds its own permission grants. Grant permissions to that row, not the release's.
2. On first launch, the app shows an **onboarding** sheet, not a Permissions panel. Grant
   Microphone, Speech Recognition, Screen Recording (system audio), and Accessibility (global
   hotkey) in System Settings → Privacy & Security. Reopen the in-app Permissions sheet anytime via
   **More → Permissions…**. Re-click **Listen** after granting if needed.
3. In the **left status rail**, under **Models**, confirm a **model picker** per pane is populated
   with your installed Ollama models (the pane header only shows the current selection as text).
   Set different models per pane if you like (e.g. a fast model for **Quick**, a heavier one for
   **Deep**, `deepseek-v4-flash:cloud` for any). **More → Refresh models** re-scans models.
4. Click **Start listening**. On a Mac that has never used the engine, the button flips to **Stop**
   and the recording indicator appears immediately, but the header shows **"Transcription: preparing
   on-device speech model…"** and the mic/system channels stay at "starting…" until the model is
   ready — the speech model is now downloaded *before* capture starts, so nothing is captured (and
   nothing is lost) during the download. Once the channels report they are running, speak a sentence
   → it appears under **Transcript** labeled **You** (blue), including the very first words.
5. Play speech from another app (a video/meeting) → it appears labeled **Others** (green).
6. In the **Quick** pane, click **What should I answer?** → a streamed suggestion appears (a
   "💭 Thinking…" state shows first for thinking models).
7. With **Proactive** on, have the other audio ask a question → a Quick suggestion appears
   automatically ~1-2s after the utterance ends. Press **⌘⇧Space** while another app is focused →
   a Quick suggestion is generated.
8. **Summary** pane: after some conversation, confirm a rolling summary + open questions/action
   items appear (auto-refreshes; the pane's Refresh button forces it).
9. **Deep** pane: click **Deep answer** → a longer, detailed response streams (using the Deep
   pane's model).
10. Type into **Context notes** (e.g., "I am the backend lead"), then trigger a Quick suggestion →
    the answer reflects the note.
11. Click **Stop** → the red recording indicator disappears and capture halts.
12. In **Settings** (gear), confirm **Transcription engine** = **SpeechAnalyzer**. Verify
    dual-channel: speak (You) while other audio plays (Others) — both should transcribe
    concurrently. Confirm **finalized** lines (not just live/volatile partials) accumulate in the
    Transcript and that proactive suggestions fire on `Others` questions. If finalized lines never
    commit (only volatile text shows), switch the engine to **SpeechRecognizer** and report —
    SpeechAnalyzer's finalization semantics need on-device confirmation. Either way, while a long
    sentence is still volatile (grey/live, not yet committed), press **⌘⇧Space**: the answer must
    address what is being said *right now*, not the previous finalized line (issue #113). The same
    holds for **Clarify**, **Draft reply** and **Deep answer**. The **Summary** pane is deliberately
    different: it reads the volatile hypothesis only once every finalized line has been summarized
    (its record is cumulative and is saved), so a Refresh taken while finalized speech is still
    queued covers that speech only — the hypothesis arrives on a later refresh, and its finalized
    text is summarized afterwards either way.
13. **History while recording** (issue #116): with a few saved conversations and recording active,
    open **History**, leave it open for ~30 seconds and type into **Context notes** — the list stays
    responsive and typing does not lag; the archive is read once when the sheet opens, not once a
    second.

### First-run model download is cancellable (issue #99)

Only reproducible on a Mac where the chosen engine's model is not yet installed (SpeechAnalyzer: a
fresh language in Settings; WhisperKit: a fresh profile).

1. Press **Listen** and wait for **"Transcription: preparing on-device speech model…"**.
2. While the download is still running, press **Stop**. Teardown must complete within a second or
   two: the header returns to **Transcription: stopped**, and **Listen/Stop**, **New conversation**
   and **More → Import audio file…** are all enabled again (no lingering "Finalizing…").
3. Repeat, and this time close the window with the red button, then try **Cmd-Q**, while the
   download is in flight — both must work immediately instead of being silently refused.
4. Press **Listen** again after the model finishes installing: the pipeline is already warm, so
   capture starts immediately and no "audio dropped during overload/model setup" caption appears.

If dual-channel transcription shows only one speaker (a console error mentioning
`kAFAssistantErrorDomain 1100`), see the README "Known limitations" — the fallback is
single-source for the MVP or the Phase-2 SpeechAnalyzer engine.

## Automatic reviews follow your settings

1. In Settings, set **AI response language** to a language other than the one you will speak, pick a
   use-case preset, and attach a reference file. Turn **Auto** on and Listen.
2. Speak a substantive question. When Summary and Deep update automatically, both must be written in
   the chosen response language and reflect the preset's persona — not flip back to the spoken
   language on the next cycle. The automatic Deep answer must use the attached reference material.
3. With two speakers (or mic plus system audio), state a commitment as one speaker and have the other
   accept it. The automatic Summary must attribute the owner (a diarized name, otherwise You/Others)
   rather than reporting it as unstated.
4. Type a line into Notes that was never spoken. The automatic Summary must not present it as
   something said in the meeting.
5. While an automatic review is running ("Auto · Updating from new context…"), type continuously in
   Notes and keep talking on both channels. The review must stay running and finish; it must not
   flip back to "Queued" or "Waiting", and the Quick status must not stop showing completed reads.
6. With a recap on screen, click **Draft reply** in Quick and keep speaking. The drafted answer must
   stay visible, the Quick status must read "Recap updated · Showing your generated answer", and
   **Show recap** must return to the current automatic recap. The recap must not be written in the
   draft's style, and the next recap must not simply repeat the draft.
7. On a slow local model with a long meeting, an automatic review that exceeds its deadline must say
   it needed more than N seconds on the selected model and must not repeat the identical request;
   manual Generate must still work, and new speech must start a fresh attempt.

## Automatic speakers (1.3.0)

1. Before Listen, choose WhisperKit and enable Automatic speaker identification. For a room sharing
   one microphone, also enable Identify people sharing my microphone.
2. Record alternating voices for at least 30 seconds. Open Speakers / edit names. Confirm source
   labels and talk time, then save a name. Confirm transcript lines use the name after analysis.
3. Keep talking through another automatic pass. Confirm the name remains attached to the same
   voice; introduce a new voice and confirm it gets a distinct label. Expect uncertain splits/merges
   to get new names rather than silently reusing an edited name.
4. Ask for Action items and Deep answer. Confirm names in the transcript reach the prompts. Rename
   a speaker: old Quick/Deep answers clear and the listener refreshes.
5. Stop and allow final analysis to finish. Export Markdown/PDF and inspect saved-session search:
   named transcript lines should agree, including the final utterance.
6. Restart recording. Older lines must keep their names. New generic labels must distinguish the
   new run. Change language while recording and rapidly Stop/Listen: old analysis must not label
   new audio or leave a stuck spinner.
7. With SpeechAnalyzer selected, check the speaker sheet explains that only voice breakdown is
   available. With identification disabled, capture must not accumulate speaker-analysis audio.
8. Try overlapping voices and document recognition errors; do not infer accuracy from unit tests.
9. Run a long session (10+ minutes) with identification on and watch memory in Activity Monitor:
   it must not step up by hundreds of MB on each pass, and each pass should finish in about the same
   time as the first rather than getting slower as the meeting grows. Talk-time totals must keep
   covering the whole run, not just the last window.
10. Disconnect from the network before the first-ever pass (so the speaker models cannot download).
    The Speakers rail must show one line saying identification is paused, no further download
    attempts may happen (check the console for repeated attempts every ~20 s), and pressing
    Speakers / edit names after reconnecting must retry and resume periodic passes.
11. With SpeechRecognizer (legacy) selected, speak in short bursts with ~1 s pauses for a minute.
    Every utterance must appear; no utterance may be dropped at a pause boundary, and a partial
    line must never be replaced by stale text from the previous utterance (issue #108).

## Capture recovery and microphone denial

These two paths are AVFoundation/ScreenCaptureKit glue that unit tests cannot reach; the decision
tables behind them are covered by `CaptureRecoveryTests`.

1. **Input-device change (issue #107).** Start listening on the built-in mic and speak so **You**
   lines appear. Connect AirPods (or plug/unplug a USB interface, or dock/undock) mid-run. The
   status line must report **Mic: input changed — resumed** and new speech must keep appearing as
   **You** for the rest of the run — no restart required. Switch back to the built-in mic and
   confirm it recovers again.
2. **Unrecoverable input.** Start listening on a USB interface and unplug it with no other input
   available. The capture line must turn **red with a ⚠️** (`Mic: input changed — mic stopped …
   Stop and restart.`) instead of staying a grey caption while the header still counts *Recording*.
   Reconnect an input, press Stop then Listen, and confirm the red state clears.
3. **Sleep/wake.** Start listening, sleep the Mac (closing the lid) for ~30 seconds, wake it and
   speak. Both channels must resume (or say, in red, that they did not).
4. **System audio stop.** While listening with system audio active, disconnect/reconfigure the
   display (or stop the stream from Screen Recording settings). Expect **System: system audio
   stopped — resumed**; if the restart fails, expect a red **system audio stopped: … Stop and
   restart.** and no silent loss of the **Others** channel.
5. **Microphone denied (issue #110).** Deny microphone access for the app under test
   (`tccutil reset Microphone com.tomwu.ListenToMe.dev`, then decline the prompt — or turn the app
   off in System Settings → Privacy & Security → Microphone) and press **Listen**. The app must
   **not** start: no *Recording* timer, no "Mic: active", and a red banner explaining that
   microphone access is off, with an **Open Settings** button that opens the Microphone pane. Grant
   access, press Listen again, and confirm normal capture resumes.
6. **First-run prompt.** On an app that has never asked (after a `tccutil reset Microphone`),
   pressing Listen must show the system microphone prompt first; allowing it starts capture in the
   same press, declining it shows the same red banner instead of recording silence.

## Provider errors and the Apple Intelligence context window (#118, #119)

1. **Rejected cloud key (#118).** In Settings choose **Cloud** and save a deliberately wrong Ollama
   API key. Ask any pane for an answer. The pane must show `HTTP 401` with "API key rejected — check
   the Ollama API key in Settings" and the server's own text in parentheses. It must **not** say
   "Is the server running and the model pulled?". The model dropdown refresh must fail the same way.
2. **Server down (#118).** Choose **Local only**, quit Ollama, and ask for an answer. Here — and only
   here — the message keeps the "Is the server running and the model pulled?" hint.
3. **Bad option (#118).** With a local model that rejects an option, confirm the server's own
   `{"error": …}` text is visible in the pane rather than a canned status line.
4. **Apple Intelligence budget (#119).** On an Apple Intelligence eligible Mac, choose
   **Apple Intelligence** in Settings, attach a large reference folder, and record (or import) at
   least 20 minutes of speech. Ask Deep for a **Recap** and for **Action items**. Both must answer
   instead of failing with a FoundationModels context-window error, and the status line under the
   transcript must name what was dropped — "Trimmed to fit this model's context window — older
   speech and some attached reference material were left out." Detach the reference folder and ask
   again: the notice must change to the speech-only wording. With a very long **Context notes**
   entry, the notice must instead name "your notes and the running summary". In no case may the pane
   show "This request is too long for Apple Intelligence's on-device context window." — that string
   is the provider's last-resort guard and means the prompt reached it unbounded; report it as a bug.
5. Switch back to **Local only** or **Cloud** with the same conversation (Settings → save): the trim
   notice disappears immediately and the full transcript is used again.
6. **Many short lines.** Still on Apple Intelligence, have a long back-and-forth of short utterances
   with named speakers (rename both speakers to long names). Ask Deep for **Action items**: the
   speaker labels count against the window too, so this must answer rather than fail.

## Enabled Screen Recording switch but capture is refused

If the installed production app repeatedly returns ScreenCaptureKit `-3801` despite an enabled
switch, confirm the app is `/Applications/ListenToMe.app` and quit it. A targeted recovery that
worked on September 10, 2026 was:

```bash
tccutil reset ScreenCapture com.tomwu.ListenToMe
```

Then open System Settings → Privacy & Security → Screen & System Audio Recording, use **+**
to select that exact app, authenticate if requested, and relaunch it. This resets only production
Screen Recording authorization; it does not reset microphone, speech, history, or the Dev app.
Verify **System: active** and transcribed playback labeled **OTHERS**. Do not treat microphone
pickup labeled YOU or an enabled toggle alone as proof of system-audio capture.

## Damaged history file and reference-file reporting (#120, #139)

1. **One bad conversation file.** With several saved conversations, quit the app and corrupt one file
   in `~/Library/Application Support/ListenToMe/Conversations` (e.g. `printf '{"id":' > <id>.json`).
   Reopen **History (⌘F)**: every other conversation must still be listed, with a one-line note that
   one unreadable file was set aside. Confirm the file was renamed to `<id>.json.corrupt-<timestamp>`
   and its bytes are intact — nothing is deleted. Reopen History again: the note is gone.
2. **Bad legacy file.** Write garbage into `~/Library/Application Support/ListenToMe/sessions.json`,
   remove `Conversations/legacy-migrated`, and relaunch. Saving, per-second autosave checkpoints and
   **Clear history** must all keep working; the note names the legacy file, which is set aside as
   `sessions.json.corrupt-<timestamp>` rather than deleted.
3. **RTF and non-UTF-8 references.** Attach a TextEdit-exported `agenda.rtf` and a Windows-1252
   `minutes.txt`. Ask Deep a question answerable only from them: the answer must use their text, and
   the prompt must not contain `\rtf1` control words. Attach a binary file renamed to `.txt` (or an
   oversized file): the attachment row must show "Not included" with the reason.
4. **Search normalization.** Save a conversation containing "café", "Zürich" and full-width "ＡＩ".
   In History search, `cafe`, `zurich` and `ai` must each find it, a query pasted with a tab between
   two words must match, and searching `you` must not return every conversation.
