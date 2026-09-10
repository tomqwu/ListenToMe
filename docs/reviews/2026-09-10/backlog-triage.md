# PR and issue triage — September 10, 2026

The published 1.3.2 build 9 was installed from the checksum-verified GitHub asset and About showed
the correct version. This maintenance pass reconciles old proposals with the current production app.
No feature below is considered implemented solely because it was triaged.

## Pull requests

| PR | Disposition | Reason |
|---|---|---|
| #63 | Update and merge | Keep Issues as backlog; link CLAUDE.md to the canonical AGENTS.md release workflow; correct shipped history. |
| #51 | Close as superseded | The old slim icon toolbar/layout predates the shipped explicit Save/New/History controls and September direction. |
| #64 | Close stale implementation; retain #52 | Its provider routing predates AI off/local/cloud enforcement; localhost alone does not prove a server stays local, and stream validation needs parity. |
| #65 | Close stale implementation; retain #68 | Using most recently fed audio for delayed results is not accurate source timing. Preserve the review as historical evidence and rework timing/scrolling on current main. |

## Existing enhancement issues

| Issue | Disposition and remaining acceptance |
|---|---|
| #52 | Keep; redesign compatible endpoints around explicit consent, redirect/relay privacy, errors and stream contracts. The shipped product remains Ollama-only. |
| #53 | Keep P1; opt-in folder selection, atomic Markdown upserts, stable filenames, retryable storage errors and no duplicate notes on autosave. |
| #54 | Keep; opt-in meeting detection should offer a start action rather than record merely because a process exists. |
| #55 | Keep; opt-in disk audio, bounded streaming writes, channel metadata, storage failure handling, retention/deletion controls. |
| #56 | Keep; real per-source RMS/peak levels and measured per-role latency; do not infer activity from transcript counts. |
| #57 | Keep; local semantic ranking with supported-language fallback, source-linked answers, deletion consistency and retrieval tests. |
| #58 | Keep; explicit tiny/base/small model selection with persistence, visible download/errors and measured tradeoffs before promises. |
| #59 | Close as overlapping umbrella. Local Obsidian/folder output belongs in #53, structured actions in #62. Direct Notion synchronization is deferred; it requires a separate explicit export design. |
| #60 | Keep; display selected engine and configured compute settings; only call an accelerator active when runtime evidence supports it. |
| #61 | Keep; bounded suggestions cadence, literal prompt on click, no extra requests in AI off, and no stale suggestions across New. |
| #62 | Keep; validated structured output, source references, fallback for unsupported models, and no invented owners/deadlines. |

The two high-severity July findings already have production mitigations: model metadata checks
before local-only requests, and microphone configuration-change reporting. Full automatic device
recovery is still not implemented. The remaining historical findings need current reproductions,
not mechanical issue creation or claims that all 39 are resolved.

Valid future enhancements stay open. Closing them as completed would misrepresent the product.
