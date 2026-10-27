# ListenToMe — Manual Smoke Test

## Mac App Store sandbox acceptance

The `AppStore` configuration uses the shared store bundle ID, sandboxed storage and separate OS
permissions. Its generated settings and native temporary-folder scope tests do not replace this
installed-app check. Preserve source/signing evidence and fresh native-resolution Mac screenshots.

1. In the signed sandboxed candidate, verify actual microphone and system-audio transcription
   labeled OTHERS, Stop/cancellation, the explicit local/remote provider, Calendar and file imports/exports.
2. Choose an external vault, save a conversation, quit/relaunch and save it again. No duplicate note
   is created. Delete/revoke the folder and verify reselection guidance.
3. Attach an external file and folder; verify their contents, quit/relaunch and verify both again.
   Delete/revoke one and verify the missing-access warning and same-path reselection. Clear and cancel
   while a read is in progress: no late context returns and saved reference grants are removed.
4. Confirm the existing DMG/Dev installations' bundle identities, data and permissions are intact.
   Do not reset them as a shortcut for the new Store identity.

These checks and Mac screenshot capture are pending while the Mac is locked. No Mac App Store
upload or review submission is established by the preliminary archive.

For changed behavior, start from its [BDD scenario](BDD.md) and record source-matched acceptance
against the stated Given/When/Then outcome. Run `make bdd-check` before the existing local gates;
`make bdd-manual` lists hardware acceptance obligations without marking them passed. The catalog
and automated tests do not replace the installed-app checks below. Reuse standing authorization
for the same Dev environment; involve the maintainer only for new access or OS authentication.

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
   Microphone, Speech Recognition and Screen Recording (system audio) in System Settings →
   Privacy & Security. The global hotkey needs no Accessibility grant. Reopen the in-app Permissions sheet anytime via
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
12a. **Grounding with Auto off** (issue #114): leave **Auto** off and do not press **Refresh**. Open a
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
12b. **Enormous last line** (issue #114, Apple Intelligence): import or paste a transcript whose
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
   and **More → Import audio or video…** are all enabled again (no lingering "Finalizing…").
3. Repeat, and this time close the window with the red button, then try **Cmd-Q**, while the
   download is in flight — both must work immediately instead of being silently refused.
4. Press **Listen** again after the model finishes installing: the pipeline is already warm, so
   capture starts immediately and no "audio dropped during overload/model setup" caption appears.

If dual-channel transcription shows only one speaker (a console error mentioning
`kAFAssistantErrorDomain 1100`), see the README "Known limitations" — the fallback is
single-source for the MVP or the Phase-2 SpeechAnalyzer engine.

## Automatic reviews follow your settings

macOS (iPhone has no response-language, preset or reference settings, and no Deep since 1.15.0, #235;
its Auto Summary is covered under [iPhone: Quick and Summary only](#iphone-quick-and-summary-only-235)):

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

## Suggested prompt chips (#61)

macOS:

1. With **Auto** on, Listen and discuss something with an open question, such as payment terms. After
   the first recap, a **Suggested · from context** row of two or three short prompts must appear above
   the fixed Quick actions, each one line of at most 60 characters, in the conversation's (or the
   chosen response) language, with no JSON, links or placeholders.
2. Keep talking: the chips must not change more often than every 20 seconds. Wait without clicking:
   nothing must be sent (no new Quick answer appears on its own).
3. Click a chip: Quick must answer that literal request, and the chip must leave the row and not come
   back. Right-click another chip → **Ask in Deep**: Deep must answer it.
4. Stop: the chips stay. Change the Quick model, turn **Auto** off, or set AI mode to off: the chips
   disappear. **New** conversation: no chips. With **Auto** off for a whole recording, no chips appear
   and no Quick check runs.

iPhone (phone width and an accessibility text size):

1. With **Auto** on (Ollama, a cloud AI service or an OpenAI-compatible server), record: chips appear
   under Quick Summary, stacked and fully readable without sideways scrolling. Tap one: the app stays
   on **Live** and an Ask card under Quick Summary shows the question in bold and the answer below it;
   Quick Summary and Summary are unchanged (also after reopening the conversation), that chip is gone,
   and **Close** dismisses the card. On a very long conversation with Apple Intelligence, a tap still
   answers (from what fits) and the card says which part was read.
2. With **Apple Intelligence** and Auto off, tap **Generate** on Quick Summary: the bullets must not
   contain a "Suggested:" heading or `>` lines; chips appear only when the on-device model wrote the
   block last. A model that ignores it, or writes it first, gives no chips, every bullet and no error.
   Repeat in a non-English conversation: the heading stays "Suggested:".
3. **New** conversation or a provider/model change clears the chips (change the model while a Quick
   refresh is running: no chips from the old model appear); Stop keeps them.

## iPhone/iPad live speaker regression (#310)

Run the automated real-model and native-control gates in [speaker identification](speaker-identification.md)
first. For physical acceptance, record two people alternating brief replies and longer turns, repeat
after silence, rename one and confirm its later turns keep that name. Stop immediately after the
last words and confirm the tail is labeled. Repeat with one person and ensure pauses do not invent
a second person. Disable identification while a pass is active: recording remains stoppable and
late results add no labels. Start a new recording and confirm it cannot inherit an old person's name.
Record device/OS, source/build, selected language, timings and observed errors; synthetic native Mac
inference and screenshots do not substitute for these physical checks. Do not play test audio before
Listening is confirmed, and do not send private audio off-device.

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

### Speaker edits and summary requests (#167)

With Auto off and a transcript but no Listener summary, edit a speaker name and run another speaker
attribution pass. Neither action should start a Listener model request. Press Refresh explicitly:
the summary request must contain the updated speaker labels. Rename again after that summary has
completed: the existing summary should rebuild from the newly labeled transcript. With AI off,
editing names must not send a replacement request. If a first summary is still streaming when labels
change with Auto off, it must stop and late output must not restore the old names; Refresh stays
available. Preserve the rendered views and sanitized request evidence with the candidate.

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
6. **Many short lines.** Back on Apple Intelligence, have a long back-and-forth of short utterances
   with named speakers (rename both speakers to long names). Ask Deep for **Action items**: the
   speaker labels count against the window too, so this must answer rather than fail.
7. **iPhone Quick on a long conversation (#114, #215).** On iPhone with Apple Intelligence,
   open a conversation longer than about ten minutes with no Summary. **Generate Quick Summary**
   must answer (it used to say "exceeds the selected provider's
   summary limit") and show "Using the opening ~N min and the last ~M min of the conversation (~K min
   in between left out)." above the text. **Summary** itself still says the conversation exceeds the
   limit. Record a few minutes, generate **Summary**, keep recording well past the window, then
   generate Quick → "Using your Summary of the first ~N min, the ~H min after it and the last ~M min of
   the conversation (~K min in between left out)." A conversation reopened from History has a Summary
   of unknown coverage: Quick keeps the opening and adds "An earlier summary is included too." With
   Auto on, a recap that rewrites the Quick Summary removes the previous answer's line. With a cloud
   model whose output limit is tiny, Summary keeps its partial text and
   shows "The answer was cut off at the model's output limit."

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
5. **Semantic search and Ask your history (#57).** Save an English conversation about a budget
   ("we reviewed the quarterly budget and the funding round") and one about travel. A few seconds
   later, search `money` in History: the budget conversation must be listed, marked **Related**, with
   its excerpt. Search `budget`: the excerpt shows the sentence with the word. On local Ollama, ask
   "What did we decide about the budget?": the answer cites `[1]`, and clicking the source opens that
   conversation; the line beside **Ask your history** must say nothing leaves the Mac. Switch to AI
   off: the button is disabled with the reason. Switch to Ollama Cloud: the line must name Ollama
   Cloud as receiving the excerpts. **Clear history**, then confirm
   `~/Library/Application Support/ListenToMe Dev/Search Index/` holds only `index.json` (the
   Release build uses `ListenToMe/Search Index/`).

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

## Domain vocabularies and My terms (#222)

Needs a physical iPhone (the simulator has no speech recognition) and the Mac app; read each script
aloud at a normal pace, once with the vocabulary off and once on, in a new conversation each time.

**Medical script** (≈1 minute): "Sixty-eight-year-old with atrial fibrillation on apixaban five
milligrams BID and metoprolol tartrate twenty-five. Worsening dyspnea, orthopnea, bilateral pitting
edema. Troponin negative times two, BNP eleven hundred, creatinine up to one point six. Get an
echocardiogram; last ejection fraction thirty-five percent. Switch furosemide to forty IV twice daily,
hold lisinopril, recheck a BMP in the morning."

**Cloud/DevOps script** (≈1 minute): "The canary in the EKS cluster failed, so we rolled back with
kubectl and Argo CD. Terraform drift on the VPC peering broke the Istio ingress. PagerDuty paged
on-call at eleven; Grafana showed p99 latency on the gRPC service doubling and Postgres connection
exhaustion. Action items: raise the HikariCP pool, add a Prometheus alert, and write the postmortem in
Confluence."

1. **Off.** Settings → Vocabularies: every preset off, My terms empty. Record both scripts. Note the
   misheard terms (typical: "apixaban", "metoprolol", "BNP", "kubectl", "Argo CD", "Istio",
   "HikariCP"). Expected: after about a minute the banner asks "Sounds like a medical conversation —
   add the Medical vocabulary?" (and for the second script "…a software or cloud conversation…"); it
   does not turn anything on.
2. **Add mid-recording.** In a new conversation, read the medical script and tap **Add** when the
   banner appears: recording keeps running (no gap in the transcript), and terms spoken after Add come
   out spelled as in the preset. Record in the doc which terms improved (on vs off).
3. **On by default.** Turn Medical and Software & Cloud on (Use by default) and add "HikariCP" and a
   colleague's name to My terms. Read both scripts again: compare the misheard terms with step 1.
   Expected: fewer misses; any term still missed goes in My terms.
4. **Language switch keeps the vocabulary.** With Automatic language, start in Chinese and switch to
   English mid-recording: after "Detected English · switched", English domain terms are still favored.
5. **Correction.** With AI speech correction on, say "we deployed on cooper netties": the correction
   reads "Kubernetes" (Software & Cloud on), and Review shows the original.
6. **Summary layout.** Generate Summary for the medical recording: it is organized under History,
   Findings and Plan. Turn off Organize summaries by domain: the next Summary is not.
7. **Banner choices.** Not now hides it for this conversation only; Don't suggest Medical again keeps
   it away in new conversations until Settings → Suggest Medical again; Suggest vocabularies off stops
   all banners.
8. **My terms.** Long-press a transcript line → Add to My terms… → tap a word: it appears in Settings.
   Export as plain text, delete the terms, import the file: they come back.
9. **Mac.** Repeat 2, 3 and 6 with SpeechAnalyzer (right-click a transcript line to add a term; the
   banner sits above the transcript). With the SpeechRecognizer engine, a term added mid-recording
   applies from the next utterance.

Record the off/on examples here when the device pass is run (date, device, script, terms fixed, terms
still missed).

**Controlled SDK results — October 26, #236:** [The evaluation](vocabulary-biasing-evaluation.md)
records file inference on a physical iPhone 12 Pro Max and Mac with these exact scripts synthesized
in two stock voices. The production SpeechTranscriber adapter recovered 36/64 scored targets with
vocabulary off and on; every paired transcript was identical. Explicit SDK diagnostics accepted
100 contextual terms but reproduced that score. Contextual Dictation scored 41/64; custom models
scored 42/64 on iPhone and 41/64 on Mac, with no added target-presence benefit from pronunciations.
These are fixed-waveform measurements, not the live app acceptance above. Expected live spelling
improvements, mid-recording changes and language switches remain unverified; #236 stays open.
No production engine, settings or privacy behavior changed. See the report for exact supplied-term
denominators, ordinary/silence controls, model preparation/cache costs and execution limits.


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
3. An Apple Watch conversation's subtitles start near 00:00:00 and follow the watch recording (watch
   builds only: the watch app is not embedded yet, #181).

## Automatic conversation titles (#221)

iPhone (device for Apple Intelligence, simulator for the keyword path):

1. **Named after Stop.** With **Settings → Conversations → Name conversations automatically** on,
   record about a minute on one topic and tap Stop. Within a few seconds "New conversation" becomes
   a short title of six words or fewer, in the language you spoke, with no quotes or emoji. Stop
   returns at once and does not wait for the title.
2. **Summary first.** Generate a Full summary, start a new conversation, record and Stop: the title
   follows the summary's first point. No extra Apple Intelligence request appears in Status details.
3. **Never replaces yours.** Type a title while a recording is being named, or before Stop: your
   title stays. Import a meeting from Calendar into a new conversation, record and Stop: the meeting
   title stays. Import from Calendar into a conversation that was named automatically: the meeting's
   name replaces it.
   - **Not while recording.** Start recording, pull down Control Center and dismiss it: the title
     does not change until you Stop.
   - **Cloud sends nothing.** With Cloud AI (or an OpenAI-compatible server) selected and no
     summary, Stop: the title comes from keywords and the vendor's dashboard shows no request.
4. **Offline / AI off.** In Airplane mode with Ollama selected but unreachable, or without Apple
   Intelligence: the title still appears, from keywords.
5. **Apple Watch and Save to folder.** (The watch part needs a watch build, #181.) A watch recording drained into History gets a title instead of
   "Apple Watch · <date>". With Save to folder on, the note's `title:` updates and no second note
   appears.
6. **Off.** Turn the setting off, record and Stop: the name stays "New conversation".

Mac: record past 30 words and Stop; "Conversation — <date>" becomes a short title (from the Summary
model with Apple Intelligence or local Ollama, keywords otherwise). Stop while a Summary refresh is
still streaming: the title never ends mid-sentence. Click into the title field before the title
arrives: the default title stays until a later Save. Type a title first, or Load from Calendar: it stays.
Start a New conversation right after Stop: the saved one is renamed in History.

## iPhone: Quick and Summary only (#235)

Simulator is enough for 1–3; 4 needs a cloud or OpenAI-compatible model with Auto.

1. **Two tabs.** The iPhone workspace shows **Live** and **Summary** only. On iPad (or a wide window)
   the Summary sits beside Live with no Review picker. **More → Full summary** offers Summary and
   Quick Summary only.
2. **Settings.** Apple Intelligence, Ollama, OpenAI-compatible and every Cloud AI service list a
   **Summary model** and a **Quick Summary model**; no Deep model row. A device that had a Deep model
   chosen in an earlier build opens Settings normally.
3. **Earlier deep analysis.** Open a conversation from History that an earlier build saved with a
   Deep answer: under the Summary, a collapsed **Earlier deep analysis** expands to the old text,
   read-only. Share the conversation and check Save to folder: the Deep section is still there.
   Record more and save: it is kept, unchanged.
4. **Auto ignores Deep.** With Auto on, discuss an unresolved tradeoff. Quick and Summary update; no
   Deep request is sent and nothing new appears under Earlier deep analysis.

## iPhone Summarize selection (#234)

Simulator is enough for 1–4 (the UI test fixture fakes the model); 5 needs Apple Intelligence on a
physical device.

1. **Select.** Open a conversation with several finished lines. Tap the checklist button on the Live
   transcript: the full transcript opens with circles. Tap two lines → "2 lines selected"; drag down the
   circles from one line to another → the range is selected. A LIVE line has no circle.
2. **Summarize.** Tap Summarize selection: the sheet shows the time span, where the lines go, and bullets
   about only those lines. Copy, Share and Add to notes work; Notes gains "Selection summary (… · N lines)".
   Close it: the Summary tab lists the selection summary; relaunch and reopen from History: still there.
   Export as Markdown and JSON, and check Save to folder: each carries it under Selection summaries.
3. **Touch and hold.** Touch and hold a line → Summarize from here summarizes it through the latest line;
   Select from here opens Select mode with those lines picked. Copy copies the line.
4. **Provider and reasons.** With a cloud AI service or OpenAI-compatible server chosen, the bar and the sheet
   say "Sends the selected lines to <destination>", and the sheet sends nothing until you tap Summarize
   (check the server's log). Remove the key or server: Summarize selection and the touch-and-hold
   Summarize from here are disabled with the reason. While a Summary is generating, both say to wait;
   while a selection summary is being written, Generate Summary says to wait.
4a. **Cancel, rotate, reopen.** Start a selection summary and tap Cancel: "Cancelled.", no failure, and
   Summarize again works. Start one from the Live panel and rotate the phone: the sheet stays open and the
   answer arrives. Open a second selection sheet: it never shows the first one's text. Long-press text in
   a line outside Select mode: it can still be selected and copied.
5. **Apple Intelligence, long selection.** On a device with Apple Intelligence, select a long stretch (more
   than about ten minutes): the summary answers and the sheet says the selection was shortened.

## iPhone History search by meaning and Ask your history (#57)

Simulator or device; the Apple Intelligence answer in step 3 needs an eligible device.

1. **Related.** Save an English conversation about a budget ("we reviewed the quarterly budget and the
   funding round") and one about travel. A few seconds later, search `money` in History: the budget
   conversation is listed with its excerpt, marked **· Related**. Search `budget`: the excerpt shows the
   sentence with the word, labelled with where it came from (summary, notes or transcript).
2. **Ask.** Type "What did we decide about the budget?": an **Ask your history about "…"** row appears.
   With Ollama, an OpenAI-compatible server or a Cloud AI service selected, its footer says "Asking sends
   the matching excerpts (not whole conversations) and your question to …" before anything is sent.
3. **Answer and sources.** With Apple Intelligence the footer says the answer stays on this iPhone. Tap
   Ask: the answer cites `[1]`, and tapping a source opens that conversation.
4. **Deletion.** Delete the budget conversation: searching `money` no longer finds it.

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
5. **Apple Watch** (watch builds only, #181). With a watch conversation in History and another watch recording still in
   "Waiting from Apple Watch", delete all: the watch conversation and its audio are gone, and the
   waiting recording stays and becomes a conversation later.

## Save audio recordings (#55)

iPhone (a physical device: the simulator cannot record; steps 1 and 7 also run in the simulator):

1. **Off by default.** Fresh install: **More → Settings → Audio recordings → Save audio recordings** is
   off, the footer says audio is never uploaded and is left out of backups, and recording a few lines
   shows no "Saving audio" line and no play button.
2. **Saved per run.** Turn it on. Start, speak about 20 seconds, Stop; Start again, speak, Stop. While
   recording, the status says "Saving audio on this device". Settings shows the space used.
3. **Playback and seeking.** The live transcript's header shows a play button: tap it. The expanded
   transcript shows the player; tap the time on a line from the second Start: the second part plays
   from that line's words. Pause works; the position advances.
4. **Language switch and headset.** With Automatic language, speak another language until it switches,
   and connect AirPods mid-recording. After Stop, a line after the switch still plays its own words.
   Speaker labels and the language status behave as without the setting.
5. **Export.** **Share audio** in the player (and History's touch-and-hold menu) offers the `.m4a`
   files; AirDrop one to a Mac and play it in QuickTime.
6. **Deletion.** Delete the conversation in History: its audio is gone (Settings' space used drops).
   Record another, then **Delete all saved audio**: transcripts stay, the play button disappears.
   Record again, then **Delete all conversations** (#220): Settings shows no saved audio.
   While recording, Delete all saved audio is unavailable ("Available after you stop recording").
   Start, wait, and turn the setting off in Settings mid-recording: "Saving audio" disappears, an orange
   line says the audio until now is kept, transcription goes on; after Stop the part plays up to the switch.
   Start and Stop without speaking or typing notes: no audio is kept for that empty conversation.
7. **Low storage.** (Simulator is enough with `MobileSavedAudioTests`; on a device, fill storage to under
   100 MB.) Start: an orange "Audio is not being saved … Transcription continues" line appears and
   transcription runs.
8. **Backups.** In Finder, back up the iPhone unencrypted: the `SavedAudio` folder is not in the backup.
9. **Killed mid-recording.** Record about 30 seconds, then force-quit from the app switcher (Stop never
   runs). Relaunch: the conversation's part plays all but its last few seconds.

Mac (`make run`; macOS releases are paused, so this is for the build only):

1. In **Settings**, turn on "Save audio recordings (microphone and system audio)". Listen with system
   audio playing, Stop. **History** → the conversation shows **Saved audio** with Microphone and System
   audio parts that play.
2. With SpeechAnalyzer or WhisperKit, **Play from a line** lists the lines and plays each from its time;
   legacy SpeechRecognizer lines remain untimed.
3. **Clear history** deletes the audio too; **Delete all saved audio** in Settings keeps history.
4. Record two runs in one conversation with WhisperKit (Stop, Listen again): a line from the second run
   plays its own words, not the first run's.
5. With autosaving off, record: no audio is saved. With it on, record and choose **New** → **Discard**
   (after a failed save) or close with **Close without saving**: the audio is deleted.
6. Turn the setting off while recording: the files stop at once and keep what they have.



## Simplified Chinese vocabularies (#238)

1. On iPhone choose a fixed Chinese (Simplified) transcription language and enable Medical in
   Settings → Vocabularies. Record a continuous Mandarin sentence using 心房颤动、心力衰竭、美托洛尔、
   阿哌沙班、肌钙蛋白、肌酐、超声心动图. Compare transcription with the preset off; measure rather
   than assume a recognition improvement (#236). Check that My terms still reaches the recorder.
2. With no preset on, speak enough Mandarin clinical material (at least 150 tokenizer words). The
   Medical banner should offer Add and keep its safety note. Add must affect the running recognizer
   without restarting capture. Ordinary family/weekend speech should offer no preset.
3. With Automatic language, switch from English to Mandarin; check the new recognizer receives the
   Chinese terms. Undo must restore the English terms. Stop and reopen the Mandarin conversation
   after changing Settings to English: manual Summary/Quick should still get the saved Chinese glossary.
4. Traditional Chinese and French transcription retain English preset terms. Simplified Chinese
   Software & Cloud should match both Chinese terms and adjacent Latin jargon such as Kubernetes.
5. Repeat the fixed-language preset check in the installed macOS app (Mac publication remains paused).
   Summary headings and Medical's safety notice keep their English wording. All detection stays local.

Simulator tests cover term routing, continuous-text matching and the rendered banner using a fake
recorder. They do not prove physical-device recognition accuracy.

## Two-pane iPhone layout (#253)

1. Open a conversation containing transcript lines and Quick output in portrait. Rotate to landscape:
   Transcript and Quick sit beside one another, each scrolls, and Start/Stop, Notes, model selection,
   Generate and Expand transcript remain reachable. Scroll one pane without moving the other.
2. Open the expanded transcript, rotate, and close it. It must remain open until Done. Pick Summary,
   rotate both ways and confirm the selection, conversation title and saved output remain.
3. At accessibility text sizes, rotate both ways: use one outer scroll, without narrow side-by-side
   text columns. Recording controls stay available. On iPad, check wide and narrow window sizes.

## Conversation prompts (#257)

On Mac and iPhone/iPad, open Context/Notes. Choose a domain preset in Ask once; confirm it only fills
the editor, then edit and Ask with the chosen provider. Check answer location, cancellation and the
provider disclosure. Switch to Summary instructions, Save, generate manual and automatic summaries,
and confirm the requested format. Reopen the conversation and verify instructions remain; New must
clear them. Clear and save to remove them. Export Markdown/plain text/JSON and verify instructions.
Check Mac reopening does not overwrite the currently open record or drop attachments/languages.
Capture native-resolution phone portrait/landscape, iPad and Mac images; inspect large text and
keyboard reachability. Follow the release screenshot checklist.

## Saved-audio re-transcription (#224)

1. Save a recording, stop, reopen it from History, and choose **More → Re-transcribe saved audio**.
   Confirm it is unavailable without saved audio or while recording.
2. Choose the recorded language, re-transcribe and inspect the preview. On Mac test both Apple
   and WhisperKit with real saved system audio: final text must carry **OTHERS** and include the tail.
   On iPhone/iPad use a physical device for real Apple recognition; simulator fixtures check UI only.
3. Choose **Keep original** and confirm transcript, notes and summaries are unchanged. Repeat, then
   **Replace transcript**; verify the new text, language, playback timing and History after relaunch.
   Notes, attachments and instructions remain; old summaries remain for review.
4. Try a multi-run conversation and both Mac tracks. Confirm subsequent runs follow earlier audio
   and both tracks retain their source. Cancel during recognition and test a missing/unreadable file:
   neither may replace the original. Changing the transcript invalidates a pending preview.
5. In a Watch development build with saved audio, replace the transcript and reopen History. The
   player and replacement lines must still say Apple Watch; inferred names must reset. Continue
   recording on the phone and confirm its speaker/language analysis leaves Watch lines alone.
6. Capture native-resolution preview screenshots on standard/large iPhone, small/large iPad and Mac,
   retaining source, device, runtime and version provenance with the test evidence.

## Local Ollama context capacity (#230)

1. Select a downloaded local model with a 4K default but larger supported context. Ask about an
   opening fact in a long conversation. Confirm the answer includes it and `ollama ps` reports the
   larger context. `make e2e` creates/removes a temporary 4K-default alias and checks this contract.
2. Send a request beyond the selected model's safe capacity: the pane must explain that nothing
   was sent for an answer and suggest a shorter selection/larger model. Retain any previous answer.
3. Check Quick and correction still use their output limits. Cloud requests must not set `num_ctx`.

## Saved conversation vocabularies (#237)

Add Medical from the suggestion banner without Use by default. Stop, start a new conversation,
then reopen the first from History and relaunch the app: Medical must return only for the first
conversation. Resume listening and confirm its terms reach recognition. With Auto Quick enabled,
check that the chosen provider receives the domain and bounded glossary without Summary headings.
Delete that conversation and confirm it is gone after relaunch; device defaults and My terms remain.

### Watch file speaker labels (#192, TestFlight beta)

Simulator coverage uses `MobileWatchSpeakerTests` (real decoded WAV windows and a fake diarizer) and
`MobileWatchSpeakerUITests` (synthetic labeled Watch conversation in the actual transcript/Notes views).
It verifies bounded windows, gap timing, already-running preparation, cancellation, delayed chunks,
renames, archive persistence and labels saved before chunk deletion. It does not establish speaker accuracy.

On a paired Watch/iPhone candidate, with Identify speakers on and models ready, record two people,
transfer in multiple batches, and verify names persist through later arrivals, History reopen, rename,
search and export. Repeat with identification off and unavailable models: keep Apple Watch labels and
initiate no model download from the import. Interrupt with backgrounding and an iPhone recording;
retry safely without changing the live microphone's speaker run. After relaunch, new identities may
receive new numbers because voiceprints are never saved. Verify that raw audio is deleted after text
and labels are saved, and that relabeling does not request another AI summary. TestFlight 1.19.0 (38) includes Watch with accepted/processed package evidence; the physical #181 checks above remain pending for production.

### Watch audio retention (#225; TestFlight beta, physical acceptance pending)

On a paired Watch/iPhone, record while disconnected and confirm pending audio stays on Watch.
Reconnect and open the iPhone app: confirm one conversation appears, and Watch waiting count clears
only after successful transfer. With Save audio recordings off, no playback copy should remain after
transcription. With it on before import, expand the transcript, play and seek a line, and share a part;
the player names the source Apple Watch. Restart during import and retry: no duplicate text or audio.
Cause a storage failure: inbox audio stays available for Retry/Delete. Delete saved audio while an
import is failed, retry, and confirm deleted copies do not return. Delete the conversation and verify
both retained and pending audio are gone. Check expiry using an old recording. Confirm updated Watch
consent mentions reconnect and optional retention. Simulator tests cover import/playback/storage;
real WatchConnectivity transfer and Watch background recording require the paired-device #181 gate.

### iOS audio-driven language checks (#216)

In Automatic, speak in a language the starting transcriber does not recognize. Check that an initial language check still occurs after at least eight seconds of activity, and continuous talking can trigger later checks without new transcript results. Check the detected-language notice, Undo and Stop. Silence and sparse isolated sounds must not trigger an initial download; loud noise may qualify as activity but must still pass language confidence and switch rules. Re-checks pause in Low Power Mode, background and serious thermal state. Stop during model preparation must remain responsive. The simulator fixture verifies control flow with synthetic audio and a deterministic model; it does not establish real speech accuracy or device battery acceptance.


## Mac custom-server Auto compatibility (#209)

Save an OpenAI-compatible endpoint and choose a Quick model in the status rail. Reopen Settings
and select Check Auto compatibility. Confirm a synthetic exchange is sent to that saved endpoint
and model, without conversation text. A valid evaluator answer enables Auto; plain prose, malformed
JSON or reasoning-only output records a format failure and pauses Auto with a reason. Summary
remains usable. A successful recheck clears that server/model failure; choosing another model does
not inherit it. A connection failure and Cancel preserve the old result. Unsaved URL/key/context-limit edits
disable the check, so draft fields cannot change the recipient. Capture the result screen and restore
original settings after the test.

## Custom-server context capacity (#210)

In Settings, select OpenAI-compatible and a test server. Set Server context window to 4K and save.
Reopen Settings and verify 4K persists. A different API URL should show Unknown; returning to the
original URL restores its setting. Cancel an edit and verify no setting changes. For short synthetic
text, confirm the server receives an output cap of 1,024. With long text, verify Mac's trimming
notice and that requests still too large (including large instructions or Unicode text) fail with
“No text was sent” before the server receives them. Choose Unknown to restore server-managed behavior.
Capture the settings UI at native resolution and restore original preferences after testing.

### iOS Ollama endpoint feedback (#149)

In Settings, select Ollama and save `http://your-mac.local:11434`. Try saving
`http://100.64.0.1:11434`, a public IPv4 literal, and a non-link-local IPv6 literal: each must
explain HTTPS/local-address alternatives and keep the previous server. HTTPS addresses and
loopback/link-local HTTP remain accepted. Loopback points to the phone itself.
Paste `https://your-mac.local:11434/ollama?token=test-value`: confirm the saved destination is the
origin and the status says URL parts were omitted without echoing the query value. Capture the
visible error and normalization status at native resolution. Restore the original settings.
Opening a model list on Apple Intelligence must not automatically fetch the Ollama catalog;
explicit Refresh remains available. Unchosen provider defaults are recomputed on launch, while an
explicit provider choice persists.

### Delete one Mac conversation (#131)

Use disposable Dev conversations A and B, with Save audio recordings enabled for A. Open History,
right-click A and choose Delete conversation. Cancel once and confirm both records and A's playback
remain. Confirm the second attempt: A disappears from keyword and semantic search, A's saved audio
is gone, and B remains readable. Repeat through the detail view's Delete button and capture the
confirmation and resulting list. Exported copies must remain untouched.
Delete the currently open saved conversation while capture is stopped, then Save/Stop: it must not
reappear. Start New and verify the new conversation can save normally. A failed archive delete must
keep the row and audio, with a visible error. If an owned-data cleanup fails after text deletion,
show the partial-erasure warning. Do not modify production conversations or permissions.
## Review follow-ups (#141)

- With a pinned local model, make discovery or one capability probe fail. The active pinned choice
  must remain selected with a visible verification warning; an unverified request must still obey
  the existing local-only privacy check. Restore the server and retry discovery.
- Cold-load a verified local model: allow up to five minutes for a manual answer. Cancellation stays
  responsive; Auto review retains its shorter coordinator deadline. Cloud requests retain 90 seconds.
- Import a damaged/truncated audio file. A read failure must show an incomplete-transcript warning,
  preserve already recognized lines, and leave the saved record incomplete after reopening/renaming.
  New conversation clears this state. Stop legacy speech and verify final words are retained; a
  finalization deadline must show a warning instead of silently pretending the tail completed.
- Verify real system audio produces OTHERS transcription after the minimal video configuration;
  microphone-only pickup is not acceptance. Preserve recording, logs, screenshots and provenance.
- Attach a direct file or folder symlink: it must be skipped. A regular file over 200 KB must also
  be skipped. Render a heading with trailing spaces and export transcript containing Markdown links,
  angle brackets and multiline speaker names; speech stays literal while AI Markdown still formats.
- With an all-day busy block and a shorter current meeting, Calendar chooses the latest-starting
  active timed meeting. At its end boundary it chooses an ongoing or next meeting correctly.
## Permission-free global shortcut (#124)

With Accessibility ungranted, press ⌘⇧Space in ListenToMe and with another app focused: each press
requests one Quick answer. Holding the shortcut must not repeat; release and press again for another
answer. Other keys and extra-modifier variants must not trigger it. Permissions shows no Accessibility
request or toggle advice. If another app owns the combination, ListenToMe shows an unavailable notice
and its in-app shortcut/buttons remain usable. Close/reopen the conversation window and repeat to
check registration cleanup. Do not reset production permissions to run this check; use the Dev test
identity and preserve evidence before its authorized scoped cleanup.

### Independent Mac error banners (#173)

1. Produce a microphone-denied capture failure using the existing denied-permission test setup;
   do not reset production permissions. Confirm the capture message offers Open Settings.
2. While that message is visible, attempt an export to an unwritable destination. Both messages
   must remain visible. Dismiss file or calendar message: the capture message and its Settings
   action remain. Repeat, then dismiss capture message: the export error remains.
3. Retry an export to a writable destination. The file error clears without clearing a capture
   failure. Starting capture clears only the capture message, not an unrelated file error.
4. Trigger Calendar denial using an existing denied test profile. Its separate message must offer
   Open Calendar privacy settings; dismissing capture must not remove that action. An import failure
   uses the file/Calendar banner and must not replace a capture failure.
5. Start a new conversation and confirm errors from the previous one are cleared. Capture native
   screenshots with both banners, each independently dismissed, and the Calendar action. Preserve
   source/signing provenance and complete Dev-app cleanup after acceptance.

## Cancel an answer or import (#127)

1. Start a slow streamed Quick, Summary or Deep answer. Stop only that pane, retaining its partial
   text and showing a stopped notice. Late tokens/errors must not alter it; other streaming panes
   continue. Request a fresh answer and check the notice clears. Focus a pane and press Escape:
   only its stream stops. Stop during reasoning before text arrives must show that no answer arrived.
2. Import a long file. The status row shows its filename and increasing **% read**, then
   **Finalizing transcript…**; percentage measures file input, not completed recognition. Cancel
   midway or during finalization. Show **Stopping…**, disable repeat cancellation, keep recognized
   lines and show incomplete status. After cleanup, Start/New/Import are usable without closing the
   window. Reopen the saved conversation and verify the incomplete flag persists.
3. Cancel while speech assets prepare, then start another import after cleanup. Old tasks must not
   overwrite its progress or transcript. New conversation clears stopped-answer/import notices.
### iOS Ollama endpoint feedback (#149)

In Settings, select Ollama and save `http://your-mac.local:11434`. Try saving
`http://100.64.0.1:11434`, a public IPv4 literal, and a non-link-local IPv6 literal: each must
explain HTTPS/local-address alternatives and keep the previous server. HTTPS addresses and
loopback/link-local HTTP remain accepted. Loopback points to the phone itself.
Paste `https://your-mac.local:11434/ollama?token=test-value`: confirm the saved destination is the
origin and the status says URL parts were omitted without echoing the query value. Capture the
visible error and normalization status at native resolution. Restore the original settings.
Opening a model list on Apple Intelligence must not automatically fetch the Ollama catalog;
explicit Refresh remains available. Unchosen provider defaults are recomputed on launch, while an
explicit provider choice persists.

## Device capability and recording recovery (#306, #307)

Use the [compatibility matrix](device-compatibility.md) and bound BDD scenarios; policy tests alone
are not native acceptance. Preserve source, OS, device, native screenshots and actual outcomes.

- On iPhone/iPad, inspect Start before tapping: unsupported device/language, simulator or denied
  microphone must show its reason and applicable recovery, with Start disabled and no permission
  prompt/download from the check. A supported advanced or dictation profile enables Start.
- If later model preparation fails, inspect the full startup alert; dismiss, retry and open its
  recording settings. Cancel preparation without a false failure. Temporary inactivity for the
  permission prompt must preserve a pending start; backgrounding must not consume queued shares.
- On the connected older iPad, verify actual new microphone words using dictation, then Stop. Check
  fixed language and the default Automatic mode separately, and the advanced path on iPhone. Play
  synthetic speech only after the test confirms Listening; stop sound immediately if capture stops.
- With saving on, use the Live transcript Play icon after Stop (Transcript actions → Play recording
  in compact Duo), verify Play/Pause and audible playback. With saving off, retain no new audio.
  Enabling saving later cannot recover earlier audio. Preserve existing conversations and keys.
- On unsupported Apple hardware or while its model is not ready, inspect Settings: Apple must not be
  offered as working. Preserve an old saved Apple choice with its reason. Explicitly configure an
  alternate provider, destination, model and key; never auto-route. Refresh after setup/foreground.
- On Mac, inspect engine choices and Start for the selected language and permissions. Unsupported
  engines are not selectable; a saved unavailable engine remains explanatory with alternatives.
  AI gating must not disable supported capture. Verify actual microphone and system-audio OTHERS
  text on the supported route. Leave an OS permission request unanswered, then Stop, New or close:
  the app must finish cancellation without waiting for that callback. A system consent prompt may
  remain open. Begin a new conversation, then answer the old request: no late capture or denial may
  affect the new conversation. Cancel a close dialog and verify explicit retry.
- On Watch simulator, inspect independent local Record and iPhone remote. Unreachable/incompatible
  or unchecked phone capability blocks remote Start; reachable Stop remains usable after losing
  Start capability. Local denied microphone/low battery/storage shows its reason. Record offline
  with later reconnect sync still requires paired physical acceptance for production readiness. The authorized Watch beta may distribute after its candidate gates with those checks explicitly pending; see [Watch beta preparation](watch-beta.md).

The prior physical iPad failure and local fallback microphone pass are preserved in the #306 evidence.
Simulator results do not establish physical recording, model accuracy, audibility or Watch pairing.
### Automatic review request limits and directives (#148)

With Auto enabled, combine a transcript below 60,000 characters with a large attached reference on
Mac. A Deep request whose complete prompt exceeds 60,000 characters must show a review-limit notice
and never reach the selected provider. Shorten the reference and add meaningful speech: the next
eligible review should succeed. Instructions, speaker labels, notes and data fences also count.
Change response language or persona without adding speech: the completed automatic review stays
visible and no new request starts. Manual generation uses the new setting immediately; a review
triggered by new speech uses it too. Rename a speaker during a Quick read: old-label output must
not apply, unread speech must still be processed, and already acknowledged speech should not be
resent solely because of the label change.


## First-run local Ollama readiness (#129)

Use a disposable local server fixture or a separate test machine; do not stop the shared Ollama server
while contract tests or another recording are active. In onboarding, choose Local Ollama and verify:

- Unreachable/malformed catalog: a reachability/catalog warning and Install link, with Retry.
- A successful empty catalog: no installed models, a copyable `ollama pull llama3.2` command and Retry.
- Installed embedding-only/cloud-only models: no verified local chat model; never silently route to cloud.
- Failed capability probe: not verified, with existing pinned model retained and no false missing-model label.
- Ready local chat model: green readiness row; status-rail picker shows its normal name. A mixed ready/
  unverified catalog keeps the good model usable and reports the uncertain count.

Switch modes or leave the Ollama step during a check, then return and retry. Stale results must not
replace the new check or leave the spinner stuck. The rail reports the same states after Refresh
models. Copy the download command into an inspection field and verify the exact text; do not run it
as part of this UI check. Capture onboarding, warning and ready-state screenshots with source provenance.


## Movie import and source choice (#128)

- Import a normal M4A/WAV as Others, then an MP4 and MOV containing speech. In the picker select You
  for one video and Others for the other. Confirm resulting transcript labels/statistics match the
  selected source, and movie imports read their first audio track without playing video.
- Import a silent video: report no audio track and restore Start/New/Import controls. Try a damaged
  container and an unsupported file; show a readable error without replacing the existing transcript.
- Cancel during movie preparation, reading and finalization. Keep recognized text marked incomplete,
  preserve prior conversation content, and allow another import after cleanup. Capture the source
  picker, labelled transcript, progress and no-audio error with source/version provenance.
- Automated fixtures are synthetic one-second tone/black-frame MP4/MOV files under iOSUnitTests/Fixtures;
  their generation commands are in that folder's README. The native reader check is decoding evidence,
  not a speech-recognition or physical-device acceptance pass.
## Transcript editing (#126)

With Auto off, record or reopen several finalized lines. Select and copy a phrase; use Copy line and Copy transcript. Double-click a line, change a name, Cancel, and verify no change; repeat with Save. Empty edits must be disabled. Confirm timestamps, speaker and language survive, and export lists original and corrected wording. Edit an existing summary and verify its replacement uses the corrected text. Edit before any summary and verify no AI request starts. Delete a line, first cancelling then confirming; verify other lines remain and the reopened History/export/search reflect deletion. Delete the final line of a saved conversation with empty notes, reopen it, and verify the empty transcript stays empty. During a later capture run, delete an earlier-run line and verify speaker labels still cover the current run. Saved audio and previously exported files remain unchanged. Capture native screenshots of editing and confirmation.

## Capture timeline and follow-latest (#68)

With SpeechAnalyzer, record known alternating microphone and system audio separated by silence. Verify OTHERS transcription and line timestamps against saved audio, including delayed finalization, Stop/Listen again, and line playback in the second run. Cancel during preparation and confirm no late line enters the next conversation. While partials grow on both channels, resize the window and confirm Latest remains followed. Scroll up during bursts; the view must not jump to the bottom. Use Latest and confirm following resumes. Preserve screenshots and actual-audio evidence; Core timing tests and a signed build are not substitutes for this acceptance.
## Compute transparency (#60)

Expand Engine → Compute details for each transcription engine. Before recording, runtime says Not running. During preparation and capture, it says Preparing/Not exposed rather than claiming GPU/Neural Engine activity. WhisperKit displays the policy passed to its constructor; Apple engines say managed by Apple Speech. Change the selected engine while recording and confirm the rail keeps the active engine’s policy until the next capture. While Stop drains transcription, runtime must remain Not exposed. Import a file with WhisperKit selected for live capture: the rail must identify SpeechAnalyzer and its Apple-managed policy. Capture the expanded details as release evidence.

## Live audio and response timing (#56)

Play known system audio with the microphone quiet; confirm the system RMS meter moves, microphone reads Silence, and actual system transcription is labeled OTHERS. Reverse the inputs. Stop must show Stopped; denied or failed channels show Unavailable, and a channel with no fresh samples shows No recent audio. Request Quick/Summary/Deep with a thinking model: elapsed time starts before content, thinking does not count as first content, and completion preserves timings. Stop a response (or change its model) and verify Cancelled; fail a request and verify Failed; a newer request must retain its own measurement when old work finishes. Check Auto Quick and automatic reviews too. New conversation clears measurements. Capture native screenshots with provenance; helper tests do not establish real audio acceptance.
## Whisper model selection (#58)

Start from no saved preference and verify Base. Select Tiny, Cancel Settings, reopen and confirm Base; then select Tiny and Save, relaunch and confirm Tiny. Start capture and verify the status names Tiny and loaded variant validation succeeds. Repeat with Base and Small using the same microphone/system test audio, recording observed quality and latency without generalizing to other Macs. Change the selection during a capture: that capture keeps its model; the next uses the saved choice. Simulate a download/load failure and confirm the selected model is named with retry guidance. Confirm no model download occurs merely by opening Settings. Preserve screenshots, logs, exact source, selected/loaded variants and actual OTHERS transcription evidence.

## Optional calendar suggestions (#54)

1. With Calendar access absent and the feature off, wait 35 seconds: no permission prompt or recording. Enable the setting and Save; passive checks still must not prompt. Use **Allow Calendar access** explicitly to grant or deny. Denial must leave capture stopped and show guidance. Canceling Settings must not persist the opt-in.
2. In an empty, idle conversation with an event happening now, wait up to 30 seconds. Inspect the banner and capture a native screenshot. Future, ended, all-day, canceled, free and declined events must not trigger it.
3. Dismiss the suggestion, restart the app and verify the same occurrence stays suppressed; a later recurrence may be suggested. Start/import/open a conversation and verify no suggestion overwrites its content.
4. Click **Use context and Start**: the title and Context use the event, normal capture preflight runs, and recording starts only after this explicit action. Check the selected AI provider privacy behavior. Stop, preserve evidence, and complete the app-scoped Dev cleanup procedure.

These are acceptance steps, not a record of a completed native run.
## Structured Summary cards (#62)

Use a new test conversation with an unresolved question, explicit action/owner/deadline and decision. Generate Summary with the chosen provider; inspect the three categories and expand each source. Confirm speaker labels match and untimed lines show no invented clock. Copy/export must be readable. Add more speech, refresh, and verify prior unresolved items remain; explicitly resolve an item and check the new state. Reopen from History, rename the conversation and verify cards survive. With a model returning freeform, malformed JSON or unsupported quotes, inspect the normal fallback text. Cancel or fail a refresh: never label partial output as a validated grid. Capture native screenshots and preserve candidate provenance. Actual model interpretation and rendered UI acceptance remain separate from schema/unit checks.
## Automated adapter coverage (#134)

`make mac-test` runs the selected native Mac adapter bundle, including actual FileContextLoader and SpeakerAudioBuffer code, native RTF decoding, AVAudioConverter resampling, cap and prior-generation rejection. It launches no ListenToMe Dev app and requests no capture permissions. It is not a whole-App coverage measurement. Core ConversationRepository tests cover archive-first cleanup, failed/unavailable storage, sticky damaged-file warnings, and durable snapshot publication. Neither suite substitutes for installed-app GUI/audio acceptance.

### iOS capture coordinator regression (#134)

Start and immediately Stop while preparation is active; no recording should begin later. Start again,
speak, then Stop twice through phone/Watch controls. Both callers must finish after the same drain;
final words must appear in History as a complete record. Start a second recording and confirm old
recorder callbacks cannot append text or report a failure in it. Repeat background/interruption,
language switching, speaker identification and Save audio recordings on/off. Simulator fakes exercise
late callbacks and held finalization; they do not prove physical microphone or paired-Watch behavior.

### Mac capture coordinator regression (#134)

During first-run preparation, press Stop and confirm it does not wait for the model download or
start recording later. While recording, change language twice, then Stop before restart completes:
no superseded restart may resume capture. Start again after Stop and verify the previous final
checkpoint is complete, the new live record is incomplete, and old speaker work cannot label the
new run. New and window close must drain final text/audio before their existing save decision.
Verify actual system-audio transcription labeled OTHERS and preserve native screenshots and
source/signing provenance. Core state-machine tests do not replace installed-app audio acceptance.

### Shared naming coordinator regression (#134)

Save or stop the same eligible conversation repeatedly while naming is pending; only one naming task
should run. Type a title before completion and confirm it remains unchanged. Start a new conversation
while the old one is being named: only the saved older record may change. Repeat with Watch imports
and Save to folder on iOS. Cloud/provider restrictions remain unchanged; these tests do not authorize
a model download or cloud naming. Core tests also force a cancellation-ignoring old result to arrive
after its replacement starts and verify the replacement remains registered and is the only one applied.

### Speaker retry across a recording change (#134)

With speaker models delayed, request Identify speakers, then start a new recording before preparation
finishes. The old request must not clear the new run's status or analyze its audio. Complete a current
pass, Stop, and confirm the final pass includes final transcript lines. Verify actual system-audio
transcription remains labeled OTHERS. Capture the relevant status UI and preserve source/signing
provenance; complete the authorized Dev-app cleanup after the testing session.

### Checkpoint persistence after coordinator extraction (#134)

In an isolated Dev conversation, capture finalized OTHERS speech, Stop, and confirm History and the
optional Save to folder note retain the original date across subsequent recording cycles. Reopen a
record and save an edit; then start New and save identical text as a distinct conversation. Use the
existing isolated archive-failure setup to trigger a failed write, restore writable storage and Retry
save; the failed content must persist. Clear History during an active conversation and confirm later
Stop does not restore it. Preserve screenshots and signing/source evidence, then clean up the completed
Dev session as documented. Core tests supplement these installed-app checks, not replace them.

### Conversation-owned Calendar and references (#134, ORCH-001–005)

Load Calendar while its permission/lookup reply is pending. Type new Context text, or accept New or
open another saved conversation: the old event or denial must not overwrite current Context, title
or messages. A title typed during lookup stays typed. In the unchanged conversation, a successful
lookup still includes event time, attendees and notes; denial and no-event recovery stay distinct.

Attach a local folder, then Clear before its read completes: no late content or skipped-file message
may return. Select newer files while an older read waits: only the latest selection becomes grounding.
Close while context is loading and Cancel the save/close decision: the window stays open and its
selected references and Calendar request still finish. Repeat with accepted close: late results
cannot update the closed conversation. A busy close refusal must not cancel pending context.
Already-running synchronous local I/O may finish after cancellation; its result cannot publish.
Preserve native screenshots and source provenance. Core held-continuation tests supplement this
rendered/OS-permission acceptance and never mark it passed.

### Model catalog ownership (#134, ORCH-006/007)

Delay a configured server’s catalog reply, open Settings and change AI mode or the custom server URL.
The old reply must not replace current model choices, status or local-readiness guidance. Repeat
with a newer Refresh finishing before the older request. AI off must request no catalog and keep
saved model choices for re-enabling AI. Apple Intelligence uses its on-device entry without catalog
access. Failed discovery keeps pinned choices; custom/cloud-service catalogs never choose a model
for an unset pane. Close with discovery pending and verify no late UI update. Already-started
network I/O may complete; these checks concern publication and no new request while AI is off.
Use only an explicitly configured test destination and preserve native screenshots/source evidence.

### Pane commands and New/import ownership (#134, ORCH-008–013)

Use the menu or Quick hotkey, then immediately Stop the requested pane: its running state must be
registered at the click and no answer may start afterward. Repeat Quick, Deep and Summary. Generate
a long Summary spanning several batches and wait for completion: early actions and all later batches
must remain, including provisional-budget handling. Stop during a later batch and retain partial text.

While final speech drains, request New twice. Only one save decision may appear; final speech must
be saved before reset. With saving unavailable, Cancel or a cancelled Save As keeps the conversation.
Choose Save As or explicit discard and verify reset only follows that accepted decision. Import a
recording then immediately Cancel before media opens: no transcript appears. Cancel during active
transcription: keep recognized lines/incomplete provenance and block another import until drain.
Close with capability or Calendar-suggestion work pending; no late result changes current controls.
Repeat speaker rename followed by New or a new recording: the old follow-up must not checkpoint
the new run. Retained settings, prompts, title editing, pane sizes and all sheets must render as before.
Capture fresh native Mac screenshots; verify actual OTHERS transcription separately. Native graph
tests prove shared-store/buffer wiring, not SwiftUI rendering or physical capture acceptance.
