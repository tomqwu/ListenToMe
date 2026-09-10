# Production roadmap — release target September 10, 2026

**Plan v1.1 · updated with the user's Save / New conversation / labeled-button requirements**

Target: a reliable production release for existing users and a small pilot group. Broad-public readiness and default speaker identification are not assumed. Source reviewed: `3c542e3`; current public release: 1.2.1; local packaged candidate: 1.3.0. Use **1.3.1 / build 7 or newer** for the hardened candidate so installed 1.3.0 builds are distinguishable. No release has been created by this planning work.

[Full design and gap review](design-and-gap-review.md) · [Evidence](evidence.md) · [Proposed layout](proposed-layout.svg)

## Requirements confirmed by the user

1. **Save conversation:** a large, labeled, discoverable action. Save the current transcript and available summary, speaker names, notes and session metadata. Give a visible “Saved at …” confirmation only after the durable write succeeds. Saving must work during capture and after Stop; optional AI/speaker processing must not block it.
2. **New conversation:** a separate large, labeled action. Finish the current capture, save available content, create a fresh session ID and clear transcript, partials, AI context/outputs, speaker assignments and notes. Default to clearing reference attachments; allow deliberate reuse. Keep model, language and appearance preferences. Prior sessions remain available in History.
3. **Buttons users can understand:** icon plus visible text for primary actions. Tooltips explain consequences and shortcuts but do not substitute for labels. Avoid tiny icon-only controls for Save, New, History, Settings and export.

If automatic history saving is disabled, “Save conversation” opens an explicit Save As/export choice without silently enabling history retention. “New conversation” offers Save As or a clearly confirmed discard. If a normal save fails, preserve the conversation, show Retry / Save As, and do not report success or clear content.

## Today's toolbar and state contract

Use native `Label` controls, approximately 18–20-point symbols, 13–14-point text and 36–40-point-high hit areas; test actual macOS sizing and VoiceOver rather than imposing a mobile-sized layout everywhere. Proposed left-to-right order:

**Start listening / Stop listening · Save conversation · New conversation · History · Export ▾ · Settings**

The meeting title and a second, readable status row carry: Mic status, System audio status, Transcription status, AI mode/destination, Saved/Saving/Save failed, and Finalizing. Put infrequent model refresh/import/reference setup inside a **More** or **Setup** menu, with labeled menu entries. At narrower widths collapse secondary actions first; keep Start/Stop, Save and New visible. Supply tooltips such as “Save this conversation without stopping capture” and “Save this conversation and start a new one.”

Wire ⌘S Save, ⌘N New conversation, ⌘F History/search, ⌘E Export and ⌘, Settings. Keep ⌘⇧Space Quick reply. Either implement the advertised recap shortcut without colliding with existing commands or remove its footer hint. Put commands in the native menu and match keyboard/button behavior.

| State | What the user sees | Required behavior |
|---|---|---|
| Ready | Start listening; clear setup readiness | No active capture; Save enabled only with content |
| Starting | Starting…; current permission/model task | Stop/cancel remains reachable; no false “recording healthy” claim |
| Recording | Stop listening; independent source health | Save checkpoints without interrupting capture; New follows safe finalization |
| Degraded | Example: “System audio unavailable — microphone only” | Keep useful work running; offer specific retry/fix; never hide missing capture |
| Finalizing | Capture stopped; transcript saving and optional processing separately visible | Persist finalized text first; allow export; prevent duplicate New/Start races |
| Saved | Saved time and pending optional updates, if any | New opens a clean conversation; History opens the prior record |
| Save failed | Persistent error + Retry / Save As | Preserve in-memory content; do not silently clear or advance the save marker |

Do not replace the whole main layout today. Fix controls, status and Settings fit first. The wireframe's tabbed Copilot area is the next layout iteration, not a prerequisite for this release.

## Execution order and ownership

Roles below are proposed responsibility assignments, not additional agents: implementation/release owner = Codex working with Tom; real-meeting/device validation and scope decisions = Tom; public release acceptance = Tom. The current task is planning; implementation begins with these concrete work packages.

| Package | Work / gap IDs | Completion evidence | Planning effort |
|---|---|---|---|
| A. Scope and reproducibility | Freeze supported hardware/engine path; beta speakers off by default; verify publishing auth, main targeting and required checks; lock dependencies. G09/G10/G27 | Exact commit and dependency manifest; authorized release path; documented support matrix | 30–60 min, access permitting |
| B. Preserve conversations | Durable incremental saving, surfaced write failures, recovery, Save / New conversation, history detail and export. G02/G03/G07/G08/G25 | Recovery after forced termination with synthetic data; Save while recording; New A→B has no A context; failed write keeps A; history A reopens | 2–4 h |
| C. Make status and AI behavior truthful | Per-source failure/readiness, explicit local/cloud policy and AI-off mode, stream-error handling, retained early decisions/actions. G01/G04/G05/G06/G20/G21/G28 | Synthetic routing/error/context tests plus denied-source and offline-model runs; no silent success | 2–4 h |
| D. Usable controls and layout | Labeled toolbar, functional shortcuts, scrollable Settings, readable contrast, per-source partials. G11/G12/G13 | Keyboard and pointer workflows; no clipped actions at required sizes; source partials do not erase one another | 1–2 h |
| E. Release verification | App-build CI on macos-26, clean install/upgrade, real meeting and resilience matrix; source/artifact parity. G10/G29/G30/G31 | Results attached to frozen commit; candidate's version/hash; verified notices and supported-feature docs | 2–3 h plus service queues |
| F. Package and publish | New signed/notarized DMG; checksum; release notes and support/rollback instructions | Gatekeeper/stapler success; installed artifact matches; release asset downloaded and verified | 30–60 min plus notarization queue |

These are estimates, not commitments. Total single-owner work is roughly **8–15 hours**, with dependencies and access/real-device testing potentially extending it. A full fix of all 34 gaps is not credible as a same-day promise. Keep the deadline by containing beta features and deferring redesign/integrations, never by skipping transcript safety or truthful routing.

## Today's checkpoints — America/Toronto

- **09:30 scope freeze:** accept the limited production audience, Save/New/labeled toolbar requirements, minimum supported device/engine path, and beta exclusions. Resolve publishing access early. Build fixtures while code work starts.
- **13:00 core checkpoint:** working Save/New/history/recovery and routing/capture-error fixes demonstrated. If conversation durability or routing remains unresolved, change the target to a prerelease or hold; do not let polish consume the recovery window.
- **15:00 candidate freeze:** no further features; merge reviewed changes, freeze version/commit/dependencies. Begin/finish full artifact testing. If fixes require more time, shift the candidate window rather than label untested code production.
- **17:00 go/no-go:** every mandatory gate below has evidence from the final candidate. A pilot prerelease is acceptable when explicitly labeled; a failing P0 is not a production release.
- **18:00 target distribution**, with a later-evening window only if all gates complete. Missing GUI/audio access is an evidence gap, not a pass. A notarization queue delay may also move publication.

The clock does not override the gates. These checkpoints are deliberately aggressive given the effort range; make the scope decision at 13:00 instead of discovering late that the critical path cannot finish.

## Mandatory release gates

| Gate | Acceptance criteria | Today’s starting status |
|---|---|---|
| Conversation durability | With saving enabled, finalized text is durably checkpointed within a proposed maximum of 5 seconds. After forced termination, recover through the last acknowledged checkpoint; never claim unsaved partial speech was saved. A denied/full storage path yields a visible failure and export fallback. | FAIL by design inspection; needs implementation/tests |
| Save / New / History | Save during capture succeeds without stopping it. New finishes/saves A and starts empty B; A remains readable/exportable. No previous notes, transcript, speaker IDs or references reach B unless explicitly retained. Failed saves do not clear A. Test saving-disabled behavior. | FAIL/missing workflow |
| Capture truth | Two-source fixture appears on the correct channels. Permission denial, unplugging input and stream failure become visible; recovery works or clear microphone-only behavior is offered. Stop actually ends capture and saves the tail. | Not validated today |
| AI routing and failure | Local-only mode cannot request cloud models, including through local Ollama. Unknown routing is not labeled private. AI-off stops automatic inference. Invalid credentials, missing model, network loss, in-stream errors and incomplete streams are recoverable and correctly labeled. | Confirmed gaps |
| Summary fidelity | In a synthetic 45–60-minute fixture, seeded decisions/actions from the start, middle and end remain in final context and a reviewed summary. No invented owners/dates in the fixture. Switched/renamed speakers retain correct grounding. | Confirmed context gap |
| GUI | Labeled actions and keyboard equivalents work at 1100×700 and 1440×900 points in light/dark; Settings actions stay reachable. VoiceOver names/focus are usable; long names and long outputs fit. | Fresh native GUI access unavailable during this review |
| Stability | One ≥60-minute real or controlled replay session on the minimum supported Mac; no crash, stuck Stop, missing completed fixture sections, or uncontrolled memory growth. Repeat start/stop and device/network failures. Record resources at 0/15/30/60 min. | Not validated today |
| Build/supply chain | Tests + ≥95% Core coverage + app build pass on the exact reviewed commit; clean resolved dependencies; notices reviewed; effective branch checks verified. | Core passes; other gates outstanding |
| Distribution | Correct Release bundle/version/architecture; signed/notarized/stapled DMG; clean-install and 1.2.1/1.3.0 upgrade check; previous session data preserved; published asset checksum matches verified artifact. | Older candidate packaging passed; hardened artifact not built |

If physical Intel testing is unavailable, do not advertise verified Intel engine support merely because `lipo` shows x86_64. If beta speaker performance/accuracy is not demonstrated, keep it opt-in with accurate limitations, or omit it from the supported release path. These are scope decisions, not substitutes for default-path stability.

## Speaker beta validation and graduation

Today verify no regression when disabled; visibly explain engine compatibility and first-use downloads. Before enabling, show experimental status, processing locality, delay, and microphone/system independence. Speaker work must never delay initial transcript persistence.

Within the next 2–3 days create licensed or explicitly permitted fixtures: two alternating voices; 3–4 voices; overlapping speech; a shared mic; remote plus local channels; English; Mandarin/English code-switching; short answers; silence/noise; and renamed speakers across repeated analysis. Record attribution errors and label churn, not only “the app ran.”

Proposed graduation targets, to agree after a baseline: ≥90% correct attribution on clean non-overlapping labeled utterances; no unexplained named-speaker swaps in the scripted cases; no unbounded backlog; visible uncertainty for overlap; acceptable CPU/RAM and update delay on the minimum supported Mac. Define denominators and publish results by fixture—do not turn a clean-speech score into a general accuracy claim. Word-error/diarization-error metrics can supplement the user-facing outcome measures.

## Follow-up roadmap

| Window | Outcomes | Definition of done |
|---|---|---|
| Next 48–72 hours | Pilot feedback, source timestamps/ordering, speaker processing budgets, engine/device readiness, redacted diagnostics | Each reported failure has a reproducible case; bounded speaker memory/work; timestamp availability is explicit per engine |
| Week 1 | Structured session schema, reopened-session editing, speaker correction, action/decision ledger, per-role cancel and stale-output labels | Names and corrections survive reopen/export; AI claims link to source segments; interruption preserves useful outputs |
| Week 2 | Collapsible setup and tabbed Copilot layout; large-text/keyboard/VoiceOver pass; microphone/app selection | 3–5 pilot users can start, save, start new and retrieve a meeting without explanation; UI fits the supported window sizes |
| Weeks 3–4 | Reliability evidence across supported devices/languages; update notices; support/rollback runbook; retention controls | Published compatibility/quality matrix and a measured beta-graduation decision |
| Later, only after core validation | Optional transcript integrations, semantic search, additional endpoints, meeting detection | Confirmed demand and a clear data-flow/maintenance story; no scope expansion from the stale backlog alone |

## Product success measures

For the pilot, manually record with permission: first successful capture rate/time; recovered finalized-text completeness after interruption; successful Save/New/History workflows; unexplained missing-source incidents; action-owner/date correction rate; model first-response latency by route; speaker-label corrections; crash/hang reports; CPU/RAM trend. Do not add undisclosed telemetry or collect meeting content for analytics by default.

The release succeeds when users can trust that their meeting was captured, saved, retrievable and clearly routed—and can understand the primary controls without guessing from icons.
