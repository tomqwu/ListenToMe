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

## Installed Mac integration

The signed Dev candidate was opened separately. Native screenshots and AX readback retain default,
expanded recording, and expanded model/session/Quick states. Actual language/engine/model values
remain unchanged; all six secondary actions are present. No microphone or AI request was needed
for disclosure acceptance. Component test acceptance and installed integration are distinct evidence.

## Completion gates

Final complete local validation, refreshed gallery/capture manifest, independent review, required
hosted CI and PR merge are recorded in the final validation receipt. Until those are recorded this
is an in-progress change, not merged or published. The README gallery must distinguish these
unreleased images from public and TestFlight builds.

Physical phone/iPad/Watch capture, paired transfer and full VoiceOver-device acceptance remain
separate. No actual OTHERS audio acceptance or production-ready claim follows from this UI pass.
