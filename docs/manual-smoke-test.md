# ListenToMe — Manual Smoke Test

Prereq: Ollama running with `llama3.1` pulled (`ollama pull llama3.1`).

1. `make run` — the app window opens with two panes.
2. Click **Listen**. Grant: Microphone, Speech Recognition, Screen Recording (system audio),
   and Accessibility (global hotkey) when prompted. Re-click Listen after granting if needed.
3. Speak a sentence → it appears under **Transcript** labeled **You** (blue).
4. Play speech from another app (e.g., a YouTube video or a meeting) → it appears labeled
   **Others** (green).
5. Click **What should I answer?** → a streamed suggestion appears in the right pane.
6. With **Proactive** on, have the other audio ask a question (e.g., "what is the plan?") →
   a suggestion appears automatically within ~1-2s of the utterance ending.
7. Type into **Context notes** (e.g., "I am the backend lead"), then trigger a suggestion →
   the answer reflects the note.
8. Press **⌘⇧Space** while another app is focused → a suggestion is generated.
9. Click **Stop** → the red recording indicator disappears and capture halts.
10. Open **Settings** (gear icon). Switch the provider to **DeepSeek**, pick **V4 Flash**, paste a
    DeepSeek API key, and **Save** → trigger a suggestion and confirm it streams from DeepSeek.
    Switch back to **Ollama** and Save. (An empty key or blank Ollama model is rejected with a
    message; the selection persists across relaunches.)

11. In **Settings**, confirm **Transcription engine** = **SpeechAnalyzer**. Verify dual-channel:
    speak (You) while other audio plays (Others) — both should transcribe concurrently. Confirm
    finalized lines (not just live/volatile partials) accumulate in the Transcript and that
    proactive suggestions fire on `Others` questions. If finalized lines never commit (only volatile
    text shows), switch the engine to **SpeechRecognizer** and report — SpeechAnalyzer's
    finalization semantics need on-device confirmation.

If dual-channel transcription shows only one speaker (a console error mentioning
`kAFAssistantErrorDomain 1100`), see the README "Known limitations" — the fallback is
single-source for the MVP or the Phase-2 SpeechAnalyzer engine.
