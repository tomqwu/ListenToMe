# Apple Watch companion (#181)

## Current companion — TestFlight 1.20.3 (43)

Apple accepted **1.20.3 (43)** through the official TestFlight helper at
**2026-10-30T17:10:34.841880+00:00** from `97ef2461b86869405c1d0f4221816b790f0216fd`.
Apple build `fe7d15fb-c6f2-487b-89b6-6f9d26985ccc` is **VALID / IN_BETA_TESTING**.
Readback completed at **2026-10-30T17:16:53.246500+00:00** confirms **en-US**,
**Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for
both existing Dev-group members. Access does not establish physical installation of build 43.

[Publication receipt](releases/ios-1.20.3-build43.json) · [Composite validation](releases/ios-1.20.3-build43-validation.json) · [Release notes and What to Test](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.3-build43).

Physical phone/iPad translation, screen-lock, multilingual and Watch acceptance remains pending.
Public production remains **1.19.1 (39)**; this beta made no public review submission or listing-media
upload. Mac changes remain unreleased, and **v1.4.4** remains GitHub Latest.

## Unreleased phone inbox redelivery repair

On local source `5f52da6a3099778a812ff7ce52793f1312350cc3`, a redelivered Watch chunk no longer
replaces an earlier durable copy when the inbox ledger is missing or corrupt. The phone keeps the
first audio and exact metadata sidecar, returns duplicate, and lets foreground `tidy` recover the
original offsets, duration and final marker. The receive callback still only files bytes; it does
not start audio or transcription. Saving/retention consent and transfer protocol are unchanged.
This repair is **not included in TestFlight 1.20.3 (43)**.

`WATCHINBOX-001` binds the two `WatchInboxRedeliveryTests` methods for missing and corrupt ledgers.
A supplemental macOS Swift package copied `iOS/WatchInbox.swift` and both methods byte-for-byte,
using only local Core. Before the fix, the two methods failed **18 assertions**: deleting the first
64-byte copy before the injected move failure lost the audio and prevented ledger recovery.
After the duplicate guard, the unchanged tests passed **2/2, zero failures/skips**. Both runs were
terminal/reaped within their 600-second bounds (12.292 s red; 10.292 s green), with all 163 pinned
inputs unchanged per run. The raw logs, separate test binaries and source hashes are retained at
`/Users/tomwu/Documents/Codex/2026-10-30/listentome-watch181-focused-review/`;
`independent-portable-red-green-review.json` has SHA-256
`f6ed065e03f9eddaaa802916980288710a133979439cab8c0eb9b8bc248737ab`.

After Xcode setup recovered, the same two bound methods passed in the actual iOS app/test targets
on source `105c91dd1d7b8e2b68dea5a89c0ae7e483e25bcf`: **2 passed, zero failures/skips**, on an
arm64 iPhone 17 Pro / iOS 26.5 simulator. The October 31 **01:32:10–01:33:24 UTC** run preserved
all **1,083** frozen inputs, finished exit 0/reaped, and shut down its owned simulator successfully.
Independent audit re-read the xcresult, checked exact method names and target inclusion, rehashed
34 result files and all six original/preserved app/test payload files, and verified absent owned
process groups. [Sanitized native result and independent audit](evaluations/watch-inbox-redelivery-native-2026-10-30.json).
The green duplicate guard avoids the injected failing move; no move error is claimed during green.
The earlier portable red/green and initial platform blocker remain historical evidence.

Full `make validate-local` subsequently passed on `989a6b4`, integrating main `946cb7e`, on
October 31 **02:56:46–03:45:26 UTC**. Core: **1,294 tests/seven optional skips/98.0768% coverage**;
iOS: **512 unit/seven skips and 101 UI/five skips**; Mac: **120**; Watch: **29 unit and six UI**;
all zero failures. Both redelivery methods passed again with zero skips. The **254-scenario** catalog
validated; all **593 required bound selectors**, **71 helper methods** and **four real local-server
contracts** passed. All **1,109 frozen inputs** and **2,033 original native-result files** matched.
The supervised process reaped and both owned simulators were confirmed Shutdown; the three copied
result bundles' derived SQLite summary caches are recorded separately from the original files.
[Audited full result and source/artifact preservation](evaluations/watch-inbox-redelivery-full-2026-10-31.json).
All three required checks passed on `989a6b4` in [run 41163072169](https://github.com/tomqwu/ListenToMe/actions/runs/41163072169).
PR [#355](https://github.com/tomqwu/ListenToMe/pull/355) remains open for final documentation review/checks
and merge; later docs-only changes do not imply a new full runtime run.

This adds **iOS simulator** filesystem coverage, not physical file-protection, WatchConnectivity
or paired-Watch acceptance. Pairing/reconnection, wrist-down,
low-storage and opt-in retention acceptance remain open; recovering index 2 does not prove
transcription/drain completion while earlier chunks are missing. No visible UI changed, so the
existing README gallery needs link verification rather than unrelated recapture. #181 remains open;
PR merge and publication are not established by these tests or CI.

## Historical TestFlight checkpoint — 1.20.2 (42)

Apple accepted **1.20.2 (42)** through the official TestFlight helper at **2026-10-28T21:11:37.664213+00:00** from `a6b90e83f775cc9dc88df3c2805ecacedca044af`. Apple build `8967f095-470f-40c0-aba0-b1188bbb699c` is **VALID / IN_BETA_TESTING**. Readback at 2026-10-28T21:15:33.796221+00:00 confirms **en-US**, **Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for the existing two-member Dev group. Access does not establish physical installation of build 42.

[Publication receipt](releases/ios-1.20.2-build42.json) · [Release notes and native previews](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.2-build42).

Physical phone translation/lock-screen/multilingual and Watch acceptance remain pending. Public production remains **1.19.1 (39)**; this beta made no new public submission or listing-media upload. Mac changes remain unreleased and keep separate installed-app acceptance gates.

## Public availability — October 28, 2026, 01:12 UTC

Public iOS **1.19.1 (39)** includes the Watch companion. Apple reports READY_FOR_SALE, and its
independent US public lookup reports version 1.19.1 released at **2026-10-28T00:12:55Z**.
The selected Apple build ID and peeled source tag match the previously accepted build 39.
Primary locale remains **en-US**. [Public App Store](https://apps.apple.com/us/app/listen-to-me-real-time-ai/id6811155732)
and [readback receipt](releases/ios-1.19.1-build39-public.json).

Public availability does not prove installation or close the outstanding physical microphone,
paired transfer/reconnection, wrist-down and battery/storage checks. No new upload or release
operation was performed for this status observation. Mac 1.5.0 remains unsubmitted.

## Historical companion — TestFlight 1.20.1 (41)

Apple accepted **1.20.1 (41)** through the official TestFlight helper (receipt recorded 2026-10-28T19:02:09.198475+00:00) from `dc6b2e39a99568fb4931e937c555fa0de0f2ff18`. Apple build `5c2339eb-5e17-4bd6-8eb1-ec1d212ef49f` is **VALID / IN_BETA_TESTING**. Existing Dev group access was verified at 2026-10-28T19:05:58.417288+00:00; its two accepted memberships are unchanged. Primary locale and metadata are **en-US**, with localized name **Listen To Me - Real Time AI**; beta description and What to Test match the intended copy. Group access does not establish physical installation of build 41.

The embedded Watch companion and all three distribution bundles were verified. Install through
TestFlight on the paired iPhone, then use the Watch installation path below if needed. Physical
Watch microphone, paired transfer, wrist-down, battery/storage and phone lock-screen acceptance
remain pending; no production-ready claim follows from package or simulator checks.
[Accepted beta receipt](releases/ios-1.20.1-build41.json) · [Release notes and native previews](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.1-build41).
Public iOS remains 1.19.1 (39); this beta made no new public submission or listing update.

## Historical Watch regression beta — 1.19.1 (39)

At that checkpoint, the Watch companion was in **TestFlight 1.19.1 (39)**. Apple accepted **1.19.1 (39)** from `f1728150e3e66664e36d2506022c2918fa60a53c`: Xcode upload success at **2026-10-27 15:39:29.401 UTC**, Apple uploaded date **2026-10-27 15:40:24 UTC**. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing internal Dev group includes build 39 with two existing active/installed tester members. This does not prove physical installation of build 39. Primary locale, localized name, beta description and What to Test were read back in **en-US**, with name **Listen To Me - Real Time AI**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.1-build39).

Full local validation and independent review passed on unchanged app/test inputs: 125 BDD scenarios; Core 1,239 tests (7 optional skips, 98.249328% coverage); iOS 531 (519 passes, 12 skips); Mac 39; Watch 34; 29 helper tests and four real-server contracts, zero failures. All three required checks passed on exact merged source before upload. The exact transferred IPA was recovered, its full-file transport MD5 matched, its preserved copy SHA-256 matched, and all three distribution signatures/profiles, versions, disabled debugging and no-test-payload checks passed. Complete physical phone/Watch acceptance remains unverified; this is an authorized beta, not a production-ready claim.

**Distribution procedure correction:** an existing private plist with `destination=upload` was passed to direct Xcode export, which uploaded this build. Actual upload was **not** performed by the helper; the later helper dry run is not upload evidence. No duplicate upload was sent. Package verification was completed after acceptance, and the receipt preserves that order. Future local export must use a private copy with `destination=export`; use the official make target for actual upload.

[Current receipt](releases/ios-1.19.1-build39.json) and [fresh native previews](images/watch/1.19.1/README.md). The [1.19.1 draft media receipt](releases/ios-1.19.1-build39-media.json) verifies 60 COMPLETE images across en-US/en-CA, including consistent 422 × 514 Watch screenshots and landscape Duo; native pixels, hashes and order match. Watch/Duo previews are also visible on the beta release page. Public iOS 1.18.1 excludes Watch; the draft has not been submitted.

## Historical first Watch beta — 1.19.0 (38)


The Watch companion is included in **TestFlight 1.19.0 (38)** for the existing Dev group. Apple accepted **1.19.0 (38)** at **2026-10-27T08:31:46.551678+00:00**, from `e43244f752712ac80e179e35c893e967aea38753`. Processing is **VALID**, internal state **IN_BETA_TESTING**, and the existing Dev group includes this build with two accepted testers. Primary locale, localized name, beta description and What to Test were read back in **en-US**. [Complete release notes](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.19.0-build38). Public iOS 1.18.1 and previous beta 1.18.2 (37) do not include it.

The exact uploaded IPA checksum matches ContentDelivery’s file checksum. Its phone, Share and Watch signatures/profiles, versions and debug flags passed verification; Apple’s processed nested entitlements independently confirm the Watch executable and distribution identity. The public buildBundles API lists one APP container and nests the Watch evidence inside it, rather than returning a separate WATCH_APP resource.

Physical Watch installation, microphone capture, paired transfer, wrist-down and battery/storage acceptance remain unverified. This is an authorized beta, not a production-ready claim. Public iOS remains 1.18.1; no new public App Store submission or screenshot listing upload was performed by this train. Mac Store draft #318 stays separate.

The current [repository policy](../AGENTS.md) permits an authorized TestFlight beta with physical
acceptance pending. Older blanket Watch exclusions in the October 22 plan describe earlier release
checkpoints. Physical microphone capture, paired transfer, wrist-down behavior and battery/storage
acceptance remain required for production readiness and a public App Store submission. Simulator
tests and screenshots do not establish those results.

## Intended beta behavior

- Record using the Watch microphone, including with the iPhone disconnected. Wrist-down recording
  uses the declared Watch background-audio mode and visible recording indicator. Phone Start still
  requires active use; in TestFlight 1.20.2 (42), its established user-started recording can continue
  through screen lock with optional AI paused. Physical continuity acceptance remains pending.
- Finished AAC chunks remain local until WatchConnectivity reports successful transfer to the
  paired iPhone. No Watch audio is sent to an AI server. The phone transcribes supported speech
  on-device; optional summary providers retain their existing explicit choices and disclosures.
- iPhone retains playable audio only when **Save audio recordings** is enabled during import.
  Otherwise it deletes temporary audio after saving the text. Existing Retry, Delete and retention
  controls apply. See [privacy](ios-privacy.md).
- Permission, battery and storage readiness are checked before capture. Stop, cancellation and a
  changed readiness state while permission is pending cannot start audio later. An interruption
  waits for explicit Continue; a continued recording keeps its identity and advances its chunk index.
  Leaving the app before Start/Continue finishes cancels that attempt; returning allows a fresh tap.
  Temporary inactivity from system permission UI is allowed. A recording already underway keeps running.
- Failed handoffs preserve audio and durable metadata. Recovery preserves the original final index,
  retries its end marker across relaunch, and accounts for later continued chunks. Duplicate handoffs
  cannot overwrite unacknowledged audio. Failed live/recovery audio remains visibly pending.
- Delete is unavailable to the outbox while recording is active. After Stop, it removes waiting
  audio and recovery intent, so a deleted recording cannot reappear after relaunch.

## Install the Watch companion

For the public version, update ListenToMe to **1.19.1 or later** from the App Store on the paired
iPhone, then install the companion through the iPhone Watch app if it was not installed automatically.
The TestFlight route below remains available for beta builds.

Install the Watch-enabled iOS build from TestFlight on the paired iPhone. In TestFlight, open the
app’s details and find its Watch entry in Information; a compatible companion has its own install
or update action. See [Apple’s TestFlight installation guide](https://testflight.apple.com/).
Automatic companion installation may also apply. For manual installation through the Watch app,
open **My Watch → Apps → Available Apps → ListenToMe → Install**, following
[Apple’s current instructions](https://support.apple.com/en-us/109023). The build must actually
contain the companion; installing older build 37 cannot add it.

The declared minimums are iOS/watchOS 26. A specific Watch model may require a newer watchOS runtime;
Series 12 and Ultra 4 simulator checks use watchOS 27. No physical paired-Watch installation is
claimed by simulator or App Store Connect processing checks.

## Candidate checks and evidence

`RELEASE-003`, `RELEASE-006` and `RELEASE-007` bind the default embedding configuration and explicit
beta-upload safeguards. The helper's `--include-watch-beta` option requires exactly the expected
WatchOS companion, executable/icons, supported deployment target, companion ID and matching
app/Share/Watch versions. Default mode rejects embedded Watch; selecting Watch mode without the
companion also fails. `--dry-run` can be combined with Watch mode and never uploads.

Before upload, inspect the **exported IPA**, not only the separate Watch build: all three bundle
identities and versions, device platform/minimum OS, team/application identifiers, distribution
profiles and expiration, strict signatures, disabled debugging and absence of test payloads. The
phone and Share extension keep their existing App Group. Watch remains non-independent and declares
only its existing background-audio behavior. Use [the release runbook](IOS-RELEASING.md).

`WATCH-001`–`WATCH-014` bind retention, native recorder lifecycle and durable outbox behavior.
`RELEASE-008` adds an explicit DEBUG/simulator-only Record/Stop preview for rendered UI and release
captures. It uses the real controller and views with no microphone input, permission request or
audio files; it is excluded from distribution builds. Those images are simulator fixture evidence,
never proof of physical capture. Native
tests encode/decode real AAC and exercise the actual controllers and filesystem with isolated audio
and transport adapters. Passing baseline adoption is labelled separately from reproduced failures.
These tests cannot prove a real Watch microphone, WatchConnectivity delivery or battery performance.

Focused evidence is preserved at
`/Users/tomwu/Documents/Codex/2026-10-26/listentome-watch181-beta/`. Full `make validate-local` passed on frozen source `016d61c`: 122 BDD scenarios, 1,239 core tests (7 optional skips, 98.2493% coverage), 529 iOS tests (517 passed, 12 optional skips), 39 Mac tests, 33 Watch tests and four real Ollama/OpenAI-compatible contracts; no failures. All three required hosted checks passed on that source. A documentation/media-only follow-up preserves every application and test input; its final CI and merged-source CI remain required.

[Fresh en-US capture catalog](images/ios/release-1.19.0-en-US.json) contains 43 individually inspected native-resolution images: 28 across four iPhone/iPad categories and 15 across Watch Series 12 42/46 mm and Ultra 4 49 mm. Original checksums, RGB equivalence, simulator/test identities and binary/source provenance are preserved externally. Only the approved 46 mm or Ultra Home/Recording images are Watch listing candidates; use one accepted size consistently across locales. The compact 42 mm set and all consent/recovery/offline images are QA only. Offline captures show clock/text overlap and are excluded from listing use. Simulator fixtures do not establish physical microphone or paired transfer acceptance. At the build-38 checkpoint, listing uploads remained pending. At the historical build-39 pre-submission checkpoint, its images had processed in the App Store draft. The version is now public; see the [public availability receipt](releases/ios-1.19.1-build39-public.json).

CI/merge, archive/export, signature/profile checks and accepted-upload/tester readback are complete. [Publication receipt](releases/ios-1.19.0-build38.json) records app source `e43244f` and separately validated uploader source `ea2c05f`. The archive was reused unchanged after the signing-helper fix.

## Physical beta feedback and production acceptance still pending

Check installation on the paired Watch, Record/Stop and audible speech, wrist-down continuity,
interruption followed by Continue, disconnected capture and one-time reconnection sync, pending
Delete, app termination/relaunch and storage/battery limits. On iPhone, verify text order and
timestamps, supported language fallback, summaries and playback with saving on/off. Include the
known long-wait/gap behavior for a recording killed mid-chunk described in the
[design](superpowers/specs/2026-10-22-apple-watch-recording-design.md).

[Current native Watch previews](images/watch/1.19.1/README.md) are captured and inspected beta images; earlier build-36 previews remain historical. Store screenshot publication requires a separately authorized production submission, complete upload processing and readback.

## Build 38 tester regression — October 27

Issue #326 reproduces the opening crash on a physical iPhone 17 Pro Max/iOS 27.0.1.
Three matching production reports and the exact archived dSYM identify `WatchLanguageAudio.samples`
calling `ChunkFeed`, which created `AnalyzerInput` for Float32 waveform analysis. An isolated signed
host with stock AAC reproduced Apple's precondition: audio sample data must be 16-bit signed integers.
The decoder now exposes PCM buffers/timestamps directly for language and speaker analysis; only
file transcription creates Speech inputs in its negotiated format. Source audio is never consumed
by optional analysis. `WATCH-015` covers AAC, bounded windows, bad input and cancellation.

`WATCH-016` reproduces a separate control defect: a false presentation binding finalized capture
without explicit Stop. Active capture now ignores that dismissal and disables interactive dismissal;
Stop remains available on return. Pending Continue can still be cancelled with Done, and actual OS
interruptions require Continue. The simulator controller/return test is separate from physical
wrist-down acceptance. Existing battery/storage start checks and recording safety limits remain;
this fix does not claim indefinite microphone access or uninterrupted OS execution.

Full validation passed on `0020345752a1ace9c28647bf9d45da310f862b18`: 125 BDD scenarios, Core 1,239/7 skips/98.249328%, iOS 531/12 skips, Mac 39, Watch 34 and four real-server contracts, zero failures. Independent source/outcome/media review cleared; [49 fresh images](images/ios/release-1.19.1-en-US.json) include four approved [Watch previews](images/watch/1.19.1/README.md). The remaining Watch frames are QA-only; offline clock overlap excludes those frames from listing use. iOS26.5 simulator and physical 27.0.1 results differ in runtime as well as device.

The candidate merged in #327 and is published as TestFlight 1.19.1 (39); see the receipt above. No production app was reinstalled,
no personal audio was copied, and no microphone/OS permission was reset to investigate.

## Translation after phone import (#330, unreleased)

The Watch does not run translation. After on-device transcription on iPhone, the original imported
text can use the phone's optional live translation. A completed Summary has a separate Translate
summary action. These use installed phone language packs; transfer, recording and retained-audio
consent are unchanged. See [translation](translation.md).

## Unreleased workspace wording

The home action is **Record on Watch**. The separate iPhone remote uses **Start on iPhone** and
**Stop on iPhone**; local capture uses **Stop on Watch**. Offline remote readiness, local microphone
readiness, consent, cancellation and durable transfer retain their existing rules. These wording
changes do not establish physical Watch or paired-device acceptance. Consent uses shorter paragraphs
while retaining agreement, on-device phone transcription and opt-in audio-retention details.
