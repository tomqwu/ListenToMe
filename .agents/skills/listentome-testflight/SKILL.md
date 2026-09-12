---
name: listentome-testflight
description: Complete ListenToMe iOS fixes and features through validated TestFlight publication, including resumed work and merged PR handoffs. Use for iOS release work in this repository; exclude documentation-only changes and macOS-only releases.
---

# ListenToMe TestFlight completion

The maintainer has standing authorization: after an iOS app fix or feature, validate, merge and
publish the beta without asking whether to publish or handing the upload back to the maintainer.
This includes resumed tasks and features merged by another session. Respect an explicit draft or
local-only instruction. This does not authorize a public App Store release or additional testers.

Read [the release runbook](../../../docs/IOS-RELEASING.md) for artifact validation, authentication,
API status checks and metadata updates. Use this repository's current procedure over older notes
that describe the CLI as blocked or require another publication approval.

## Start with the working authentication path

- **Verified baseline:** the agent uploaded **1.4.0 (11)** on **2026-09-12 at 12:12:56 UTC** using
  `make ios-testflight` with an App Store Connect team API key. Apple processing, Dev access and
  en-CA metadata were verified. This is a completed release, not a candidate to upload again.
  Evidence: `dist/ios-1.4.0-build11-evidence/upload-accepted.json`; workflow implementation: PR #85.
- Check `~/.config/listentome/testflight.json` and its referenced local `.p8` before asking for
  credentials, account login, app identifiers or a new key. The helper also supports `IOS_ASC_CONFIG`,
  `LISTENTOME_CONFIG_DIR` and the complete `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID` environment group.
  Keep key contents out of chat, logs, Git and persistent memory notes; the local configuration supplies the references.
- **Prefer the configured API key from the start.** Do not deliberately retry Xcode-session account
  lookup first. A helper dry-run should report `app_store_connect_api_key` when this configuration is
  present; it validates local inputs only and is never upload/authentication proof.
- A failed native automation connection affects GUI control. It does not block the working CLI/API
  path. Use authenticated App Store Connect API requests for processing, group access and metadata
  when browser/native control is unavailable; the runbook lists the verified endpoints.

## Complete the release

1. Inspect merged source, version/build, CI and existing evidence before rebuilding. Reuse an archive
   only when its source provenance matches. Check local receipts and App Store Connect for an already
   accepted version/build, including uploads made outside the helper. Never overwrite or re-upload it.
2. Complete relevant local behavior/UI/API checks, CI, signing and distribution-package verification.
   A connected phone is not required for an authorized beta upload. Record physical-device acceptance
   separately; simulator checks do not establish production readiness.
3. Run `make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<app-source-commit>`.
   Use the commit that produced the app, not a later workflow/docs-only commit. Require the actual
   accepted-upload receipt, then tag that app source and verify the remote tag.
4. Verify processing `VALID`, internal state `IN_BETA_TESTING`, the build's Dev relationship, and the
   intended tester's accepted group membership. Apply and read back the prepared en-CA description
   and What to Test. `/betaTesters/{id}/builds` lists **individual assignments only**; absence there
   does not disprove access through Dev. Do not claim a physical installation was observed.
5. Report upload, processing and tester access from evidence. Archive/export, dry-run and offline
   helper tests alone are not publication. Preserve the source, receipt, verification and any genuine
   remaining blocker so another session can resume without repeating completed work.

## If authentication fails

Inspect the actual error and selected route. `Failed to Use Accounts` was the old Xcode-session
lookup failure; an enabled account or empty legacy preference alone does not diagnose its cause.
If the helper unexpectedly selected that route, inspect missing/overridden API configuration first.
Do not reset accounts/keychains, rebuild the app to fix authentication, or repeat unchanged failures.

Only when a required credential reference/file is genuinely missing, request the **Key ID, Issuer ID
and local `.p8` path** that are missing. Check the user-specified folder for the downloaded key; an
app's numeric Apple ID, bundle ID and SKU are not API credentials. If Apple rejects the configured
key, report the sanitized API/upload error and ask only for the specific recovery action that tools
cannot complete. Resume the same validated, unaccepted artifact after recovery. GUI fallback remains
optional when available; do not routinely ask the maintainer to publish manually.

Documentation-only skill/runbook updates do not require a new binary, version bump or TestFlight upload.
