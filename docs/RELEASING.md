# Releasing ListenToMe

This document describes how the maintainer builds and publishes an official, signed +
**notarized** `.dmg` for ListenToMe.

> **Build and validate the distributable locally.** CI compiles the app on a `macos-26` runner.
> Signing, notarization, GUI, permissions and real-audio acceptance still require a local Mac.
> Use the mandatory gates in [the production roadmap](reviews/2026-09-10/production-roadmap.md).

## Completion policy

Fixes and features include production publication by default, as specified in [AGENTS.md](../AGENTS.md).
A local build, local install, or draft PR is not the end of the workflow. After publishing, download
the hosted asset and compare its SHA-256 against the verified local DMG. Use `--target` with the exact
artifact source commit when creating a release so the tag cannot silently point at another commit.

## Bundle identifiers: release vs. dev

| Configuration | Bundle id | Display name | Signed with |
|---|---|---|---|
| **Release** (the dmg) | `com.tomwu.ListenToMe` | ListenToMe | `Developer ID Application` |
| **Debug** (`make build` / `make run`) | `com.tomwu.ListenToMe.dev` | ListenToMe (Dev) | your local identity (see `signing.local.mk`) |

macOS keys TCC permission grants by bundle id **plus** the binary's code-signing requirement.
A Developer ID signature and an Apple Development signature produce requirements that can never
satisfy each other, so if both builds shared one bundle id, installing either would silently
invalidate the other's Screen Recording / Microphone / Calendar grants — the toggle in System
Settings stays on while capture returns nothing. The split (set in `project.yml` under
`targets.ListenToMe.settings.configs.Debug`) gives each its own row, so a maintainer can keep the
released app installed while developing.

Consequences worth knowing:

- The dev build has its own `UserDefaults` domain, so model choices, presets, and appearance do
  not carry over from the released app. The Keychain service is shared. History is now isolated: Release writes
  `ListenToMe/Conversations`; Debug writes `ListenToMe Dev/Conversations` under Application Support.
  Both import the old `ListenToMe/sessions.json` once; Debug never deletes that production copy.
- **Release verification must use the Release configuration.** `scripts/release.sh` builds
  `-configuration Release` and aborts if that build fails, so the dmg is unaffected — but if you
  ever inspect a build by hand, check the id before concluding anything:
  ```bash
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Volumes/ListenToMe/ListenToMe.app/Contents/Info.plist
  ```
  It must print `com.tomwu.ListenToMe`. A `.dev` suffix means a Debug app got packaged
  (only possible via `ALLOW_DEBUG_PACKAGE=1`) — do not publish it.

## Prerequisites

This project's Apple Developer **Team ID is `T32FW7PZ3S`** (already the default in `scripts/release.sh`
and the `store-credentials` example below, so you don't need to pass it).

- **Apple Developer Program** membership (Team `T32FW7PZ3S`).
- A **"Developer ID Application"** certificate installed in your login keychain. This is the
  identity Gatekeeper requires for distribution outside the App Store — it is *not* the same as
  the "Apple Development" certificate used for local debug builds. Create one at
  <https://developer.apple.com/account/resources/certificates> → **+** → *Developer ID Application*,
  download it, and double-click to install. Verify it exists:
  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```
- Notarization credentials, provided one of two ways:
  - A **`notarytool` keychain profile** (recommended). Create it once:
    ```bash
    xcrun notarytool store-credentials "ListenToMe-Notary" \
      --apple-id "you@example.com" \
      --team-id "T32FW7PZ3S" \
      --password "<app-specific-password>"
    ```
    Generate the app-specific password at <https://appleid.apple.com> → Sign-In and Security.
  - …or the raw **Apple ID / app-specific password** via env vars (`NOTARY_TEAM_ID` defaults to
    `T32FW7PZ3S`).
- Build tooling: `brew install xcodegen` (and optionally `xcbeautify`). `gh` (GitHub CLI) to publish.

## Environment variables read by `scripts/release.sh`

| Variable | Purpose |
|---|---|
| `DEVELOPER_ID_APP` | The `Developer ID Application: …` identity. If set, the app is deep-codesigned with a hardened runtime + secure timestamp before packaging. **If unset, the dmg is built UNSIGNED** (a prominent warning prints; the build is not distributable). |
| `NOTARY_PROFILE` | A `notarytool store-credentials` profile name. If set (and the app was signed), the dmg is submitted for notarization and stapled. |
| `NOTARY_APPLE_ID` | Apple ID email — alternative to `NOTARY_PROFILE`. |
| `NOTARY_PASSWORD` | App-specific password — used with the trio. |
| `NOTARY_TEAM_ID` | Apple Developer Team ID — used with the trio. |
| `ALLOW_DEBUG_PACKAGE` | Set to `1` to fall back to a **Debug** build when the Release build fails (pipeline testing only). The Debug app's bundle id is `com.tomwu.ListenToMe.dev`, so the dmg installs an app the user's existing permission grants no longer apply to. Never publish it. |

Notarization is attempted only when the app was signed (`DEVELOPER_ID_APP` set) **and** either
`NOTARY_PROFILE` or the full `NOTARY_APPLE_ID` + `NOTARY_PASSWORD` + `NOTARY_TEAM_ID` trio is present.

## Build the release

1. Confirm the version. `MARKETING_VERSION` in `project.yml` is the source of truth; the script
   reads it and names the dmg `dist/ListenToMe-<version>.dmg`.

2. Export your credentials and run the release target:
   ```bash
   export DEVELOPER_ID_APP="Developer ID Application: Qiang Wu (T32FW7PZ3S)"
   export NOTARY_PROFILE="ListenToMe-Notary"        # or NOTARY_APPLE_ID + NOTARY_PASSWORD

   make release
   ```

   `make release` runs `scripts/release.sh`, which:
   - runs `make gen` and installs `Config/Package.resolved` into the generated workspace,
   - refuses package versions outside that lock,
   - builds a **Release** `ListenToMe.app` into `.build/release`,
   - deep-codesigns it (if `DEVELOPER_ID_APP` is set),
   - stages the app + an `/Applications` symlink and packages a compressed `.dmg` via `hdiutil`,
   - submits it for notarization and staples the ticket (if notary credentials are set),
   - prints a summary (dmg path, signed?, notarized+stapled?, and the `gh release create` command).

   Without `DEVELOPER_ID_APP`, the script still produces an UNSIGNED dmg so the pipeline is
   testable, but prints a warning that Gatekeeper will block it. Do not publish an unsigned dmg.

3. (Recommended) Verify the notarized dmg passes Gatekeeper:
   ```bash
   spctl -a -t open --context context:primary-signature -vv dist/ListenToMe-<version>.dmg
   xcrun stapler validate dist/ListenToMe-<version>.dmg
   ```

## Publish

The `dist/` artifact is gitignored and is **not** committed. Freeze and verify the exact source commit,
required CI checks, local GUI/audio acceptance, signature, notarization, and checksum first.
Do not infer required-check enforcement merely from a passing CI run; verify the main ruleset targets
`refs/heads/main` and actually requires the named checks. A build with outstanding gates is a candidate.
Never publish an unsigned artifact as a production release. Publish the verified DMG as a GitHub Release:

```bash
gh release create v1.0.0 dist/ListenToMe-1.0.0.dmg \
  --title "ListenToMe 1.0.0" --generate-notes
```

This creates the `v1.0.0` tag, the release, and auto-generated notes, and uploads the dmg.
