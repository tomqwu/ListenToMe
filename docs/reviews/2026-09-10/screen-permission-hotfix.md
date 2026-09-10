# Screen Recording status hotfix — 1.3.2 / build 9

## Reproduction

The production 1.3.1 app showed Not set, then Denied after Grant. System Settings showed
two enabled ListenToMe entries. The old resolver treated requesting access plus a negative
CoreGraphics/window-name result as denial, while discarding ScreenCaptureKit errors.

## Change

Negative/inconclusive checks now show Not verified, with Recheck and Open Settings actions.
Recheck uses ScreenCaptureKit directly, coalesces concurrent probes, surfaces failures and
runs only after an explicit Recheck action. Launch and activation refreshes never invoke a
prompt-bearing ScreenCaptureKit query. Once onboarding is completed, launch no longer opens
the Permissions sheet automatically; it remains available from More. A successful probe still shows Granted and clears the relaunch hint.
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
- No capture was started. The user authorized refreshing the existing OS permission; it remains unverified. The detection UI is repaired; effective screen access is not yet restored.
- 1.3.2 has not been published; 1.3.1 remains the public release.

User subsequently confirmed authorization to refresh the existing permission. An attempted Settings action was interrupted by user interaction; no permission change was verified.

## Build 9 installed verification

Signed and notarized build 9 was installed and accepted by Gatekeeper. Native UI launch opens
the main conversation window directly, without the Permissions sheet. Permission-refresh attempts
were interrupted by user interaction, and System Settings subsequently showed an OS update in
progress. No successful permission toggle or restored system-audio access is claimed.

## System-audio repair verified — September 10, 15:55

Authentication completed. Toggling both existing ListenToMe entries off/on, relaunching, and
adding the exact installed app without a reset did not restore capture. With the production app
closed, ran `tccutil reset ScreenCapture com.tomwu.ListenToMe`, then used System Settings →
Screen & System Audio Recording → Add to select `/Applications/ListenToMe.app` by exact path.
The Dev bundle ID was not reset. This repaired effective capture authorization; the precise
internal cause of the inconsistent old authorization record is not established.

On fresh launch, Start listening showed **Mic: active · System: active** without another prompt.
Played a synthetic AIFF through `afplay`; the native transcript displayed **OTHERS This is the
listen to me system audio test.** and **OTHERS The project review is scheduled for Friday.**
The microphone also picked up playback, independently labeled YOU. This demonstrates direct
system-audio transcription, not merely an enabled Settings toggle or microphone pickup.
Stopped capture and observed **Saved at 3:55:02 PM**. No recording remains running from the test.

This supersedes the earlier unresolved authorization notes. The repair was applied to the
installed 1.3.2 build 9 app; no additional binary or public release was created during this repair.
