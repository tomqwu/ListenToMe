# ListenToMe — Manual Smoke Test

> **Note:** `make e2e` already covers the app build, app-bundle path resolution, and a real LLM
> contract test (streaming through `OllamaProvider`). This document covers the audio/transcription
> path that cannot be automated: mic capture, system-audio capture, and live speech-to-text — all
> of which require a GUI session and manual permission grants.

Prereq: Ollama running with at least one chat-capable model installed (local or Ollama-cloud, e.g.
`deepseek-v4-flash:cloud`). The app auto-picks an installed model per pane on first launch.

1. `make run` — the window opens with **four panes**: **Transcript** (left) and **Listener**,
   **Quick**, **Deep** (right).
2. On first launch, the app shows a **Permissions** panel automatically. Grant Microphone,
   Speech Recognition, Screen Recording (system audio), and Accessibility (global hotkey) directly
   from the panel. You can also reopen it anytime via the 🛡️ (lock.shield) toolbar button.
   Re-click **Listen** after granting if needed.
3. In each AI pane's header, confirm a **model dropdown** is populated with your installed Ollama
   models. Set different models per pane if you like (e.g. a fast model for **Quick**, a heavier one
   for **Deep**, `deepseek-v4-flash:cloud` for any). The toolbar **↻** button re-scans models.
4. Click **Listen**. Speak a sentence → it appears under **Transcript** labeled **You** (blue).
5. Play speech from another app (a video/meeting) → it appears labeled **Others** (green).
6. In the **Quick** pane, click **What should I answer?** → a streamed suggestion appears (a
   "💭 Thinking…" state shows first for thinking models).
7. With **Proactive** on, have the other audio ask a question → a Quick suggestion appears
   automatically ~1-2s after the utterance ends. Press **⌘⇧Space** while another app is focused →
   a Quick suggestion is generated.
8. **Listener** pane: after some conversation, confirm a rolling summary + open questions/action
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
    SpeechAnalyzer's finalization semantics need on-device confirmation.

If dual-channel transcription shows only one speaker (a console error mentioning
`kAFAssistantErrorDomain 1100`), see the README "Known limitations" — the fallback is
single-source for the MVP or the Phase-2 SpeechAnalyzer engine.

## OpenAI-compatible endpoint (optional)

1. Start any OpenAI-compatible server locally (e.g. LM Studio on `http://localhost:1234/v1`).
2. **Settings → AI backend → OpenAI-compatible endpoint**; set the Base URL to that server's `/v1`
   (key blank for a local server); Save.
3. Confirm the per-pane model dropdowns populate from the endpoint's `/v1/models`, and that a Quick
   action streams a reply. The footer should still read "local models stay private" for a localhost URL.
4. Switch the backend back to **Ollama** and confirm normal operation resumes.
