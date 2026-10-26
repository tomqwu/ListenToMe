---
name: listentome-testflight
description: Publish a ListenToMe iOS release train to TestFlight - validated archive, authenticated upload, tester verification - including resumed work and merged PR handoffs. Use when an iOS release train is due in this repository; publication is batched, not once per merged fix. Exclude documentation-only changes and macOS-only releases.
---

# ListenToMe TestFlight completion

iOS publication runs on **release trains**, not once per fix. A change is done when it is merged to
`main` with the required checks green, its tests passing and its docs updated; the upload is a
separate, batched step. Publish when a batch of merged iOS work is complete, or when a single
user-visible fix warrants its own build — **at most one TestFlight build per day for trains an agent
starts on its own initiative**, never one per merged pull request. A train the maintainer calls
("publish", "release what's on `main`", "publish as always") goes out the same day even if a build
already went out, and work the maintainer requested from tester feedback ships as soon as it is merged
and its candidate checks pass, without waiting for the next day or asking again. Otherwise, if today's
self-started build has already gone out, the change rides the next train: report it as merged and
unreleased rather than uploading again. See [AGENTS.md](../../../AGENTS.md) for the
full policy and the candidate → verified → published ladder.

When a train is due, the maintainer's standing authorization applies: validate, then publish the beta
without asking whether to publish or handing the upload back to the maintainer. This includes resumed
tasks and features merged by another session. Respect an explicit draft or local-only instruction.
This does not authorize a public App Store release or additional testers.

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

Use English (US), `en-US`, and `metadata/ios/en-US/` for new release metadata. Verify the returned
locale and localized app name; English text in an `en-CA` record does not satisfy this requirement.
Historical Canadian receipts below retain their original locale. If Apple blocks a localized name
or a primary-language change, preserve the exact error and distinguish the new localization from
the app's primary locale rather than silently falling back to Canada.

1. Confirm a train is actually due: the maintainer called it, or it is requested tester-feedback
   work that is merged with its candidate checks green, or no TestFlight build has already been
   uploaded today and the merged work is either a complete batch or a user-visible fix that
   warrants its own build. Then
   inspect merged source, version/build, CI and existing evidence before rebuilding. Reuse an archive
   only when its source provenance matches. Check local receipts and App Store Connect for an already
   accepted version/build, including uploads made outside the helper. Never overwrite or re-upload it.
2. Complete relevant local behavior/UI/API checks, CI, signing and distribution-package verification.
   A connected phone is not required for an authorized beta upload. Record physical-device acceptance
   separately; simulator checks do not establish production readiness.
   Capture and inspect fresh, source-matched screenshots for all supported iPhone/iPad categories
   and applicable store-size slots using the runbook's screenshot checklist. Preserve originals and
   provenance in release evidence. Add Watch only when shipped. Before an authorized App Store
   submission, upload and read back the current screenshot sets; a beta upload alone does not update
   store images. Report pending listing uploads explicitly.
3. Run `make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<app-source-commit>`.
   Use the commit that produced the app, not a later workflow/docs-only commit. Require the actual
   accepted-upload receipt, then tag that app source and verify the remote tag. Publish the GitHub
   pre-release for that tag (`--prerelease --latest=false`, CHANGELOG section as notes, no binary) as
   described in `docs/IOS-RELEASING.md`; never make it Latest over the macOS release. The page must be complete: version/build, source
   commit, full notes, What to Test, privacy changes, and App Store "What's New" text since the last
   production release (App Store Connect reported 1.15.0 READY_FOR_SALE on October 25, 2026; recheck each train).
4. Verify processing `VALID`, internal state `IN_BETA_TESTING`, the build's Dev relationship, and the
   intended tester's accepted group membership. Apply and read back the prepared en-US description
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
