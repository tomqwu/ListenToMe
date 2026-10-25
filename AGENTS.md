# ListenToMe repository workflow

**Current state:** for what is published, what is merged but unreleased, open priorities and pending
maintainer items, read the dated snapshot in [docs/HANDOFF.md](docs/HANDOFF.md). The rules below win
over it.

## Behavior-driven development (all repository work)

Read [docs/BDD.md](docs/BDD.md) before changing behavior. The executable contract catalog is
[`Behaviors/`](Behaviors/). This applies to macOS, iPhone/iPad (including Duo), Watch, shared code,
imports, persistence, privacy, build configuration and delivery tooling, including work already in
progress on older branches when it is integrated.

1. Before implementation, write/update an observable **Given / When / Then** scenario and bind it
   to a concrete native XCTest or Python unittest method. Include unhappy paths, privacy and
   cancellation where relevant. Do not write scenarios that merely describe internal function calls.
2. Run that test and record the expected failure (**red**), implement the smallest change to make
   it pass (**green**), then refactor while keeping it green. For a regression, first reproduce it.
   Never invent a historical red result for existing tests adopted into the catalog.
3. Run `make bdd-check` and the relevant native suites, then the existing validation/acceptance
   gates below. `BDD_BASE` is the actual base for a stacked PR. Test runs and code review must
   establish that assertions prove the stated outcome; structural traceability alone cannot do so.
4. In the PR, identify scenario IDs, red/green commands and outcomes, refactoring, and outstanding
   manual/device acceptance. Use the PR template. Every changed behavior needs an updated scenario
   and an added/changed bound test method; changing a test-file header alone does not qualify.

Finish the current change through validation, review, required CI and merge before opening another
feature PR. Keep future work in GitHub Issues instead of accumulating speculative draft PRs. Work
down the existing draft queue sequentially; consolidate drafts for the same issue while preserving
their commits and evidence.

The BDD gate runs inside the existing required core CI check and `make validate-local`. It never
replaces full test coverage, rendered UI inspection, real OTHERS audio acceptance or physical-device
gates. Documentation-only work needs content/link checks, not an unrelated binary test or release.
The catalog starts with baseline journeys; that is not a claim that every legacy behavior has been
specified or every scenario has just passed. Extend it as each issue is implemented.

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
Every major iOS release includes a validated TestFlight build (maintainer instruction,
2026-10-24); do not finish a major release with only a tag or GitHub release page.

- Publish when a batch of merged work is complete, or when a single user-visible fix warrants going
  out on its own.
- **At most one macOS release and at most one TestFlight build per day, for trains an agent starts
  on its own initiative.** Never one release per merged pull request.
- **A train the maintainer calls goes out the same day**, even if that platform's train already
  departed today. "Publish", "release what's on `main`" and "publish as always" each call a train.
- **Work the maintainer requested from tester feedback ships on a TestFlight train as soon as it is
  merged and its candidate checks pass**, without waiting for the next day or asking again.
  Physical-device acceptance is not required for that beta upload (see the ladder below).
- Otherwise, if the day's self-started train for that platform has already departed, the change
  rides the next one. Leave it merged with its changelog entry unreleased and say so;
  merged-but-unpublished is the expected state, not an unfinished task.
- A fix that warrants its own train is one users are actually hitting in a published build: a crash,
  data loss, a broken capture, transcription or model-routing path, or a regression. Refactors,
  tests, and work behind an unfinished feature wait for the next train.
- Documentation-only changes never require a binary release, a version bump or an upload.
- The maintainer may call a train at any time, including on a day a train already departed;
  "release what's on `main`" is a complete instruction.

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
After the upload is accepted and the `ios-v<version>-build<build>` tag is pushed, publish a GitHub
**pre-release** for that tag: `gh release create ios-v<version>-build<build> --verify-tag --prerelease
--latest=false`, titled `ListenToMe iOS <version> (<build>) — TestFlight`, with that version's
`CHANGELOG.md` section as the notes and no attached binary (iOS installs through TestFlight only).
Never mark an iOS release Latest; the latest macOS DMG release stays Latest.
The release page must be complete on its own (maintainer requirement, 2026-10-24): version and build,
the source commit and upload date, the full user-facing notes for that build, the What to Test steps,
any privacy or data-handling change, and an App Store "What's New" text (≤ 4,000 characters)
covering everything since the last App Store production release, ready to paste.

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

## Release screenshots

During UI testing and every release train, capture fresh screenshots from the candidate source for
all supported device categories. Follow the screenshot checklist in `docs/IOS-RELEASING.md` for iOS.
Preserve native-resolution files and source/version/device provenance with release evidence. Before
an authorized App Store submission, upload the current set to every applicable device-size and locale
slot and read back processing/status; screenshots saved locally are not proof Apple has them. Cover
Watch only when embedded for distribution, and Mac when a Mac release is called. Never publish a
store listing with stale screenshots or claim screenshot publication without upload verification.

## macOS permissions

Never reset broad macOS permissions. For the known ScreenCaptureKit -3801 issue, use the targeted
production-app recovery and verification procedure in `docs/manual-smoke-test.md` when authorized.


## Dev app cleanup after testing

After each completed macOS Dev-app testing session, preserve its screenshots, logs and source/signing
provenance. Check for other running Dev sessions and unsaved work before closing or removing an
app; do not interrupt them. Then close the completed test session's app and move its temporary `.app`
bundles to Trash. Confirm each bundle's `CFBundleIdentifier` is exactly `com.tomwu.ListenToMe.dev`
before removal.

The maintainer authorizes cleanup of the Dev app's permissions after testing (2026-10-24):
`tccutil reset All com.tomwu.ListenToMe.dev`. This is an app-scoped
reset, never a system-wide reset. Do not reset production `com.tomwu.ListenToMe`, other applications,
or the login keychain. Preserve conversation data, settings and API keys. Record cleanup results and
any active-session exception. Perform cleanup at the end of the test session, not between builds or
while an acceptance run is active. See `docs/RELEASING.md` for signing and cleanup details.
