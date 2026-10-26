# Publish an iOS build to TestFlight

This is the release runbook for ListenToMe on iPhone/iPad. Follow it when an iOS **release train** is
due — not after every merged fix. Merging a PR, building an archive, or exporting an IPA does **not**
publish the app; equally, a merged iOS change does not by itself call for an upload.

**Cadence.** Publish when a batch of merged iOS work is complete, or when a single user-visible fix
warrants its own build. **At most one TestFlight build per day for trains an agent starts on its own
initiative**, never one per merged pull request. A train the maintainer calls ("publish", "release
what's on `main`", "publish as always") goes out the same day even if a build already went out, and
work the maintainer requested from tester feedback ships on a TestFlight train as soon as it is merged
and its candidate checks pass, without waiting for the next day or asking again. Otherwise, if
today's self-started build has already gone out, the change rides the next train: leave it merged, keep its
`CHANGELOG.md`/release-note entry unreleased, and report it as merged rather than released.
Documentation-only changes never require a new binary, version bump or upload. See
[AGENTS.md](../AGENTS.md) for the full policy and the candidate → verified → published ladder.

When a train is due the maintainer's instruction to release already authorizes the upload; do not ask
again whether to publish. Apple ID authentication and two-factor prompts still belong to the
maintainer.

**A connected iPhone is not required to archive or upload to TestFlight.** Simulator/UI tests and
honestly documented device limitations are sufficient to distribute an authorized beta for device
testing. Physical-device acceptance is still required before calling the app production-ready or
submitting a production App Store release. Missing hardware must not be reported as an upload blocker.

## Fresh US capture package pending submission choice — October 26

The [fresh 1.18.1 capture catalog](images/ios/release-1.18.1-en-US-refresh.json) records 24 native
English (US), US-region images from the exact build-36 artifact source, with four passing native
screenshot tests and complete visual review. These new images are **saved, not uploaded**; no
withdrawal/replacement/resubmission was performed while awaiting the maintainer choice between
resubmitting build 36 and holding for a Watch-enabled build. The existing US review
`89b4c261-b37d-4b24-aaee-20f8238d1663` remains WAITING_FOR_REVIEW at 20:43 UTC.

[Watch preview images](images/watch/1.18.1-preview/README.md) are saved separately. Build 36 has no
embedded Watch app, so these prospective review images must not be added as customer screenshots
for that binary. They establish rendered simulator UI only, not microphone or paired-device
acceptance. See [HANDOFF](HANDOFF.md) for the preserved evidence and exact current state.

## Delivery language — English (US)

Use **English (US), `en-US`**, for new TestFlight and App Store metadata, from
`metadata/ios/en-US/` (maintainer instruction, October 26, 2026). Read back the actual localization
ID, locale, localized app name, description and release notes. English text stored as `en-CA` is
not a US localization. The maintainer-selected English (US) name for this update is **Listen To Me - Real Time AI**.
Apple rejected both older name variants in that locale as already used by another account.

Treat an app's primary locale separately from its localized version metadata. Apple can require
approved localized screenshots before allowing the primary locale to change. Preserve any actual
rejection and report the primary locale honestly; do not claim it changed merely because `en-US`
metadata was created. Historical Canadian receipts below retain their original locale.

For new screenshot captures, select English and US region explicitly (`-testLanguage en -testRegion US`).
Reusing identical English UI images for another localization does not change their original capture
locale: retain that provenance and separately verify the target locale's asset IDs, processing,
native dimensions, order and downloaded pixels. Do not rerun local device testing for the current
submission; the maintainer has already reported working TestFlight testing and requested it stop.

## Speaker-model candidate gate (#310)

A speaker-identification train must include the real-model `SpeakerModelQualityTests` and
`SpeakerStreamingModelTests` in `make mac-test` / `make validate-local`, not only simulator tests
with predefined IDs. Preserve the actual red/green logs and source hashes. The synthetic fixtures
run the production iOS streaming factory on Mac CoreML; physical iPhone/iPad accuracy, latency and
battery acceptance are separate and must be reported when outstanding. Watch imports and Mac live
capture retain the existing offline pipeline; do not claim the iOS live fix changes either one.
Follow [the model acceptance checklist](speaker-identification.md). The original tester recording
remains untested unless retained audio is provided. The beta upload policy above still applies.

## Current English (US) App Review receipt — October 26

Apple accepted the corrected **en-US** submission at **2026-10-26T20:07:35.298432+00:00** under the
maintainer-selected name **Listen To Me - Real Time AI**. Review submission
`89b4c261-b37d-4b24-aaee-20f8238d1663` and version `c60352d3-eb78-479b-970c-d6ed6faa3242` read back
WAITING_FOR_REVIEW. The same accepted **1.18.1 (36)** build/source remains selected; release is
AFTER_APPROVAL. No replacement binary, local device retest or approval/public-availability claim.

The first Canadian review `25ae4878-c462-4528-a48e-01b12b028f39` was canceled and is COMPLETE.
The exact US version localization is `b5e13b58-07ea-40a4-adbb-d013adbb362b`; the US app-info
localization is `57150306-ffc1-4b1b-817e-89e6b3fe63d4`. Name, current US copy, reviewer contact,
exact build and all 24 US images were rechecked before the single corrected review was sent.
Each US screenshot is COMPLETE with native dimensions, checksum, order and downloaded RGB identity
verified. The original source-matched captures were en-CA and are reused for identical English UI;
retain that provenance rather than claiming a fresh US capture.

The app's primary locale remains **en-CA**: Apple's primary-locale PATCH returned HTTP 409
`MISSING_SCREENSHOTS_PRIMARY_LOCALE` even after US image processing completed. The US localization
is submitted, while the Canadian primary/fallback is retained. Do not retry an unchanged rejection,
claim US primary status or edit the approved production version to bypass Apple's requirements.
The [Apple localization rules](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)
explain the distinction and primary-language prerequisites.

Corrected receipts/scripts are in the external `listentome-appstore-publication/locale-us/` directory.
Use the new review ID for status readback; parent-directory receipts describe the canceled first
submission. Maintainer-reported working TestFlight acceptance applies; further local tests and
participant requests remain stopped for this submission. The earlier receipt below is historical.

## Historical Canadian App Review receipt — withdrawn October 26

Apple accepted public submission of **iOS 1.18.1 (36)** at **2026-10-26T19:45:08.361828+00:00**.
Review submission `25ae4878-c462-4528-a48e-01b12b028f39` and version
`c60352d3-eb78-479b-970c-d6ed6faa3242` read back WAITING_FOR_REVIEW. The selected build remains
`2fd8477d-504e-44d2-ac7f-6c7e9236d01f`, accepted from source `7643b20`; no replacement binary or
new TestFlight upload was made. Release is AFTER_APPROVAL. App Review acceptance of the request
does not establish Apple approval or public availability.

For this release, the maintainer reported completed, working TestFlight testing and requested that
further local testing stop. Record that as maintainer-reported acceptance; do not convert it into
agent-verified speaker accuracy, audible playback quality or battery measurements. Do not restart
local device checks or request more test participation for this submission. The general verification
ladder remains applicable to future releases.

All 24 processed screenshots, source checksums/native dimensions/order, current en-CA description
and What's New, selected build and preserved reviewer contact details were rechecked before the
single submission was sent. External evidence is `listentome-appstore-publication/app-review-accepted.json`
and the matching review/version readbacks. That Canadian review was later canceled. Read current US review
`89b4c261-b37d-4b24-aaee-20f8238d1663` in `locale-us/`; do not resume the canceled review.
The preparation section below preserves its earlier incomplete acceptance state.

## Public App Store preparation — October 26

The maintainer requested public distribution of the iPhone/iPad update. The working team API key
created App Store draft **1.18.1** (`c60352d3-eb78-479b-970c-d6ed6faa3242`), selected accepted build **36**
and updated/read back the en-CA description, full What's New since production 1.15.0, support links
and reviewer instructions. Existing review contacts were preserved. Release is set to after approval,
as in the preceding production version. No review submission has been created or sent.

All 24 fresh source-matched screenshots are COMPLETE in `APP_IPHONE_61`, `APP_IPHONE_67`,
`APP_IPAD_PRO_3GEN_11` and `APP_IPAD_PRO_3GEN_129`, six per set, including native landscape views.
Their source checksums, native dimensions, order and downloaded RGB pixels were verified. The five
inherited draft images were backed up and removed only after replacement verification; paginated
before/after reads proved the production 1.15.0 listing unchanged. The only locale is en-CA. Watch
is not embedded and has no screenshot claim; macOS draft/build distribution is separate.

The external `listentome-appstore-publication` evidence directory contains the selected version/build,
immutable inherited-image snapshot/allowlist, upload IDs, processed-image checks, metadata readback,
production preservation and independent review. Resume that same draft and build. Basic attended microphone transcription, Stop and retained Play/Pause controls passed on physical
iPhone 12 Pro Max/iOS 27.0 and iPad Pro 12.9-inch (4th generation)/iPadOS 27.0.1: one test each,
zero failures/skips. The app was a development-signed Release build with product inputs identical to
accepted source `7643b20`, not the installed App Store/TestFlight artifact; audible playback quality
was not separately attested. Speakers, Auto and correction were off. Human speaker and other
remaining affected-device acceptance still hold production submission.

Keep the earlier failures: old transcript text after an interrupted New tap, a human-phrase timeout,
and the iPad runner's on-device XCTest authentication requirement. The updated physical-only harness
requires the empty transcript and no old phrases before Start; it bounds New retries and returns
without opening the microphone on freshness failure. The controlled synthetic phrase played only
after native Listening confirmation. Do not turn either these basic passes or the screenshot/API
checks into a claim that the human speaker gate passed.

## Screenshot capture and App Store handoff (#255)

Capture screenshots during UI acceptance and refresh the complete release set on every iOS train,
from the exact candidate source. Reuse a test capture only when its source and appearance match that
candidate. Keep the source commit, version/build, locale, simulator/device model, OS, orientation,
native pixel dimensions, capture command/test, and SHA-256 of each file in a manifest under
`dist/ios-<version>-build<build>-evidence/screenshots/`. Preserve this directory before archiving a
worktree. Screenshots do not replace physical-device acceptance.

1. Check the candidate's supported device families and the current screenshot slots in App Store
   Connect. Capture **iPhone and iPad**, using native-resolution simulators/devices for every required
   display-size slot. Also inspect compact/large iPhones and compact/large iPads during layout tests;
   this coverage is broader than the store's minimum upload slots. Do not assume a single iPhone
   screenshot covers tablets or every required size. When Watch is embedded in a distributed build,
   add every applicable Watch screenshot category. Do not advertise the unshipped Watch feature.
2. Capture a coherent set: Live transcript/Quick, Summary, Notes/context and prompts when present,
   History, and relevant settings. Include the iPhone landscape two-pane layout and iPad wide layout
   in acceptance evidence; use orientations accepted by each store slot for listing assets. Exercise
   large text separately. Use realistic synthetic examples with no personal transcripts, keys, or
   tester information. Fixture data must depict actual candidate behavior, with no debug/test controls.
3. Export UI-test attachments with `xcrun xcresulttool export attachments --path <result.xcresult>
   --output-path <screenshots-directory>`, or capture a rendered simulator with
   `xcrun simctl io <device-id> screenshot <file.png>`. Inspect every final image at native resolution
   for clipping, stale copy, keyboard/alert overlays and unintended status text. Do not stretch a
   smaller image to satisfy a larger display-size requirement. Refresh README/product images when
   they depict changed screens, while keeping the full release-resolution originals in evidence.
4. Before an **authorized App Store submission**, upload the selected current images to the matching
   app-version localization and device-size screenshot sets. Verify the current Apple requirements
   and the slots shown in App Store Connect at release time rather than relying on a fixed size list.
   Read back every set's order, image dimensions, asset processing state and download URL; download
   and visually compare the processed assets with the intended set. Record screenshot/set IDs and
   sanitized verification responses in the manifest. A local capture or successful binary upload does
   not update listing screenshots. Resolve stale/missing sets before submission.
5. For TestFlight-only trains, prepare and preserve the full fresh set for the next App Store version;
   report listing upload as pending unless it was actually completed. TestFlight upload does not
   itself authorize public App Store submission. If the editable App Store version or upload access
   is unavailable, preserve the set and name that specific blocker, without claiming Apple has it.

## App identity and prerequisites

| Setting | Value |
| --- | --- |
| App Store Connect app | Listen To Me, Apple ID `6811155732` |
| App bundle | `com.tomwu.ListenToMe.ios` |
| Share extension | `com.tomwu.ListenToMe.ios.share` |
| Apple Watch app | `com.tomwu.ListenToMe.ios.watchkitapp` — not shipped until the [#181](https://github.com/tomqwu/ListenToMe/issues/181) train |
| Team | `T32FW7PZ3S` |
| App Group | `group.com.tomwu.ListenToMe.ios` |
| Existing internal testing group | `Dev` |
| Scheme | `ListenToMeIOS` |

Use the full Xcode installation (`xcode-select -p`), XcodeGen, and the configured App Store Connect
team API key for uploads. A usable Xcode account is an alternate credential route. Upload access
requires Account Holder, Admin, App Manager, or Developer permissions. Browser login alone does not
establish Xcode's upload session.
A signing certificate can produce a valid archive/IPA even when upload authentication is broken.

The checked-in export settings are [AppStoreExportOptions.plist](../Config/iOS/AppStoreExportOptions.plist)
for a local distribution IPA and [TestFlightExportOptions.plist](../Config/iOS/TestFlightExportOptions.plist)
for upload. Both use automatic signing, `app-store-connect`, this team, and disable automatic
version/build rewriting. They contain no credentials. Do not depend on plists left in ignored `dist/`
folders by a previous session.

### Persistent API-key authentication for automated uploads

Use the configured **App Store Connect team API key by default**. This route completed the agent's
1.4.0 (11) upload; it is not an untested fallback. Check `~/.config/listentome/testflight.json` and its
referenced key before asking for credentials or Xcode login. An unavailable native/browser automation
connection does not prevent CLI uploads or API verification. This is a different credential path
from Xcode-session lookup; the old session failure need not be repaired to use it.
Apple documents the three `xcodebuild` authentication arguments in
[Distribute apps in Xcode with cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/).

Only if configuration is missing, the one-time maintainer input is a **Key ID**, **Issuer ID**, and the **local path** to the downloaded
`.p8` private key. Never paste the key contents into chat or commit them. Use an existing suitable
team key if available. Otherwise, in App Store Connect → Users and Access → Integrations →
App Store Connect API → Team Keys, generate a key named `ListenToMe Upload` with **Developer** access.
Team keys grant the chosen role across the team's apps; they cannot be restricted to this app.
If API access has not been enabled, the Account Holder must request it first. See
[Apple's key setup instructions](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).

Store the key outside the checkout, for example in `~/.appstoreconnect/private_keys/`, with access
restricted to your user. Store its non-secret references in `~/.config/listentome/testflight.json`:

```json
{
  "key_path": "/absolute/path/to/AuthKey_YOURKEYID.p8",
  "key_id": "YOURKEYID",
  "issuer_id": "YOUR-ISSUER-UUID"
}
```

Replace these placeholders with the actual values. The existing `make ios-testflight` command
automatically passes `-authenticationKeyPath`, `-authenticationKeyID` and
`-authenticationKeyIssuerID` to Xcode. No extra publishing prompt or new app archive is needed.
Alternatively, provide all three environment variables `ASC_KEY_PATH`, `ASC_KEY_ID` and
`ASC_ISSUER_ID`; these take precedence as a complete group. `IOS_ASC_CONFIG` selects a different
JSON file, and `LISTENTOME_CONFIG_DIR` selects a different configuration directory. JSON is read
as data, never sourced as a shell script. Incomplete configuration fails before any upload.

Without a configured key, the helper retains the existing Xcode-session route. Its dry-run reports
the chosen route and validates local configuration only; it does **not** authenticate with Apple.
Offline helper tests prove argument handling and receipt safeguards, not working credentials.
Require a real accepted upload before claiming the API-key path has repaired publishing.

## Credentials and recovery runbook

The iOS upload credentials live on the maintainer's Mac, outside the checkout. **Never commit or
paste a secret value** — not the `.p8` contents, not an Apple ID password, not a JWT. The repo and
`~/.config/listentome/testflight.json` store only non-secret references (paths and IDs).

| Credential | Where it lives | Verify it is present |
|---|---|---|
| The key's non-secret references (`key_path`, `key_id`, `issuer_id`) | `~/.config/listentome/testflight.json`, or the complete `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID` environment group | `python3 -m json.tool ~/.config/listentome/testflight.json` prints all three (none of them is secret) |
| App Store Connect API key (`.p8`) | Outside the checkout, at the `key_path` above — e.g. `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`, readable only by the maintainer | `ls -l` that `key_path`; the file must exist and be readable by your user. Never print its contents |
| The selected route end to end | — | `make ios-testflight IOS_ARCHIVE=<archive> IOS_RELEASE_SOURCE=<commit> IOS_RELEASE_FLAGS=--dry-run` should report route `app_store_connect_api_key` |
| Xcode-session account (fallback route) | Xcode → Settings → Accounts, team `T32FW7PZ3S` with App Store Connect access | The account is listed with that team; browser login alone does not establish it |
| iOS distribution signing | Automatic provisioning via `-allowProvisioningUpdates` against team `T32FW7PZ3S` | A clean `ARCHIVE SUCCEEDED`, then `codesign --verify --deep --strict` in step 3 |

A dry run validates local configuration only. It is never authentication proof — only an upload Apple
accepts is.

When one is missing or rejected:

- **Configuration or key file missing.** Ask only for the specific missing references — **Key ID,
  Issuer ID and the local `.p8` path** — never the key contents and never another manual upload. If
  no suitable key exists, the Account Holder creates one in App Store Connect → Users and Access →
  Integrations → App Store Connect API → Team Keys with **Developer** access, as described above.
- **Apple rejects the configured key** (401/403, `NOT_AUTHORIZED`). Report the sanitized API or
  upload error. The key may be revoked, the API role insufficient, or API access not enabled for the
  team; each needs the maintainer in App Store Connect. Do not rebuild the app to fix an
  authentication failure, and do not repeatedly retry unchanged credentials.
- **`Failed to Use Accounts` on the Xcode-session route.** Check the configured API key first; see
  the troubleshooting section below. Do not delete accounts, reset keychains or rewrite credential
  registries.
- **Any credential unavailable at all.** Stop at candidate. Preserve the source commit/tree, the
  validated archive, the IPA checksum, the selected route, the exact failing command and sanitized
  error, and resume that same unaccepted artifact after recovery. Report the work as merged but not
  published — never as released.

Only the maintainer can perform these, so ask rather than attempting them:

- Accepting the Xcode license: `sudo xcodebuild -license accept` (needs `sudo`).
- Approving Touch ID and keychain-unlock prompts.
- Apple ID sign-in and two-factor codes; creating, revoking or re-downloading App Store Connect API
  keys; enabling API access for the team; and changing a user's App Store Connect role.

The macOS signing, notarization and recovery runbook is in
[RELEASING.md](RELEASING.md#credentials-and-recovery-runbook).

### Repeatable release screenshot capture

Run `-only-testing:ListenToMeIOSUITests/MobileReleaseScreenshotTests` from the candidate source
on dedicated iPhone 17 Pro, iPhone 17 Pro Max, iPad mini (A17 Pro) and iPad Pro 13-inch simulators
(or current supported equivalents). Erase these dedicated simulators before capture so stale
preferences and queued exports cannot add warning banners. The test captures portrait/landscape Live, Prompt, Summary, History and Settings
using synthetic content in the real views. It never sends a model request. Export original PNG
attachments with `xcrun xcresulttool export attachments --path <result.xcresult> --output-path <folder>`.
Inspect every image and record the source, app version/build, simulator/runtime, orientation, native
pixel dimensions and SHA-256 in the release manifest. These are Debug simulator views from candidate
source, not physical-device or Release-binary acceptance. Keep the full originals with release evidence.
XCUIScreen landscape PNGs can store orientation in EXIF while their encoded dimensions remain portrait.
Preserve those originals and make orientation-normalized RGB copies at the same native pixel count;
record both hashes and the transform. Verify the actual upload dimensions and absence of alpha.
Never resize one device capture to impersonate another.

## 1. Identify the exact release and validate it

App Store Connect reported **1.15.0 READY_FOR_SALE** on October 25, 2026. Recheck the production
version each train and prepare App Store “What’s New” from that baseline; the TestFlight version
and the production baseline need not match.

Read `AGENTS.md`, inspect `git status`, and fetch the merged branch. Preserve unrelated work; use a
clean checkout/worktree if needed. Inspect the new PR's code, test evidence, and hosted CI. Reuse
valid evidence for the exact source rather than rerunning tests solely because the agent changed.
Check the changed [BDD scenarios](BDD.md), their actual red/green evidence and any listed manual
acceptance. `make bdd-check` enforces changed behavior/test bindings; `make ios-test` also verifies
that all bound iOS unit/UI tests actually passed in the full run. Native Mac adapter/control and
Watch unit/UI contracts also run locally through `make mac-test` and `make watch-test`; supply a
dedicated `WATCH_DESTINATION=platform=watchOS Simulator,id=<UUID>` for full validation. Neither substitutes for device
acceptance or an Apple upload receipt.
Run missing relevant checks: lint, core coverage, iOS build/UI tests and macOS build. Exercise the
changed user flow locally and inspect its rendered UI; GitHub Actions builds both apps and runs the
headless `ListenToMeCore` unit/integration test suite plus the 95% coverage floor as a CI check; GUI,
audio, device and Ollama-e2e acceptance stay local, run with `make validate-local`.
Credential-dependent tests must be configured locally when relevant. Never place credentials in source, logs, fixtures committed to Git,
or the app bundle. Do not label simulator tests as physical-device validation.

In `project.yml`, keep the app and share extension's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
identical. The `ListenToMeWatch` target keeps the same version and build as the app and share
extension, and every archive runs **without** `WATCH_EMBED` until the
[#181](https://github.com/tomqwu/ListenToMe/issues/181) train: `scripts/ios-testflight.sh` refuses an
archive that contains `ListenToMeIOS.app/Watch/`. Choose a build number not already accepted by App
Store Connect. Update the matching `metadata/ios/en-US/what-to-test-<version>.txt` and `docs/IOS.md`.
Merge source changes after CI passes.

**Third-party notices.** Every SwiftPM package pinned in `Config/Package.resolved` must ship its
license with the binary (#202). The iOS app bundles `App/ThirdPartyNotices.txt` (shared with macOS)
and shows it under **Settings → About → Acknowledgements**; the Apple Watch app and the share
extension link no third-party package. When a release adds, removes or bumps a package — any change
to `Config/Package.resolved` or to a target's `dependencies` in `project.yml` since the last accepted
build — run `make ios-build`, then `python3 -I scripts/generate-third-party-notices.py`, and commit
the regenerated file. `ThirdPartyNoticesTests` (part of `swift test` and the hosted CI check) fails
while a pinned package lacks a notice at its resolved revision, and `MobileAcknowledgementsTests`
fails if the app bundle lacks the file. Before archiving, open **Settings → About →
Acknowledgements** in the simulator build and confirm each new package is listed and opens its license.

Documentation-only follow-ups do not require a new binary. Do not bump the macOS version for an iOS-only release.

## 2. Archive the merged source

Run from the repo root. Set the release values from `project.yml`, not an older chat reply. Check
`echo "${WATCH_EMBED:-unset}"` first: `make gen` inherits an exported `WATCH_EMBED`, and a project
generated with `WATCH_EMBED=YES` embeds the Apple Watch app (`unset WATCH_EMBED` before archiving
until the [#181](https://github.com/tomqwu/ListenToMe/issues/181) train):

```sh
: "${IOS_VERSION:?Set the version from project.yml after checking App Store Connect}"
: "${IOS_BUILD:?Set the unaccepted build number from project.yml}"
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
and `get-task-allow` must be false. Until the [#181](https://github.com/tomqwu/ListenToMe/issues/181)
train, confirm the IPA has no `Payload/ListenToMeIOS.app/Watch/` folder: the Apple Watch app must not
ship yet. Ensure no test credential files or test-only payloads were bundled.
Keep the IPA checksum and verification results with the evidence.

## 4. Upload — this is the publishing step

After the preceding checks, the repeatable repository entry point is:

```sh
make ios-testflight IOS_ARCHIVE="$IOS_ARCHIVE" IOS_RELEASE_SOURCE="$(cat "$IOS_EVIDENCE/source-commit.txt")"
```

Add `IOS_RELEASE_FLAGS=--dry-run` to check archive identity without uploading. The helper checks app/extension
identity and matching versions, requires explicit upload acceptance, records a status receipt, and refuses
an upload already recorded by this helper. It cannot discover previous uploads made outside it: check App
Store Connect and existing logs first. It does not prove archive/source provenance; verify that in step 2.
The raw command below is the Xcode-session diagnostic path; it does **not** read the helper's JSON
configuration. Prefer the helper for normal publishing. An API-key diagnostic command must also
pass the three `-authenticationKey*` arguments from the configured references:

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

Then publish a GitHub pre-release for the tag, with this version's `CHANGELOG.md` section as notes:

```bash
gh release create ios-v<version>-build<build> --verify-tag --prerelease --latest=false \
  --title "ListenToMe iOS <version> (<build>) — TestFlight" --notes-file <notes.md>
```

The release page must be complete on its own (maintainer requirement, 2026-10-24): version and build,
the source commit and upload date, the full user-facing notes for that build, the What to Test steps,
any privacy or data-handling change, and an App Store "What's New" text (≤ 4,000 characters)
covering everything since the last App Store production release, ready to paste.

Start the notes with one line saying it is a TestFlight beta that installs through TestFlight, so no
download is attached. Verify with `gh release view ios-v<version>-build<build>` that it is a
pre-release and that `gh release list` still shows the latest macOS release as Latest. Releases exist
from iOS 1.11.0 (28); earlier iOS builds have tags only.

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
use the authenticated API path below. Missing GUI control alone is not an online-verification blocker.

### API verification when GUI control is unavailable

Authenticate requests to `https://api.appstoreconnect.apple.com` with the configured team key.
Use a short-lived ES256 JWT with `kid` and `typ: JWT` headers and `iss`, `iat`, `exp` and
`aud: appstoreconnect-v1` claims. Keep the JWT and private key in process memory, never in command
arguments, saved evidence or printed output. Use a standard JWT library (the verified local route
used `uv run --with 'PyJWT[crypto]' python ...`). See
[Apple's JWT instructions](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests).

Use the following checks and metadata operations. Build 11 already had automatic Dev access, so
no group-assignment write was needed. Substitute the new build/resource IDs from responses; do
not reuse build 11's IDs for a later release.

| Check/action | API request and evidence |
| --- | --- |
| App identity | `GET /v1/apps/6811155732?fields[apps]=name,bundleId`; require `com.tomwu.ListenToMe.ios`. |
| Duplicate preflight and processing | `GET /v1/builds?filter[app]=6811155732&filter[version]=<BUILD>&include=preReleaseVersion,buildBetaDetail,betaGroups`; check the included marketing version too. |
| Processing complete | Build `processingState=VALID`, `expired=false`, and `buildBetaDetail.internalBuildState=IN_BETA_TESTING`. An accepted upload can take time to appear here; wait without re-uploading. |
| Intended internal audience | `GET /v1/betaGroups?filter[app]=6811155732&include=betaTesters`; select **Dev** with `isInternalGroup=true`, not the separate external group named `dev`. Verify the intended tester's accepted membership and the build/group relationship. |
| Build in Dev | `GET /v1/betaGroups/<GROUP_ID>/builds`; follow pagination. If automatic access already includes the build, do not add a redundant assignment. |
| Missing group assignment | `POST /v1/betaGroups/<GROUP_ID>/relationships/builds` with `{"data":[{"type":"builds","id":"<BUILD_ID>"}]}`; then read back. |
| What to Test | `GET /v1/betaBuildLocalizations?filter[build]=<BUILD_ID>`, then `PATCH /v1/betaBuildLocalizations/<LOCALIZATION_ID>` with that resource's `type`, `id`, and `attributes.whatsNew` from the prepared version file. |
| Beta description | `GET /v1/betaAppLocalizations?filter[app]=6811155732`, then `PATCH /v1/betaAppLocalizations/<LOCALIZATION_ID>` with `attributes.description` from the prepared beta description. Preserve other fields. |

PATCH bodies use `{"data":{"type":"<RESOURCE_TYPE>","id":"<ID>","attributes":{...}}}`.
Select the `en-US` localization; if absent, create it using Apple's resource-specific create endpoint
and required relationships. Read back metadata after writes. Save sanitized resource/status responses
with the release evidence. Never add unrelated testers or enable external/public distribution.

**Reusable verification script.** Historical scripts can hard-code `en-CA`; adapt and inspect their
actual API locale selectors and file paths for `en-US` before a new train. A US metadata file alone
does not change the API localization. Recent releases keep a parameterized script that performs the table
above in their evidence directory: `dist/ios-<version>-build<n>-evidence/asc-verify-script.py` (most
recently `dist/ios-1.16.0-build33-evidence/`). `dist/` is gitignored, so this is local evidence, not
repository source: copy the previous release's script into the new evidence directory and read it
before running it, for example

```sh
uv run --with 'PyJWT[crypto]' python "$IOS_EVIDENCE/asc-verify-script.py" "$IOS_BUILD" \
  "metadata/ios/en-US/what-to-test-${IOS_VERSION}.txt" "$IOS_EVIDENCE/asc-verify.json" \
  metadata/ios/en-US/beta-description.txt > "$IOS_EVIDENCE/asc-verify.log" 2>&1
```

It reads the key references from `~/.config/listentome/testflight.json` and keeps the JWT in memory. It
checks the build up to four times, five minutes apart, and exits 3 if the build is not `VALID` yet —
run it again later; never re-upload. It then checks the internal **Dev** group and its testers, adds
the build to Dev only if it is missing, writes and reads back the en-CA What to Test (and, with the
fourth argument, the beta description), and saves the sanitized record to `asc-verify.json`.

`GET /v1/betaTesters/<TESTER_ID>/builds` lists **individually assigned builds**, not all builds
accessible through a group. In build 11's verified release it returned an old direct assignment;
Dev group access still worked. Do not misdiagnose that response as missing access or create another
testing group. Membership plus the correct build/group state establishes group availability; it does
not prove the tester installed or exercised the new build on a phone.

## Troubleshooting and handoff

### Verified baseline: API key, first proved September 12, 2026

The agent uploaded **1.4.0 (11)** through the repository helper with explicit API-key authentication.
Apple accepted it at **12:12:56 UTC**, then reported `VALID` and `IN_BETA_TESTING`. Dev build access,
the existing tester membership, en-CA description and What to Test were verified through the API.
This completed the automated path without native Organizer control or another manual upload.

- App source/tag: `9e3930844e9872cd252c6222c1d08c617543e8b4`, `ios-v1.4.0-build11` (already accepted).
- Archive: `dist/ListenToMe-ios-1.4.0-build11-release.xcarchive`.
- Receipt and verification: `dist/ios-1.4.0-build11-evidence/upload-accepted.json`,
  `PUBLISH-STATUS.md`, `api-build-current.json`, `api-dev-builds.json` and metadata responses.
- Persistent configuration: `~/.config/listentome/testflight.json`; look up current key references
  there, rather than storing credentials or their values in skills/memory.
- Workflow implementation: [PR #85](https://github.com/tomqwu/ListenToMe/pull/85), merged with all CI
  green; 12 helper tests passed and a real API-key upload proved the route.

The same route has carried every build since. The most recent accepted upload is **1.18.1 (36)**,
accepted on 2026-10-26 at 17:29:24 UTC from `7643b204def6acea0b616a2c2de2bade2fc4c7c9`, tagged
`ios-v1.18.1-build36`. Apple build `2fd8477d-504e-44d2-ac7f-6c7e9236d01f` is `VALID` and
`IN_BETA_TESTING`; Dev access for both existing testers and en-CA metadata were read back.
The [complete GitHub pre-release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.1-build36)
is non-Latest with no binary; macOS `v1.4.4` remains Latest. Evidence is under
`dist/ios-1.18.1-build36-evidence/`, backed up externally under `2026-10-26/listentome-speakers/`.
Twenty-four fresh native screenshots across all four iPhone/iPad categories were inspected and
hashed. Original tester audio and physical accuracy/latency/battery remain unverified; three-person
separation is not established. Watch is excluded, Mac publication remains paused, and App Store
listing upload remains pending. Production 1.15.0 was rechecked before this train.

The preceding combined train **1.18.0 (35)** was
accepted on 2026-10-26 at 12:51:44 UTC from `b1570ad567a43a093294974871d7f0abf1872708`, tagged
`ios-v1.18.0-build35`. Apple build `18ed5ceb-99cc-4658-b07b-3232b0bb23ce` is `VALID` and
`IN_BETA_TESTING`; the existing internal Dev group includes it, both testers have accepted membership,
and en-CA What to Test and beta description match. The [GitHub pre-release](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.0-build35)
has complete notes and remains non-Latest with no binary; macOS `v1.4.4` remains Latest.
Evidence is in `dist/ios-1.18.0-build35-evidence/` of the release worktree, backed up externally under
`listentome-features/combined-train/release/accepted-build35`. Twenty-four inspected source-matched
native screenshots cover all four iPhone/iPad categories; listing upload remains pending. The API-key
archive, export and upload completed without unlocking the Mac. The maintainer explicitly deferred
Mac GUI/OTHERS acceptance for the mixed PR merge and this iOS beta; Mac publication remains paused.
Current-source physical iPhone/iPad acceptance is pending, with no production-ready claim.
App Store Connect reported production **1.15.0 READY_FOR_SALE** at the October 26 preflight; recheck
before the next train. Earlier build-34 and physical-device evidence retains its original provenance.

Use this evidence to distinguish the working path from historical Xcode-session failures. Recheck
live state for a new release; do not treat this historical build number as the next build to upload.
Native GUI automation remained unavailable and physical-device acceptance was not performed for build 11.

### Historical Xcode-session baseline (September 11, 2026)

Build 7 was successfully uploaded by the agent using `xcodebuild -exportArchive` with
`-allowProvisioningUpdates`. Its saved `TestFlightExportOptions.plist` is semantically identical
to `Config/iOS/TestFlightExportOptions.plist`. Build 8 failed at `IDEDistributionUploadAccountStep`
using that same command/settings, while Xcode Settings showed the signed-in Admin team.
The maintainer then uploaded build 8 through Organizer at 2026-09-12 01:32:36 UTC.
Both successful uploads used `DVTServicesSessionProviderCredential`. This establishes a CLI
account-lookup failure, but does not establish its cause or prove that CLI access has recovered.

Local evidence is under `dist/ios-1.3.1-build7-evidence/` and
`dist/ios-1.3.1-build8-evidence/`; the latter contains `upload-accepted.json` for the Organizer
upload. Build 8 is accepted and tagged `ios-v1.3.1-build8`; do not retry it. Tester availability
must still be checked separately. The original IPA checksum predates Organizer's export and must
not be described as a verified checksum of Apple's uploaded payload.

The agent owns the release train end to end, from validated archive through publication. If
Xcode-session lookup fails, check the configured API-key
route first. Native Organizer automation is another fallback when available; do not routinely delegate
the publish click to the maintainer. Report a blocker only for the actual usable routes and preserve
the evidence; a failed GUI connection does not negate working API authentication.
Offline helper tests and dry runs validate safeguards, not live authentication. Do not claim the
publishing workflow is operationally repaired until an agent-operated upload actually succeeds.

- **`Failed to Use Accounts` / `Failed to find an account with App Store Connect access`:** inspect
  the `.xcdistributionlogs` path printed in the upload log, especially `IDEDistribution.standard.log`.
  Compare the credential/provider path with the last successful upload before requesting account changes.
  A browser session or an empty legacy account-list preference alone does not establish the state of
  Xcode team-session credentials. Do not delete accounts, reset keychains, or rewrite credential registries.
  Check Xcode → Settings → Accounts and verify team
  `T32FW7PZ3S` and its App Store Connect access; refresh/sign in only if that account actually needs it.
  Browser login and successful signing are not proof of
  upload access. Ask the user only for the required interactive sign-in/2FA if tools cannot do it.
  Retry the same validated archive after the account state changes; do not repeatedly retry unchanged
  credentials or rebuild to fix an authentication failure. Do not print tokens or reset the keychain.
  If Organizer works but CLI lookup remains broken, configure the explicit team API key above and
  use the same validated archive. Ask for the Key ID, Issuer ID and local `.p8` path, not the private
  key contents or another manual upload. API-key setup is not proof of recovery until Apple accepts
  an agent-operated upload.
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

If blocked, preserve the source commit/tree, archive, IPA checksum, selected authentication route,
exact failing command and sanitized error, remaining action and next command. For example: "the API
configuration references a missing local key file; restore that file, then resume the validated archive."
Do not infer missing account access from an old preference or ask for a phone to repair upload auth.

Apple references: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[distribution workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
[build statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-build-statuses),
[add testers to builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds).
