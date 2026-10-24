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
   but the rail shows **PREP** with a spinner (not **REC**), the header says **Preparing…**, and the
   mic/system channels stay at "starting…" until the model is ready — the speech model is now
   downloaded *before* capture starts, so nothing is captured (and nothing is lost) during the
   download. Once the channels report they are running, speak a sentence
   → it appears under **Transcript** labeled **You** (blue), including the very first words.
5. Play speech from another app (a video/meeting) → it appears labeled **Others** (green).
6. In the **Quick** pane, click **What should I answer?** → a streamed suggestion appears (a
   "💭 Thinking…" state shows first for thinking models).
7. With **Proactive** on (the checkbox in the **Quick** pane header, on by default), have the other
   audio ask a question → a Quick answer appears automatically ~1-2s after the utterance ends,
   without pressing anything. Ask a *second* question within ~8s → it must **not** fire again
   (debounce); after that window a further question does. Ask a question yourself (mic) → nothing
   fires. Turn **Proactive** off → a question from the other audio produces no answer, and the
   choice survives quitting and relaunching the app. Press **⌘⇧Space** while another app is focused
   → a Quick suggestion is generated.
8. **Summary** pane: after some conversation, confirm a rolling summary + open questions/action
   items appear (auto-refreshes; the pane's Refresh button forces it). Immediately after a
   successful refresh the **Refresh** button must be **disabled** ("Everything said so far is
   already summarized.") and must re-enable as soon as new speech is transcribed.
8a. **Failure keeps the pane** (issue #137): with a summary on screen, quit the Ollama server (or
   pick a model that is not pulled) and press **Refresh** after new speech → the summary text must
   remain visible and the error must appear as an orange banner under the pane header, not replace
   the text. Restart Ollama and refresh again → the banner disappears.
8b. **Thinking status**: assign a reasoning model (e.g. `qwen3` or `deepseek-r1`) to **Deep** and
   click **Deep answer** → the header shows **Thinking…** during the reasoning phase and the
   reasoning text never appears in the answer body.
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
12b. **Grounding with Auto off** (issue #114): leave **Auto** off and do not press **Refresh**. Open a
    long saved conversation (40+ minutes) or record one, with a decision stated in the first two
    minutes. Press **⌘⇧Space** → the Quick pane shows "Using the opening ~N min and the last ~M min of
    the conversation (~K min in between left out)." under its header, and the answer can use the
    early decision. Press **Refresh**, wait for the Listener (and any follow-up batches), ask again →
    the line reads "Using the Listener summary of the first ~N min and everything said since (~M min)."
    (or, for a meeting that is still too long, "…of the first ~N min, the ~H min after it and the last
    ~M min…"). Keep talking for 20+ minutes without Refresh and ask again → the line must name the
    summary's real span and a gap ("in between left out"), never claim the summary covers the new
    speech. A short conversation shows no line. Turn **Auto** on and let the recap replace a manual
    Quick answer (or click **Show recap**) → the answer's line disappears with it.
12b′. **Enormous last line** (issue #114, Apple Intelligence): import or paste a transcript whose
    last line is several thousand words long and ask Deep → it answers (never "This request is too
    long for Apple Intelligence's on-device context window"), and the line ends "The latest line
    was shortened."
12c. **Output limit** (issue #215): give **Deep** a cloud or OpenAI-compatible model with a small
    output limit (an LM Studio server with max tokens 64, or Ollama with `num_predict` 64 in a
    Modelfile) and ask **Deep answer** → the partial answer stays and the pane shows "The answer was
    cut off at the model's output limit." with no error banner. Ask again with a normal limit → the
    line disappears.
13. **History while recording** (issue #116): with a few saved conversations and recording active,
    open **History**, leave it open for ~30 seconds and type into **Context notes** — the list stays
    responsive and typing does not lag; the archive is read once when the sheet opens, not once a
    second.

### First-run model download is cancellable (issue #99)

Only reproducible on a Mac where the chosen engine's model is not yet installed (SpeechAnalyzer: a
fresh language in Settings; WhisperKit: a fresh profile).

1. Press **Listen** and wait for the rail to show **PREP** and the header **"Transcription:
   preparing on-device speech model…"**.
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
11. Multi-party stability: in a 20+ minute recording with three or more voices, let each person stay
    quiet for several minutes at a time. The Speakers list must keep roughly one row per real
    participant — it must not balloon with new Speaker N rows each pass — and a renamed speaker must
    keep their name, including on lines after a long silence (voice matching, issue #171). Note any
    extra rows and whether the voices involved sound alike.
12. With SpeechRecognizer (legacy) selected, speak in short bursts with ~1 s pauses for a minute.
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
   again: the notice must change to the speech-only wording ("some older speech was left out; each
   pane says which part it read."), and the Deep pane must show its own "Using the …" line (#114).
   With a very long **Context notes**
   entry, the notice must instead name "your notes and the running summary". In no case may the pane
   show "This request is too long for Apple Intelligence's on-device context window." — that string
   is the provider's last-resort guard and means the prompt reached it unbounded; report it as a bug.
5. Switch back to **Local only** or **Cloud** with the same conversation (Settings → save): the trim
   notice disappears immediately, and the next answer reads up to 16,000 (Quick) or 32,000 (Deep)
   characters of transcript, or all of it for Recap and Action items.
7. **iPhone Quick and Deep on a long conversation (#114, #215).** On iPhone with Apple Intelligence,
   open a conversation longer than about ten minutes with no Summary. **Generate Quick Summary** and
   **Generate Deep Summary** must both answer (they used to say "exceeds the selected provider's
   summary limit") and show "Using the opening ~N min and the last ~M min of the conversation (~K min
   in between left out)." above the text. **Summary** itself still says the conversation exceeds the
   limit. Record a few minutes, generate **Summary**, keep recording well past the window, then
   generate Deep → "Using your Summary of the first ~N min, the ~H min after it and the last ~M min of
   the conversation (~K min in between left out)." A conversation reopened from History has a Summary
   of unknown coverage: Deep keeps the opening and adds "An earlier summary is included too." With
   Auto on, a recap that rewrites the Quick Summary removes the previous answer's line. With a cloud
   model whose output limit is tiny, Deep keeps its partial text and
   shows "The answer was cut off at the model's output limit."
6. **Many short lines.** Still on Apple Intelligence, have a long back-and-forth of short utterances
   with named speakers (rename both speakers to long names). Ask Deep for **Action items**: the
   speaker labels count against the window too, so this must answer rather than fail.

## OpenAI-compatible server (#52)

Use LM Studio (or `ollama serve`, whose OpenAI API is `http://localhost:11434/v1`).

1. **Explicit and labelled.** In Settings choose **OpenAI-compatible**. With the URL empty, Save and
   confirm the panes say "Set your OpenAI-compatible server URL in Settings" and nothing is sent.
   Enter `http://localhost:1234` and Save: the footer reads "OpenAI-compatible — your server at
   localhost:1234", never "local" or "on-device", and **More → Refresh models** lists the server's models.
   The panes stay unset ("Choose a model for each pane…") until you pick each one in the status rail;
   switching back to **Local only** restores your earlier Ollama picks.
2. **Plain http is refused off the local link.** Enter `http://192.168.1.20:1234/v1` and Save: Settings
   shows the "Plain http:// is only allowed…" error and nothing is applied.
3. **Answers and failures.** Ask Quick, Deep and Summary for answers; they stream. Stop the server and
   ask again: the pane keeps its text and the banner says "Could not reach localhost:1234".
4. **Key binding.** Save a key, then change the URL to another host: the key is removed (re-open
   Settings and the key field is empty).
5. **Auto.** Turn on Auto with a small model and speak: either the recap updates or the Quick pane says
   "did not return a usable Quick Summary update" — never a silent stall.

## Cloud AI services (#214)

Needs a real API key for each service you test; the maintainer supplies keys at test time. Never commit
or paste a key into an issue or log.

1. **Opt-in, nothing chosen.** On a fresh install the macOS mode is still Local only and the iPhone
   provider Apple Intelligence. In Settings choose **Cloud AI service** without picking a service and
   Save: the save is refused with "Choose a cloud AI service…" and nothing is applied.
2. **Labelled.** Pick **Anthropic Claude**: Settings shows "Sends your transcript to Anthropic", the
   host `api.anthropic.com`, **Get a key from Anthropic** (opens the key page) and the privacy policy
   link, plus the note that Anthropic may re-run a declined request on another Claude model.
3. **Key and models.** Paste the key, **Check key** (macOS) or **Refresh models** (iPhone): the vendor's
   models are listed, Claude Opus 5.5 is marked as the suggestion, and no pane or role has a model until
   you pick one. Pick a model for every pane or role.
4. **A Summary per service.** For each of OpenAI, Anthropic Claude, Google Gemini, DeepSeek, OpenRouter,
   Groq, Mistral and xAI Grok: generate a Summary from a short recorded conversation and confirm it
   streams and completes. On iPhone, **Test this model** on the Quick role passes or pauses Auto with a
   reason (Claude should always pass: its evaluator uses structured output). The same transport check
   runs headless with `LTM_CLOUD_PRESET=<id> LTM_CLOUD_MODEL=<model> LTM_CLOUD_KEY=<key> swift test
   --filter CloudAIPresetLiveTests` (it is skipped without those variables).
5. **Per-vendor keys.** Switch from Claude to OpenAI and back: each service keeps its own key and
   model choices. A wrong key shows "rejected the API key" and never echoes the key.
6. **Back to the default.** Choose Local only (macOS) or Apple Intelligence (iPhone): no request goes to
   the cloud service afterwards.

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

## macOS lifecycle and UX papercuts (#136, #147)

1. **Engine label follows the live run.** Start listening with **SpeechAnalyzer**, then open
   **Settings**, switch the transcription engine to **WhisperKit** and Save. The rail's **Engine**
   line must still read `SpeechAnalyzer · WhisperKit next start` — never plain "WhisperKit" — and
   must read plain `WhisperKit` after Stop + Start.
2. **Preparing gates automation.** With a conversation already transcribed and **Auto summaries**
   on, press Start on a Mac that still has to download the speech model. While the rail shows
   **PREP**: the transcript pane's status chip reads **preparing** (never **live**), the
   Quick/Summary/Deep panes generate nothing, no speaker analysis starts, and the automation status
   reads "Auto paused · Preparing on-device speech model…". All of it resumes once capture starts.
3. **Closed-window menu items.** Close the main window (⌘W) while the app stays in the Dock. In the
   menu bar, **Export conversation…**, **Conversation history…** and **Settings…** must all be
   greyed out, and ⌘E / ⌘F / ⌘, must do nothing visible rather than appear to work. Reopen the
   window; they become enabled again.
4. **Keyboard shortcuts.** With the window key: ⌘⇧L starts listening (menu item reads **Stop
   listening** while running, and ⌘⇧L stops), ⌘⇧D fills **Deep**, ⌘⇧R produces a Quick recap, ⌘⇧U
   refreshes **Summary**. Confirm the footer hints match the **Session** menu exactly. Then drag the
   window down to its minimum width (1100 pt — it will not go narrower): all nine footer hints and
   the AI-mode label on the right must still be readable, none clipped or overlapping.
5. **Quit & Reopen never doubles the app.** Turn autosaving off, record a few lines, open **More →
   Permissions… → Quit & Reopen**, and press **Cancel** in the "Save this conversation before
   closing?" alert. Nothing must relaunch: check that exactly one ListenToMe is running (Activity
   Monitor / `pgrep -fl ListenToMe`). Repeat and choose **Close without saving** — now exactly one
   *new* instance starts and the old one exits.
6. **Unsupported language is announced.** Set the transcription language to one your Mac has no
   speech model for (or set the system language to e.g. `pt-BR` and leave "Auto"), then Start. The
   status line must name the requested language and the one actually used, e.g.
   "pt-BR isn't supported on this Mac — transcribing in en-US".
   **Every supported language is offered (#172).** Open the rail's language picker: below **Auto
   (system)** it shows **Installed** and **Downloadable** sections, common languages (English,
   Mandarin, Cantonese, Japanese…) first, and languages the old curated list lacked, such as
   Portuguese (Brazil) or Italian. Pick a downloadable one and Start: the model downloads, live text
   arrives in that language, and after relaunch the language appears under **Installed**.
7. **Calendar title and denial.** With a meeting in progress in Calendar, click **Load from
   Calendar**: notes fill *and* the conversation title becomes the event's title. Rename the title
   by hand and click it again — your title must survive. Then deny Calendar access for this app in
   System Settings and click it again: the banner must say access is missing (not "no meeting") and
   offer **Open Calendar privacy settings**. Press its **✕** — the banner disappears.
8. **Reduce Motion.** Turn on System Settings → Accessibility → Display → **Reduce Motion** and
   start listening: the recording dot stays solid red instead of pulsing. With VoiceOver on, the
   pane **Copy** button announces "Copy <pane> text", not just "button".

## iPhone automatic transcription language (#197)

Physical iPhone or iPad only: the simulator has no live speech engine. The full check is step 11 of
the physical-device list in [IOS.md](IOS.md#app-store-privacy-and-support-pages) ("Before marking
iOS production-ready…"); this is the short pass.

1. **Existing choice is kept.** Update a build where **Settings → Transcription → Language** was set
   to a fixed language: it must still show that language, not Automatic. A fresh install shows
   **Automatic (default)**.
2. **First download, then offline.** With the device language English and Automatic selected, start
   a recording and speak Mandarin. The status line shows the one-time language-model download
   (about 75 MB, from huggingface.co), then within about 30 seconds "Detected Chinese · switched",
   and the early English nonsense is replaced by Chinese text while recording continues. Repeat in
   Airplane mode: the model loads from the device and the switch still happens.
3. **No false switch.** Speak English for a minute with Automatic on: nothing switches, and **Quick
   Summary → Status details** shows "Language check: en … → kept (same language)".
4. **Undo.** After a switch, tap **Undo**: transcription returns to the starting language, the
   transcript is re-transcribed in it, and the picker now shows that language fixed. Repeat with
   Undo tapped right after Stop: once Stop finishes, the earlier lines come back with no line twice.
   After a switch, take a call: the resumed recording stays in the switched language with Undo.
5. **Unavailable model.** On a fresh install in Airplane mode, record with Automatic: recording
   continues in the device language and the status line says "Language detection paused".
6. **Every supported language is offered (#172).** **Settings → Transcription → Language** lists
   **Automatic (default)** first, then **System**, then **Installed** and **Downloadable** sections
   with the common languages first and languages such as Portuguese (Brazil), Italian or Hindi
   further down. Pick a downloadable one, record: its model downloads and the transcript is in that
   language; reopen Settings and it is listed under **Installed**.

## iPhone language re-check mid-recording (#199)

Physical iPhone or iPad only. The full check is step 12 of the physical-device list in
[IOS.md](IOS.md#app-store-privacy-and-support-pages).

1. **Change part-way.** With Automatic selected and the device in English, speak English for two
   minutes, then Mandarin for two minutes in the same recording. Within about two minutes of the
   change, the notice reads "Detected Chinese from m:ss · switched" with a time near the change.
   The English lines before it are unchanged, and the Mandarin part is in Chinese with the same
   times as before.
2. **Short phrase.** Inside the Mandarin part, say one short English sentence: nothing switches back.
3. **Undo the latest switch.** Tap **Undo**: only the Mandarin span returns to English, and the
   picker shows English fixed. In a recording that switched twice, Undo returns to the language
   from before the second switch and leaves the first switch's lines alone.
4. **Energy.** Turn on Low Power Mode while recording: **Quick Summary → Status details** shows
   "Language re-check: … skipped (Low Power Mode)". Stay silent for a minute: it shows "skipped
   (too little speech)". Record 20+ minutes in one language: memory stays flat in Xcode's gauge.
5. **Mixed sentences are a known limit.** A sentence mixing English words into Mandarin stays in the
   recording's current language (#205).

## Save to folder — Markdown vault (#53)

iPhone (simulator is enough for 1–5; 6 needs a physical device signed in to iCloud):

1. **Off by default.** Fresh install: **More → Settings → Save to folder** is off and no note is written.
2. **Choose a folder.** Turn it on: the Files picker opens. Pick a folder in On My iPhone. Settings shows
   the folder name and "Saving each conversation to … when you stop or save."
3. **Written at Stop, not while recording.** Record a few lines: Files shows no new note while
   recording. Tap Stop: one `… ListenToMe <key>.md` note appears with front matter, Summary/Notes and a
   `[mm:ss]`-timestamped transcript.
4. **No duplicates.** Rename the conversation and generate a Summary: the same note updates; no second
   file appears. Force-quit and reopen, edit notes: still one note. Unrelated files in the folder are
   unchanged.
5. **Visible failure and Retry.** Delete the chosen folder in Files, then tap Save: an orange "Save to
   folder" line appears under the title and in Settings ("can't be found … Choose the folder again").
   Choose a folder again: the waiting note is written.
6. **iCloud Drive / Obsidian.** Choose a folder inside the Obsidian vault in iCloud Drive. Stop a
   recording, then open Obsidian on a Mac or iPhone: the note appears with its properties (date,
   duration, language, speakers, tags) and renders the transcript list.

Mac: in **Settings**, turn on "Save each conversation to a folder as Markdown" and choose a folder.
Listen, then Stop: the note appears once the checkpoint is complete, and updates as Listener/Quick/Deep
change. Move the folder to the Trash: an orange note with **Retry folder save** appears beside the
saved time. Stop a recording and quit with ⌘Q at once: the note is in the folder. With the folder
in the Trash, stop a recording and quit; put the folder back, relaunch: the waiting note is written.

**Own language (#206).** iPhone: with Automatic, record in a language other than the device's until it
switches, Stop, then set Settings → Language to another fixed language and edit the conversation's
notes: the note's `language:` is still the switched-to language. A conversation that switched part-way
also lists `languages:` with both. Mac: record in French, Stop, change the language to English, rename
the conversation: the note keeps `language: "fr-FR"`.

## Export formats and file names (#130)

Mac:

1. With **WhisperKit** selected, Listen for a minute with two people talking, then Stop. **Export**
   lists Markdown, Plain text, Subtitles (SRT), Subtitles (WebVTT), JSON, Recap, PDF and Copy. The
   save panel proposes `<title> <yyyy-MM-dd HHmm>.srt`, not a clock-time name. The `.srt` opens in
   QuickTime/IINA beside a recording of the call with readable two-line cues; the `.vtt` validates
   (for example in a browser `<track>`); Markdown and text lines start with `[mm:ss]`.
2. With **SpeechAnalyzer** (the default), record and open **Export**: the subtitle items are disabled
   with a note saying why, and Markdown/text have no `[mm:ss]` (nothing invented).
3. **History** → open a conversation → **Export**: the same formats plus Recap and PDF, named after
   that conversation, not "Conversation.md".
4. Open the `.json` in a JSON viewer: `schema` `listentome.conversation`, `version` 1, `language`,
   `speakers` and `segments` as in [export-formats.md](export-formats.md).

iPhone (simulator is enough):

1. Record a few lines, Stop, then **More → Export as**: five formats. Pick **Subtitles (SRT)** →
   **Save to Files**: the file is named after the title and date and its cues match the transcript
   times, including after a resumed recording (times keep counting up).
2. **History** → touch and hold a conversation → **Export as** → **JSON** → Save to Files: valid
   JSON with the conversation's language. An imported-notes conversation offers no subtitles.
3. An Apple Watch conversation's subtitles start near 00:00:00 and follow the watch recording.

## iPhone Delete all conversations (#220)

Simulator or device.

1. **Unavailable while busy.** Start listening, open History: **Delete all conversations…** is
   disabled with "Stop recording or wait for the AI response to delete conversations." Stop.
2. **Confirmation.** With three saved conversations (one with an attachment), tap the button at the
   bottom of History. The alert reads "Delete all 3 conversations?" and says it cannot be undone.
   With Save to folder on, it also says notes already saved to the folder stay. Cancel: nothing
   changes. Type a search: the button is hidden.
3. **Everything goes.** Confirm: History shows "No saved conversations", the title reads "New
   conversation" and the status line says "3 conversations deleted from this device." Force-quit
   and reopen: History is still empty. Files already written by Save to folder are still there.
4. **Settings.** Save a conversation, then use **Settings → Privacy → Delete all conversations…**:
   same alert and result.
5. **Apple Watch.** With a watch conversation in History and another watch recording still in
   "Waiting from Apple Watch", delete all: the watch conversation and its audio are gone, and the
   waiting recording stays and becomes a conversation later.
