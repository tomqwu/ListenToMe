# Publish an iOS build to TestFlight

This is the release runbook for ListenToMe on iPhone/iPad. Follow it after an iOS fix or feature;
merging a PR, building an archive, or exporting an IPA does **not** publish the app.
The maintainer's instruction to release already authorizes the upload. Do not ask again.

**A connected iPhone is not required to archive or upload to TestFlight.** Simulator/UI tests and
honestly documented device limitations are sufficient to distribute an authorized beta for device
testing. Physical-device acceptance is still required before calling the app production-ready or
submitting a production App Store release. Missing hardware must not be reported as an upload blocker.

## App identity and prerequisites

| Setting | Value |
| --- | --- |
| App Store Connect app | Listen To Me, Apple ID `6811155732` |
| App bundle | `com.tomwu.ListenToMe.ios` |
| Share extension | `com.tomwu.ListenToMe.ios.share` |
| Team | `T32FW7PZ3S` |
| App Group | `group.com.tomwu.ListenToMe.ios` |
| Existing internal testing group | `Dev` |
| Scheme | `ListenToMeIOS` |

Use the full Xcode installation (`xcode-select -p`), XcodeGen, and an Xcode account with App Store
Connect access to this team. The account needs an upload-capable role: Account Holder, Admin,
App Manager, or Developer. Browser login alone does not establish Xcode's upload session.
A signing certificate can produce a valid archive/IPA even when upload authentication is broken.

The checked-in export settings are [AppStoreExportOptions.plist](../Config/iOS/AppStoreExportOptions.plist)
for a local distribution IPA and [TestFlightExportOptions.plist](../Config/iOS/TestFlightExportOptions.plist)
for upload. Both use automatic signing, `app-store-connect`, this team, and disable automatic
version/build rewriting. They contain no credentials. Do not depend on plists left in ignored `dist/`
folders by a previous session.

## 1. Identify the exact release and validate it

Read `AGENTS.md`, inspect `git status`, and fetch the merged branch. Preserve unrelated work; use a
clean checkout/worktree if needed. Inspect the new PR's code, test evidence, and hosted CI. Reuse
valid evidence for the exact source rather than rerunning tests solely because the agent changed.
Run missing relevant checks: lint, core coverage, iOS build/UI tests and macOS build. Exercise the
changed user flow locally and inspect its rendered UI; credential-dependent tests skip on CI and
must be run locally when relevant. Never place credentials in source, logs, fixtures committed to Git,
or the app bundle. Do not label simulator tests as physical-device validation.

In `project.yml`, keep the app and share extension's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
identical. Choose a build number not already accepted by App Store Connect. Update the matching
`metadata/ios/en-CA/what-to-test-<version>.txt` and `docs/IOS.md`. Merge source changes after CI passes.
Documentation-only follow-ups do not require a new binary. Do not bump the macOS version for an iOS-only release.

## 2. Archive the merged source

Run from the repo root. Set the release values from `project.yml`, not an older chat reply:

```sh
IOS_VERSION=1.3.1
IOS_BUILD=8
IOS_RELEASE="ios-${IOS_VERSION}-build${IOS_BUILD}"
IOS_ARCHIVE="dist/ListenToMe-${IOS_RELEASE}.xcarchive"
IOS_EXPORT="dist/${IOS_RELEASE}-export"
IOS_EVIDENCE="dist/${IOS_RELEASE}-evidence"
mkdir -p "$IOS_EVIDENCE"
git rev-parse HEAD > "$IOS_EVIDENCE/source-commit.txt"
git rev-parse 'HEAD^{tree}' > "$IOS_EVIDENCE/source-tree.txt"
make gen
xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$IOS_ARCHIVE" \
  -derivedDataPath .build/ios-release -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates archive > "$IOS_EVIDENCE/archive.log" 2>&1
```

Require exit code zero and `ARCHIVE SUCCEEDED`. Record the actual commit, CI run, test outcomes and
remaining device checks in the evidence directory. Do not overwrite a previously uploaded release.
`make ios-archive` is only a convenience archive target; it is **not** the publication workflow.

An existing archive may be reused if its recorded source and version match the intended release,
its validation passed, and it has not already been uploaded. For a squash merge, compare the recorded
source tree with the merged tree (`git rev-parse '<commit>^{tree}'`), record both commits, and require
an exact match. Rebuild if the source is uncertain or different. Do not upload a stale candidate.

## 3. Export and verify the distribution package

```sh
xcodebuild -exportArchive -archivePath "$IOS_ARCHIVE" -exportPath "$IOS_EXPORT" \
  -exportOptionsPlist Config/iOS/AppStoreExportOptions.plist \
  -allowProvisioningUpdates > "$IOS_EVIDENCE/export.log" 2>&1
shasum -a 256 "$IOS_EXPORT/ListenToMeIOS.ipa" > "$IOS_EVIDENCE/SHA256SUMS"
```

Require `EXPORT SUCCEEDED`. Extract the IPA into a fresh temporary directory with `unzip` or
`ditto -x -k`. Inspect the app and `PlugIns/ListenToMeShare.appex` Info.plists: bundle identifiers,
version/build, and the app's `CFBundleIcons` must be correct. Run `codesign --verify --deep --strict`
on both bundles. Inspect `codesign -d --entitlements :- <bundle>`: both need the App Group above,
and `get-task-allow` must be false. Ensure no test credential files or test-only payloads were bundled.
Keep the IPA checksum and verification results with the evidence.

## 4. Upload — this is the publishing step

```sh
xcodebuild -exportArchive -archivePath "$IOS_ARCHIVE" \
  -exportPath "dist/${IOS_RELEASE}-upload" \
  -exportOptionsPlist Config/iOS/TestFlightExportOptions.plist \
  -allowProvisioningUpdates > "$IOS_EVIDENCE/testflight-upload.log" 2>&1
```

Require a successful exit **and** the upload log's `Upload succeeded` / `Uploaded ListenToMeIOS`.
A local `EXPORT SUCCEEDED` from step 3 is not upload evidence. Apple may then report that the package
is processing; do not claim it is available on the user's phone yet.

After upload, create and push an immutable annotated tag `ios-v<version>-build<build>` pointing at the
recorded release source. Verify the remote tag. Keep iOS tags separate from macOS releases and do
not replace the latest macOS DMG release. Do not tag a failed upload as a released build.

## 5. Confirm availability to testers

Open [this app's TestFlight page](https://appstoreconnect.apple.com/apps/6811155732/testflight/ios).
Wait for processing, resolve any reported compliance requirements using the app's actual behavior,
and apply the prepared What to Test text. Update the beta description when the feature set changes;
repository metadata files do not update App Store Connect automatically.

Confirm the build is assigned to `Dev`, the intended tester is in that group and has accepted the
invitation, and the build is available to that tester. If automatic distribution is not enabled,
assign the processed build explicitly. A group showing a build is not proof that its individual
tester has an available build. External testing is a separate distribution path and may require
TestFlight App Review. Never invite unrelated testers merely to work around a visibility issue.

Report separately: source/CI verified, archive exported, upload accepted, Apple processing completed,
tester availability verified, and physical-device acceptance. If browser/native control is unavailable,
continue the CLI upload and report that online availability/metadata verification remains unverified.

## Troubleshooting and handoff

- **`Failed to Use Accounts` / `Failed to find an account with App Store Connect access`:** inspect
  the `.xcdistributionlogs` path printed in the upload log, especially `IDEDistribution.standard.log`.
  Open Xcode → Settings → Accounts; refresh/sign in to the intended Apple account and verify team
  `T32FW7PZ3S` and its App Store Connect access. Browser login and successful signing are not proof of
  upload access. Ask the user only for the required interactive sign-in/2FA if tools cannot do it.
  Retry the same validated archive after the account state changes; do not repeatedly retry unchanged
  credentials or rebuild to fix an authentication failure. Do not print tokens or reset the keychain.
- **Provisioning or signing errors:** verify bundle IDs, team and App Group entitlements, and automatic
  provisioning access. Report the exact entitlement/profile error; a missing phone is not the generic
  remedy for App Store distribution signing.
- **Duplicate build/version:** check whether the previous upload was accepted or is still processing
  before retrying. If accepted, do not upload it again. For a new artifact, increment both targets'
  build numbers, commit, validate, and archive the new source.
- **Uploaded but absent from TestFlight:** check processing/build status, tester assignment and invitation
  acceptance. Do not confuse upload completion with distribution to testers.
- **No connected device:** publish the authorized TestFlight beta after local checks; record outstanding
  physical-device tests. Stop only the production-readiness claim, not beta distribution.

If blocked, preserve the source commit/tree, archive, IPA checksum, exact failing command and sanitized
error log, remaining action and next command. A useful handoff says "build 8 exported; upload failed
because Xcode has no App Store Connect account for this team; sign in then rerun step 4," not "release
blocked because no iPhone is connected."

Apple references: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[distribution workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
[build statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-build-statuses),
[add testers to builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds).
