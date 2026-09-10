# 1.3.1 / build 7 candidate — implementation and release evidence

Status: **implemented candidate; production publication held**. The design audit remains the
baseline, not a description of current code. The branch `feat/production-hardening` includes the
previous 1.2.1 release fixes, opt-in speaker work, the review, and this hardening increment.

## Delivered behavior

- Large icon-and-text Start/Stop, Save conversation, New conversation, History, Export, and Settings.
  Native menu commands: Cmd-S, Cmd-N, Cmd-F, Cmd-E, Cmd-comma. Tooltips explain the actions.
- Conversation title and readable capture/transcription/AI/save status. Settings scrolls while its
  Save/Cancel actions stay visible. Both audio sources retain independent partial transcription.
- Atomic JSON checkpoint per conversation, including segments, speaker identity/name, notes and
  available AI outputs. Finalized content triggers a checkpoint; a one-second timer captures other
  changes. Save works during recording. Initial persistence does not await speaker or AI processing.
- New, window close and app quit drain transcription before final persistence. Save failures retain
  the conversation and offer retry/export; saving-disabled flows offer Save As, Cancel or discard.
  New clears transcript, partials, notes, AI context/outputs, speaker state, buffers and references.
- Full History detail, copy and Markdown export. Legacy data migrates once. Corruption remains visible
  and intact. Explicit history deletion is confirmed, the silent 200-record cap is removed, and Dev
  writes to its own history directory. Turning autosave off keeps prior history.
- Explicit AI off / local / cloud policy. Local-only checks model metadata before each request and
  rejects unknown/cloud-backed models and redirects. Route/model changes cancel earlier requests.
  Keychain write failures are shown; unchanged keys do not block saving unrelated settings.
- Runtime system-stream failures, microphone configuration changes, queue overflow, model loading,
  transcription failures and unavailable SpeechAnalyzer are visible. Recovery currently requires
  stopping/restarting or choosing another engine; there is no automatic device-switch recovery.
- Listener processes oldest unseen transcript in bounded batches and carries forward the completed
  meeting record. Failed/cancelled work does not acknowledge transcript coverage. In-band model
  errors, premature endings and empty answers fail visibly while retaining partial text.
- Dependency lock in `Config/Package.resolved`, app-build CI on `macos-26`, and bundled third-party
  software notices accessible from More. Version increased to 1.3.1 / build 7.

## Verification completed

| Check | Evidence / result |
|---|---|
| Core suite and coverage | `./scripts/check-coverage.sh 95`: 239 tests, 2 opt-in tests skipped, zero failures; 96.74% line coverage. Archive coverage 100%. |
| App compile | `make build SIGN_FLAGS='CODE_SIGNING_ALLOWED=NO'` passes. Universal Release compilation also passes; this does not verify Intel engine operation. |
| Lint | `make lint` passes with existing size/format/concurrency-related follow-up warnings; no lint errors. |
| Persistence interruption | `python3 scripts/verify-session-recovery.py`: isolated synthetic writer killed with SIGKILL after acknowledged checkpoint; fresh process recovers text, notes, speaker identity and incomplete marker. No user history is touched. |
| Real Ollama streaming | Opt-in `OllamaContractE2ETests`, `qwen3.6:27b-coding-nvfp4`: passes in 70.1 seconds. This is a single request, not a latency benchmark. |
| Real local-only summary | Opt-in `SummaryContractE2ETests`: synthetic 60-minute transcript spanning multiple batches; passes in 182.3 seconds. Output manually inspected below. This is not a one-hour audio stability test. |
| Dependency lock | Build uses `-onlyUsePackageVersionsFromResolvedFile`; generated resolution matches the checked-in lock. |

The synthetic summary retained both decisions (pilot release; postpone budget review) and all three
seeded commitments: Alice — rollout checklist — Wednesday; Bob — cost numbers — Thursday;
Dana — rollback review — Friday. Its output introduced no extra owner or date in this fixture.
This is limited evidence for this model/fixture, not a guarantee against model hallucinations.

## Gaps still open

The original [34-gap matrix](design-and-gap-review.md) remains the scope inventory. Implementation
does not replace final-candidate UI/audio acceptance.

- **G09, G10, G29, G31 distribution gates:** review/merge and hosted CI must pass on the final source;
  effective main review/check enforcement is not established. CLI GitHub authentication is invalid;
  the GitHub connector and SSH remain available for source review. No public release is created here.
  Signed artifact, notarization, clean install/upgrade and published checksum verification remain open.
- **G02/G03/G07/G08/G11/G12/G25 GUI acceptance:** recovery/Core regressions pass; actual native Save,
  New, close/quit, denied-storage fallback, History and keyboard flows still need a rendered run at
  1100×700 and 1440×900 in light/dark, including VoiceOver. Native automation currently reports
  `Sky Computer Use native pipe startup failed`, including after reset.
- **G04/G22/G23/G24/G27/G28:** real two-source capture, denied permissions, device changes, first-run
  downloads and a 60-minute resource/capture soak remain unverified. Status/error reporting is
  improved; input meters, selectors, preflight model readiness and bounded Whisper backlog remain
  follow-up work. No new hardware/engine compatibility claims are made.
- **G05/G06/G18/G19/G21/G26/G33:** summary retention and protocol failures are fixed at the tested
  boundary. A reviewed structured action ledger, source-linked AI claims, typed discovery errors,
  per-role cancel UI, reopened-session editing and per-file reference preview remain future work.
- **G14–G19:** speaker analysis stays experimental and disabled by default. Default Apple timestamps,
  cross-source ordering, windowed speaker processing/memory budgets, attribution accuracy/overlap and
  speaker correction remain unvalidated or deferred. Structured segment names/IDs now persist.
- **G30/G32/G34:** privacy/workflow docs are updated; current screenshots, diagnostics/update UX and
  the larger tabbed layout redesign remain follow-up. Bundled library notices were collected from
  locked checkouts; downloaded model assets need a final inventory in the distributable review.

## Release unblock sequence

1. Unlock/authorize the existing signing key. Both Apple Development and Developer ID signing return
   `errSecInternalComponent` despite the identities being installed. No key access protections were
   changed and no replacement credentials were created.
2. Restore native UI access; validate the workflows and complete the default-engine real audio soak.
3. Finish source review, successful hosted Core/app CI and effective main branch check requirements.
4. Build from the frozen reviewed commit with the existing Developer ID/Notary profile. Verify the
   signed/stapled DMG, clean install/upgrade, then publish and download/check the published checksum.

Until these pass, keep the current public 1.2.1 release as the production download. A candidate build
or a passing Core suite is not a production release.
