# Production review evidence — September 10, 2026

Reviewed source: `3c542e3`, branch `feat/automatic-speakers`, marketing version 1.3.0 / build 6.
Review began around 09:05 America/Toronto. This is an audit, not a production certification.
Application code was not changed during this review.

## Verification performed today

- `./scripts/check-coverage.sh 95`: 215 tests, one expected skipped live Ollama contract test, zero failures. Core line coverage: **97.2365%**. This excludes `App/`, including capture, model loading, persistence, GUI, speaker scheduling, and audio-buffer behavior.
- Synthetic probes against the built Core module reproduced the five observations below. They used synthetic strings and an injected stream, with no microphone, network, credentials, or user-session access.
- Source audit: capture/transcription lifecycle; speaker matching/scheduling; AI context and transport; session persistence/search/export; settings/onboarding; layout/theme/shortcuts; release packaging/CI/dependency handling.
- Inspected repository screenshot `docs/images/screenshot.png`. It shows the **older** four-pane arrangement and does not document the current command-center sidebar. The current layout review uses source and the prior September 9 UI observation; a fresh GUI pass remains required.
- Live GUI inspection failed twice with `Sky Computer Use native pipe startup failed`. No claim of current interactive, small-window, or VoiceOver verification is made.
- Public GitHub REST release query returned latest **v1.2.1**, published September 9, target `081cadf8b4b2e2864857c5166df6ae9014387b84`.
- `git ls-remote` returned `main` at `51ad70324d3a20594fdbbacd4248fb52a38fe9c0`; no remote `feat/automatic-speakers` branch or `v1.3.0` tag was returned. The feature commit is local at review time.
- Authenticated `gh release list` and `gh pr list` returned HTTP 401. Public read endpoints worked; authenticated publishing access remains unverified/unavailable in this session.
- Ruleset `22642939`, named `Main`: `enforcement=active`, empty `conditions.ref_name.include`, only `deletion` and `non_fast_forward` rules. It declares no required pull-request review or status checks. Correct branch targeting and required checks need explicit verification/configuration before treating it as a release gate.
- No tracked `Package.resolved` returned by `git ls-files '*resolved*'`; `.gitignore` excludes `*.xcodeproj` and `.swiftpm/`. App package version ranges are in `project.yml`.
- Existing `dist/ListenToMe-1.3.0.dmg` was built September 9. Prior-turn signing, notarization, and Gatekeeper checks passed. This turn did not rebuild or re-certify it. Those checks establish packaging, not meeting quality.

## Synthetic reproductions

From repository root after the coverage build:

```sh
swiftc -parse-as-library -profile-generate \
  -I .build/arm64-apple-macosx/debug/Modules \
  docs/reviews/2026-09-10/reproduce-gaps.swift \
  .build/arm64-apple-macosx/debug/ListenToMeCore.build/*.o \
  -o /tmp/listentome-review-probes
/tmp/listentome-review-probes
```

The build path is for this Apple Silicon workstation. Adjust for a different build triple. These are observations of current defects, not passing acceptance tests for their fixes.

```text
EARLY_ACTION_ABSENT_FROM_LISTENER_PROMPT=true
SUPPLIED_PRIOR_SUMMARY_IGNORED_BY_LISTENER_BUILDER=true
MIC_FINAL_CLEARS_REMOTE_PARTIAL=true
ARRIVAL_ORDER_DIFFERS_FROM_CAPTURE_ORDER=true
STREAM_ERROR_REPORTED_AS_EMPTY_SUCCESS=true
```

The first two show that an early action leaves the listener prompt's recent 4,000-character window, and even explicitly supplying the prior summary to `PromptContext` does not include it in the listener prompt. They demonstrate missing grounding, not a measured hallucination rate.

## Layout measurements

Computed from the sRGB tokens in `App/Theme.swift`, using relative luminance `(Llighter + .05)/(Ldarker + .05)`:

| Text/background | Contrast |
|---|---:|
| Light tertiary text / window | 2.61:1 |
| Dark tertiary text / window | 3.54:1 |
| Dark tertiary text / card | 3.31:1 |

These tokens are used for small informational labels. They fall below the 4.5:1 normal-text benchmark in [WCAG contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). This is a design benchmark, not a native-app compliance certification or screenshot measurement.

## External checks

- [Ollama cloud documentation](https://docs.ollama.com/cloud): a request to local Ollama can still invoke cloud inference; a local base URL alone does not establish local processing.
- [GitHub macOS 26 runner announcement](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/): macOS 26 runners support Apple Silicon and Intel. The repository's claim that the macOS 26 app cannot be built on hosted runners is outdated; physical audio/TCC testing is still separate.
- [Apple SpeechAnalyzer presentation](https://developer.apple.com/videos/play/wwdc2025/277/): timing attributes are available. The current app requests no timing attributes and emits zero timestamps, so the WhisperKit-only label restriction is an implementation limitation.
- [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): notarization checks for malicious components and is not App Review. It is not proof of capture reliability or speaker accuracy.

## Evidence still required

Fresh GUI verification of the actual Release app; complete two-source audio sessions; device disconnect/sleep/network failures; offline first launch; real speaker attribution accuracy; load/thermal/memory measurements; clean-install and upgrade behavior; actual authenticated release access; execution of new app-build CI on the release commit.
