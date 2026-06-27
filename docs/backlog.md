# ListenToMe — Backlog

Post-v1.0 feature backlog. Items are sourced from the competitive analysis
(`docs/competition-analysis.md`) and a pass over the **open-source** competitors' GitHub repos —
[Meetily](https://github.com/Zackriya-Solutions/meetily), [Hyprnote / Anarlog](https://github.com/fastrepl/anarlog),
and [Screenpipe](https://github.com/mediar-ai/screenpipe). Each item notes **why** (which competitor
is ahead) and a rough **effort**. Nothing here is committed — it's a prioritized idea list.

Guiding constraint: every item must stay true to the product's principles — **on-device, private,
bring-your-own-model, free & open-source**. Anything that would send data off-device by default is
out.

---

## ✅ Recently shipped (v1.0 → v1.1)

These closed gaps that competitors had over the v1.0 MVP:

- **Use-case presets** (18 presets, persona guidance) — vs single-vertical competitors.
- **Configurable reference budget**, **file/folder context**, **audio-file import**.
- **WhisperKit engine** (opt-in, multilingual / code-switching).
- **Calendar auto-context** (EventKit, local) — parity with Granola/Fathom/Fellow auto-context.
- **Cross-meeting search** (local, on-device) — parity with AskFred/Ask Granola/Natively RAG (keyword tier).
- **Richer exports** — Markdown / **recap** / **PDF**, plus copy-to-clipboard.
- **C · Pro command-center UI** + dark theme.

---

## 🔜 Candidate backlog (prioritized)

### P1 — high value, aligned

1. **Speaker diarization** — *Meetily ships it; Otter/Fireflies/Natively label who-said-what.*
   On-device diarization of the "Others" channel into Speaker 1/2/… Effort: **large** — Apple
   provides no diarization API, so this needs a bundled CoreML speaker-embedding model
   (e.g. a pyannote/sherpa-onnx port) + clustering, with quality validation. The biggest single gap.
   **Shipped (experimental first cut):** opt-in "Speaker breakdown" — FluidAudio (native Swift +
   CoreML Pyannote, models auto-downloaded on first use) diarizes the captured Others channel and
   shows each voice's talk-time share in a sheet. Default OFF, flagged experimental; quality is
   user-validated. Core stays pure (`SpeakerStats` aggregation); FluidAudio lives only in the App
   target. Follow-ups: inline who-said-what labeling in the transcript and accuracy tuning.

2. **OpenAI-compatible endpoint support** — *Hyprnote supports LM Studio / OpenRouter / any
   OpenAI-compatible API.* Generalize `OllamaProvider` to also speak the OpenAI
   `/v1/chat/completions` shape, so users can point a pane at LM Studio, OpenRouter, vLLM, etc.
   (still BYO-model, still local when the endpoint is local). Effort: **small–medium**; high reach.

3. **Auto-save notes to a Markdown vault / folder** — *Hyprnote/Anarlog saves notes as markdown on
   disk.* A "save each session's recap to `<folder>`" option (Obsidian-friendly), beyond the manual
   export we have today. Effort: **small** (we already format Markdown + persist sessions).

### P2 — useful, more scope

4. **Meeting auto-detection / auto-start** — *Granola, Fathom, Fellow, Superpowered, Meetily tie
   into a meeting starting.* Detect a Zoom/Meet/Teams call (running process or calendar event in
   progress) and offer to start capturing + preload context. Effort: **medium**; needs process
   detection (and to stay non-creepy/opt-in).

5. **Save the raw audio recording** — *Most competitors keep the audio.* Optionally write the
   captured audio (mic and/or system) to disk per session for re-listening / re-transcription.
   Effort: **medium** (tap the capture buffers to a file); add a clear privacy toggle.

6. **Command-center live data** — finish the rail we deferred in the C port: a **real audio level
   meter** (expose RMS from `DualChannelCapture`) and **per-role response latency** badges (measure
   stream wall-time in `MeetingSession`). Effort: **small**; pure polish on the chosen UI.

7. **Semantic cross-meeting search (RAG)** — upgrade the keyword search to on-device semantic
   ranking via `NLEmbedding` (NaturalLanguage), and let a pane answer questions across past
   sessions. *AskFred / Ask Granola / Natively do cloud RAG; ours would be local.* Effort: **medium**.

### P3 — explore / lower priority

8. **More transcription model choices** — *Meetily exposes Parakeet (NVIDIA) + Whisper sizes.*
   Surface WhisperKit model-size options (tiny/base/small) and document trade-offs. Effort: **small**.

9. **Export integrations** — direct **Notion / Obsidian** export targets and a structured
   action-item / task-list extraction. Effort: **medium**; keep local-first.

10. **GPU/accel transparency** — *Meetily advertises Metal/CoreML acceleration.* Surface which
    on-device accelerator is in use (Apple Speech / WhisperKit already use Metal/CoreML). Effort:
    **tiny** (informational).

---

## ❌ Intentionally out of scope

- **iOS / Android / Windows companions** — *several competitors are cross-platform.* ListenToMe is a
  focused macOS app; a mobile companion is a separate product, not a backlog item.
- **Cloud accounts / team workspaces / shareable cloud links** — conflicts with the on-device,
  private, no-account positioning.
- **Dedicated Claude / OpenAI provider integrations** — superseded by item #2 (one OpenAI-compatible
  path) and the existing Ollama-cloud route; we don't ship per-vendor SDKs.
