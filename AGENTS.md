# ListenToMe repository workflow

## Local validation policy

Run all tests on the local Mac using `make validate-local`, including core coverage, iOS simulator
unit/UI tests, release-helper tests and the real Ollama contract. GitHub Actions runs the headless
`ListenToMeCore` unit/integration test suite and the 95% coverage floor as a CI check; GUI,
audio, device and Ollama-e2e acceptance stay local. The main branch ruleset requires the three checks
(`ListenToMeCore tests + coverage`, `macOS 26 app build`, `iOS 26 app build`) and a pull request.
Record local results before merging or publishing.
Installed-app GUI/audio acceptance remains required separately, as the gate on publication.

## Definition of done for fixes and features

A change is done when it is **merged to `main`** with the three required checks green, its relevant
tests written and passing, and every affected doc updated. Publication is a separate, batched step
and is **not** part of a change being done. Do not hold a finished change open waiting for a release,
and do not publish a release merely because a change merged.

1. Implement the change and run relevant tests, lint, coverage, and the app build.
2. Exercise the changed user flow locally and inspect its rendered UI. For audio changes, verify
   actual system-audio transcription labeled OTHERS; a permission toggle or microphone pickup is not
   proof.
3. Update every affected doc, the release notes for the affected platform, and `CHANGELOG.md` under
   that platform's unreleased heading.
4. Commit and push the source, verify hosted CI, and merge the pull request.
5. State in the pull request description what was verified: commands run and outcomes.

Merged work is merged. Until it has actually been published under the rules below, never describe it
as released, shipped, available to users, or on the maintainer's phone. "Merged to `main`, riding the
next release train" is a complete and accurate status report.

## Release trains: when to publish

Publication is batched into release trains. It is not performed once per fix.

- Publish when a batch of merged work is complete, or when a single user-visible fix warrants going
  out on its own.
- **At most one macOS release and at most one TestFlight build per day.** Never one release per
  merged pull request.
- If the day's train for that platform has already departed, the change rides the next one. Leave it
  merged with its changelog entry unreleased and say so; merged-but-unpublished is the expected
  state, not an unfinished task.
- A fix that warrants its own train is one users are actually hitting in a published build: a crash,
  data loss, a broken capture, transcription or model-routing path, or a regression. Refactors,
  tests, and work behind an unfinished feature wait for the next train.
- Documentation-only changes never require a binary release, a version bump or an upload.
- The maintainer may call a train at any time; "release what's on `main`" is a complete instruction.

Publication itself stays authorized: when a train is due, run the workflow below without asking the
maintainer to repeat "publish", including for work merged by another session. An explicit draft,
investigation or local-only request overrides this. OS authentication such as Touch ID and Apple ID
sign-in must be completed by the user. None of this authorizes a public production App Store release.

## The verification ladder: candidate, verified, published

These three words are not interchangeable. Claim only the rung the evidence supports.

- **candidate** — built and verified locally: the artifact exists, relevant tests, lint and the
  required CI checks are green, and signing succeeded. A build with any outstanding gate is a
  candidate. A candidate is not verified and is not published.
- **verified** — installed-app acceptance for the paths the change affects: on macOS, GUI/audio
  acceptance in the installed app; on iOS, physical-device acceptance. A simulator or UI-test run is
  never physical-device acceptance, and a candidate pass is never production acceptance.
- **published** — on macOS, a signed and notarized DMG attached to a GitHub release; on iOS, an
  upload App Store Connect actually accepted. In both cases: the asset downloaded again and its
  checksum compared against the local artifact, and the tag created at the exact source commit that
  produced the artifact.

Rules that hold at every rung:

- Never claim publication without an acceptance receipt — the downloaded DMG's matching SHA-256 on
  macOS, the helper's accepted-upload receipt on iOS. A successful archive, `EXPORT SUCCEEDED`, dry
  run or offline helper test is not an upload.
- An authorized TestFlight beta upload does not require physical-device acceptance, but a build
  without it must never be described as production-ready. Record the missing acceptance; do not omit
  it. Keep it separate from upload blockers: it prevents a production-ready claim, not beta
  distribution.
- Never replace an already-published version's binary.
- If a genuine blocker prevents publication, name the blocker precisely, preserve the candidate and
  its evidence, and report the work as merged but not published. Never describe blocked work as
  released.

## Publishing a macOS release train

1. Choose the exact merged commit to release and confirm the three required checks are green on it.
2. Reach **verified**: install the built app and accept the affected GUI/audio paths.
3. Set the version and release notes, and move the `CHANGELOG.md` entries for this train under the
   new version. Follow `docs/RELEASING.md` for stable production identity, dependency locking,
   signing, notarization and stapling.
4. Publish the signed, notarized production DMG as the latest GitHub release, targeting that exact
   source commit.
5. Download the published asset and verify its checksum and release/tag metadata. Report the release
   link, what was verified, and any remaining material limitations.

`docs/RELEASING.md` also holds the credentials and recovery runbook: where the Developer ID
certificate and the `notarytool` keychain profile live, how to check each one, what to do when one is
missing or rejected, and which steps only the maintainer can perform.

## Publishing an iOS release train

Use the platform-specific build, physical-device acceptance and archive/TestFlight distribution
procedure in `docs/IOS.md` and the runbook in `docs/IOS-RELEASING.md` instead of the macOS DMG steps,
with the checked-in `Config/iOS/` export settings, through actual upload and tester-status
verification. Read `.agents/skills/listentome-testflight/SKILL.md` when starting or resuming that
work. Upload with
`make ios-testflight IOS_ARCHIVE=<validated.xcarchive> IOS_RELEASE_SOURCE=<commit>`.

The verified default credential is the configured App Store Connect API key in
`~/.config/listentome/testflight.json` (successful agent upload: iOS 1.4.0 build 11, September 12,
2026). Check that configuration before requesting login or credentials; `docs/IOS-RELEASING.md` has
the full credentials and recovery runbook. Native GUI automation failure does not block this CLI/API
route. Follow the current repo skill over historical account-failure notes. Xcode account failures
require account recovery, not a new build. A genuine credential/tool blocker must be reported
precisely with preserved evidence; never claim publication without upload acceptance. No connected
iPhone is required for an authorized TestFlight beta upload. Do not call simulator checks a
physical-device pass or publish an unvalidated build as production. A successful archive/export is
not a successful upload.

## macOS permissions

Never reset broad macOS permissions. For the known ScreenCaptureKit -3801 issue, use the targeted
production-app recovery and verification procedure in `docs/manual-smoke-test.md` when authorized.
