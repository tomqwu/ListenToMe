# ListenToMe — Backlog

> **The candidate backlog now lives in [GitHub Issues](https://github.com/tomqwu/ListenToMe/issues) — not this doc.**
> Browse by priority label: `priority: P1` · `priority: P2` · `priority: P3` (all also carry `enhancement`).
> A static list goes stale; issues are trackable, closeable, and linkable to PRs. This file keeps only the
> guiding constraint, the shipped history, and what's intentionally out of scope.

**Guiding constraint:** every item must stay true to the product's principles — **on-device, private,
bring-your-own-model, free & open-source**. Anything that would send data off-device by default is out.

---

## ✅ Shipped

Gaps closed since the v1.0 MVP (newest last):

- **v1.0 → v1.1** — use-case presets (persona guidance), configurable reference budget, file/folder
  context, audio-file import, WhisperKit engine (opt-in, multilingual), calendar auto-context (EventKit,
  local), cross-meeting search (local keyword), richer exports (Markdown / recap / PDF + copy).
- **v1.1 → v1.2** — on-device **speaker diarization** + inline transcript labels (FluidAudio, #47), more
  one-tap **Quick** prompts (#48), horizontally **resizable panes** (#50).
- **In progress** — cockpit UI redesign in a **Native-Mac** style (slim top bar + ⚙ Configure popover;
  transcript-left · Listener-center · Quick-right · Deep-bottom) — PR #51.

## 🔜 Candidate backlog → GitHub Issues

Moved to [Issues](https://github.com/tomqwu/ListenToMe/issues). Each issue notes **why** (which competitor
is ahead) and a rough **effort**. Sourced from `docs/competition-analysis.md` plus a pass over the
open-source competitors' repos — [Meetily](https://github.com/Zackriya-Solutions/meetily),
[Hyprnote / Anarlog](https://github.com/fastrepl/anarlog),
[Screenpipe](https://github.com/mediar-ai/screenpipe).

## ❌ Intentionally out of scope

- **iOS / Android / Windows companions** — ListenToMe is a focused macOS app; a mobile companion is a
  separate product, not a backlog item.
- **Cloud accounts / team workspaces / shareable cloud links** — conflicts with the on-device, private,
  no-account positioning.
- **Dedicated Claude / OpenAI provider SDKs** — superseded by one OpenAI-compatible endpoint (issue #52)
  and the existing Ollama-cloud route; we don't ship per-vendor SDKs.
