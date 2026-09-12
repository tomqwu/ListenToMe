---
name: listentome-testflight
description: Complete ListenToMe iOS fixes and features through validated TestFlight publication, including resumed work and merged PR handoffs. Use for iOS release work in this repository; exclude documentation-only changes and macOS-only releases.
---

# ListenToMe TestFlight completion

The maintainer has standing authorization: after an iOS app fix or feature, validate, merge and
publish the new beta to TestFlight without asking whether to publish. This applies across sessions
and when another session merged the feature. A new request for approval is not part of this workflow.
Respect an explicit instruction to stop at a draft, investigation or local-only result.

Read [the release runbook](../../../docs/IOS-RELEASING.md) from the repository root as
`docs/IOS-RELEASING.md`; use its app identity, checked-in export settings and verification steps.

- Inspect the merged PR and existing evidence before rebuilding. Track the exact release commit,
  app/extension version and build. Never upload an old candidate or an already accepted build.
- Carry the work through relevant local UI/API checks, hosted CI, source merge, signed archive,
  distribution export and verification, actual upload, source tag, processing and tester status.
- Use `make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<commit>` for the
  upload step. It is not a substitute for the preceding validation or subsequent tester checks.
- No connected phone is needed to upload a TestFlight beta. Record unperformed physical-device
  acceptance separately; do not call the beta production-ready without it.
- An exported IPA is not publication. Require explicit upload acceptance. Report processing and
  tester availability separately, with unknown states stated honestly.
- If upload fails, inspect the actual error and compare the last successful credential/provider
  path before asking the user to change anything. An empty legacy preference or browser screenshot
  alone does not diagnose Xcode's team-session credentials. Do not delete accounts or reset credentials.
- Stop retrying unchanged failures. Preserve the archive, checksum, source, sanitized error and exact
  next command. Request only the specific interactive action that tools cannot complete. Resume the
  same validated artifact after recovery; do not ask for publication permission again.

Publication is the default completion condition, not a follow-up offer. Documentation-only workflow
updates do not require another app build. This authorization does not extend to public App Store
production release, unrelated apps, or invitations to additional testers.
