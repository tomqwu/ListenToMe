# Unreleased workspace usability refinement

This pass preserves the native visual identity and recording/provider/data behavior while making
reading and the next action clearer. It is separate from a release train.

## User-visible changes

- iPhone populated portrait: transcript receives 46% of the Live panel area, bounded to 200–360
  points; empty conversations keep the smaller preview. Transcript actions groups Select lines,
  speech correction and retained-audio playback, including audio with no recognized speech.
  Enabled correction status and the full transcript reader remain available.
- Summary: Generate/Update are visible words and matching accessible names, with stable role
  identifiers and 44-point touch targets. Existing cancellation and previous-output preservation
  remain. Compact Duo keeps its authored text within the native reader viewports.
- Auto: capability guidance appears before listening even when Auto is off. Unavailable Auto
  cannot be enabled, but a saved enabled preference can be turned off. No provider or saved
  preference is silently changed, and opening controls does not authorize a cloud request.
- More groups Conversation, Share and export, and App. Notes, prompts & files opens the existing
  Notes sheet; its Ask AI section names the prompt tools. Existing shortcuts remain.
- Mac: recording settings, AI models and session details start collapsed in native disclosures.
  Answer and recap remain directly visible; six secondary Quick actions expand together.
  The existing 1,100-point minimum window width and transcript/prompt split are retained.
- Watch: Record on Watch, Stop on Watch, Start on iPhone and Stop on iPhone identify the recording
  device. Consent retains agreement, on-device phone transcription and audio-retention disclosures
  in shorter paragraphs. Readiness, Stop, offline transfer and cancellation are unchanged.

## BDD and regression evidence

`Behaviors/workspace-usability.json` binds `UX-001`–`UX-006` to native iOS unit/UI, Mac native
and Watch UI methods. The native Mac test hosts actual `ConversationLanguageControls`, uses
native pointer events to open the disclosure, and checks unchanged choices, zero saves and no
translation work. It does not claim to test the full app or invoke an AI provider.

Evidence is retained under
`/Users/tomwu/Documents/Codex/2026-10-30/listentome-gui-refinement/`:

- `ios-red`: all four new cases failed against the incumbent mobile UI. Observed failures include
  the idle Auto promise, 0.3395 transcript-panel share, icon-only action, 42-point target and absent
  named tools. This is real red evidence, not historical adoption.
- `watch-red`: the new device-named local action was absent before implementation.
- `mac-red`: an extracted incumbent always-visible section failed collapsed-height and native
  disclosure assertions. This was a behavior-preserving extraction for the test; it is not a claim
  that a previously existing Mac scenario failed.
- `ios-green`, `watch-green`, `mac-green`: initial focused passes. Source review then identified
  mismatched accessible action naming and notes-only retained-audio playback loss.
- `review-red`: both review findings reproduced before their fixes.
- `review-green`: retained-audio and correction journeys passed, but the existing clean Duo
  screenshot test caught Quick text extending below its reader. This attempt remains failed.
  `duo-failed-MobileWorkspaceView.swift` preserves that production input. The fix keeps a 44-point
  button while removing excess internal height; no preview content or viewport assertion is cut.
- `mac-content-green`: the strengthened real-control native disclosure case passed.
- `watch-final-green`: device-named controls, shorter consent, recording Stop and dismissal/
  background-return journeys passed on the dedicated 46 mm watchOS 27 simulator.

- `copy-selector-red`: the provider-copy assertion failed; its initial sheet-action assertion
  accidentally matched the obscured workspace action and therefore is not a valid sheet red.
  `sheet-selector-red` uses distinct full-reader identifiers and genuinely fails both the empty
  reader and populated reader checks. The subsequent fix gives the reader its own stable identifiers
  and includes cloud/custom providers in the capability explanation.

- The first `make validate-local` stopped at lint: the added existence assertion pushed
  `MobileAppTests` one line over its existing type-size limit. The journey moved into the usability
  suite and all BDD bindings followed it; no lint suppression was added. That aggregate attempt did
  not reach coverage or native stages and remains failed. Compact Update assertions now explicitly
  check its accessible name and target alongside complete Duo text.

- The next full aggregate passed the core suite/coverage and reached native iOS, where the legacy
  Auto-persistence journey tried to enable an unavailable provider. That genuine failed assertion
  exposed an outdated test setup. The journey now uses the existing supported-provider fixture;
  unavailable-provider refusal remains independently asserted. The failed aggregate was interrupted
  after the recorded failure and is not counted as complete local validation.

- The third aggregate caught a genuine portrait regression: the complete automatic-summary error
  ended six points below its Quick panel. `error-priority-red` reproduced the existing clipping
  assertion and a new assertion that errors precede optional Status details. The correction moves
  only that diagnostic button below the error, preserving transcript allocation and retry behavior.
  This interrupted aggregate remains failed; final completion is recorded in PR #353.

## Installed Mac integration

The signed Dev candidate was opened separately. Native screenshots and AX readback retain default,
expanded recording, and expanded model/session/Quick states. Actual language/engine/model values
remain unchanged; all six secondary actions are present. No microphone or AI request was needed
for disclosure acceptance. Component test acceptance and installed integration are distinct evidence.

## Validation and delivery record

[PR #353](https://github.com/tomqwu/ListenToMe/pull/353) records final commands, complete local-gate
outcomes, independent review, required hosted CI and merge status. The complete gate is
`make validate-local` with the owned iPhone and Watch simulator destinations; raw output and native
result bundles remain in the evidence directory above. The third run used `978caac` with byte-identical app/test/config inputs through `9179753`.
The error-priority correction has its own final source, focused red/green and complete-gate receipt
in the PR. Retained frozen-input manifests permit exact comparisons; earlier failed and interrupted
attempts remain distinct.

[Capture manifest](images/workspace/unreleased-2026-10-30/manifest.json) catalogs 45 simulator
captures across seven device profiles, plus the selected native Mac workspace/options images.
Nine approved native-resolution gallery assets preserve original hashes and EXIF-normalized RGB
identity. The earlier Pro Live portrait and scrolled setup/consent captures remain QA-only; the Pro
Max Live portrait, Pro full reader and clean Duo are selected. GFM-rendered gallery previews were
inspected at 1,000 and 375 pixels: all seven inline images loaded and neither content width overflowed.
Full-resolution links expose the other two selected Mac/options and iPad-mini assets. Historical
galleries remain collapsed and all previews are labelled unreleased. Live fixtures inject synthetic
summaries/Auto; normal Apple Intelligence remains manual-only. The later error-priority fix changes
only error-present rendering: all selected gallery states have no error and emit the same visible
children in the same order. This is conditional render equivalence, not byte-identical app source.

The completed installed Dev session was closed. Its strict-verified signed app, screenshots, AX
readbacks and source/signing provenance were preserved; the exact `.dev` bundle was moved to Trash
after checking no ListenToMe process remained. Only `com.tomwu.ListenToMe.dev` permissions were
reset (exit 0). FinderInfo on the owned app/resource-bundle roots was removed before strict archive
verification; signed files were unchanged. Other apps, production permissions, conversations,
settings and credentials were preserved.

Physical phone/iPad/Watch capture, paired transfer and full VoiceOver-device acceptance remain
separate. No actual OTHERS audio acceptance, production-ready claim or publication follows from
this UI pass; merged work rides the next appropriate release train.
