# Screen Recording status hotfix — 1.3.2 / build 8

## Reproduction

The production 1.3.1 app showed Not set, then Denied after Grant. System Settings showed
two enabled ListenToMe entries. The old resolver treated requesting access plus a negative
CoreGraphics/window-name result as denial, while discarding ScreenCaptureKit errors.

## Change

Negative/inconclusive checks now show Not verified, with Recheck and Open Settings actions.
Recheck uses ScreenCaptureKit directly, coalesces concurrent probes, surfaces failures and
remembers an explicit request across launches so verification can resume after returning from
Settings or restarting. A successful probe still shows Granted and clears the relaunch hint.
No permission reset or security setting changes are included in the fix.

## Validation

- All 13 permission resolver tests pass, including false/inconclusive checks after a request.
- Full Core suite passes; line coverage 96.74%, above the 95% gate.
- Debug app compiles; SwiftLint passes with existing warnings.
- Signed, notarized Release test app installed in `/Applications/ListenToMe.app`; prior 1.3.1
  preserved under `dist/pre-132-install.*`. Gatekeeper accepts it.
- Recheck in the installed app reports `com.apple.ScreenCaptureKit.SCStreamErrorDomain`, -3801.
  This is an OS authorization refusal despite the enabled Settings entries. The app's designated
  signing requirement matches 1.3.1. The cause of the OS/Settings discrepancy is not established.
- No capture was started. Refreshing the existing OS permission requires user confirmation and
  remains pending. The detection UI is repaired; effective screen access is not yet restored.
- 1.3.2 has not been published; 1.3.1 remains the public release.
