# Apple Watch beta preparation (#181)

Current source permanently embeds the Watch companion in the iPhone app. **This work has not been
published.** Latest TestFlight 1.18.2 (37) and public iOS 1.18.1 do not include Watch. The next
Watch-enabled beta must finish validation, review, CI, merge, distribution signing, upload acceptance
and tester readback before it can be installed. See [the current handoff](HANDOFF.md).

The current [repository policy](../AGENTS.md) permits an authorized TestFlight beta with physical
acceptance pending. Older blanket Watch exclusions in the October 22 plan describe earlier release
checkpoints. Physical microphone capture, paired transfer, wrist-down behavior and battery/storage
acceptance remain required for production readiness and a public App Store submission. Simulator
tests and screenshots do not establish those results.

## Intended beta behavior

- Record using the Watch microphone, including with the iPhone disconnected. Wrist-down recording
  uses the declared Watch background-audio mode and visible recording indicator. The iPhone's own
  recorder remains foreground-only.
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

## Installation after the beta is accepted

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

[Fresh en-US capture catalog](images/ios/release-1.19.0-en-US.json) contains 43 individually inspected native-resolution images: 28 across four iPhone/iPad categories and 15 across Watch Series 12 42/46 mm and Ultra 4 49 mm. Original checksums, RGB equivalence, simulator/test identities and binary/source provenance are preserved externally. Only the approved 46 mm or Ultra Home/Recording images are Watch listing candidates; use one accepted size consistently across locales. The compact 42 mm set and all consent/recovery/offline images are QA only. Offline captures show clock/text overlap and are excluded from listing use. Simulator fixtures do not establish physical microphone or paired transfer acceptance. Store screenshot uploads are pending a separately authorized production submission.

Final CI/merge, archive/export, signature/profile checks and accepted-upload/tester receipts remain pending.

## Physical beta feedback and production acceptance still pending

Check installation on the paired Watch, Record/Stop and audible speech, wrist-down continuity,
interruption followed by Continue, disconnected capture and one-time reconnection sync, pending
Delete, app termination/relaunch and storage/battery limits. On iPhone, verify text order and
timestamps, supported language fallback, summaries and playback with saving on/off. Include the
known long-wait/gap behavior for a recording killed mid-chunk described in the
[design](superpowers/specs/2026-10-22-apple-watch-recording-design.md).

[Current native Watch previews](images/watch/1.19.0/README.md) are captured and inspected candidate images; earlier build-36 previews remain historical. Store screenshot publication requires a separately authorized production submission, complete upload processing and readback.
