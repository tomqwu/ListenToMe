# ListenToMe repository workflow

## Standing iOS release instruction

Every iOS app fix or feature includes TestFlight publication by default, including work merged by
another session. Do not ask the maintainer to repeat "publish" or offer publication as optional
follow-up work. Read `.agents/skills/listentome-testflight/SKILL.md` and `docs/IOS-RELEASING.md` when
starting or resuming that work. An explicit draft/local-only request overrides this default.
Use `make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<commit>` for upload.
The verified default is the configured App Store Connect API key in
`~/.config/listentome/testflight.json` (successful agent upload: iOS 1.4.0 build 11, September 12, 2026).
Check that configuration before requesting login or credentials. Native GUI automation failure does
not block this CLI/API route. Follow the current repo skill over historical account-failure notes.
A genuine credential/tool blocker must be reported precisely with preserved evidence; never claim
publication without upload acceptance. This does not authorize a public production App Store release.

## Definition of done for fixes and features

The maintainer expects fixes and features to be released, not left at a local build or install.
Unless the user explicitly requests a draft, investigation, or local-only change, complete the
release workflow without asking again whether to publish:

1. Implement the change and run relevant tests, lint, coverage, and the app build.
2. Verify affected behavior in the installed production app. For audio changes, verify actual
   system-audio transcription labeled OTHERS; a permission toggle or microphone pickup is not proof.
3. Update version/build numbers and release notes. Follow `docs/RELEASING.md` for stable production
   identity, dependency locking, signing, notarization, and stapling.
4. Commit and push the source, verify hosted CI, and complete the release PR/merge workflow.
5. Publish the signed, notarized production DMG as the latest GitHub release, targeting the exact
   source commit used for the artifact. Never replace an already-published version's binary.
6. Download the published asset and verify its checksum and release/tag metadata. Report the
   release link, verification, and any remaining material limitations.

Documentation-only changes do not require a new binary release. If an actual blocker prevents
publication, name the blocker and preserve the candidate/evidence; do not describe the work as
released. Existing user authorization persists across turns. OS authentication such as Touch ID
must be completed by the user, but do not request publication approval again for authorized work.

Never reset broad macOS permissions. For the known ScreenCaptureKit -3801 issue, use the targeted
production-app recovery and verification procedure in `docs/manual-smoke-test.md` when authorized.

For iOS-only changes, use the platform-specific build, physical-device acceptance and
archive/TestFlight distribution procedure in `docs/IOS.md` instead of the macOS DMG steps.
Do not call simulator checks a physical-device pass or publish an unvalidated build as production.

For every iOS publication, follow `docs/IOS-RELEASING.md` and the checked-in `Config/iOS/` export
settings through actual upload and tester-status verification. No connected iPhone is required for
an authorized TestFlight beta upload. Keep missing physical-device acceptance separate from upload
blockers; it prevents a production-ready claim, not beta distribution. A successful archive/export
is not a successful upload. Xcode account failures require account recovery, not a new build.
