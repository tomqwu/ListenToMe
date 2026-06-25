# Releasing ListenToMe

This document describes how the maintainer builds and publishes an official, signed +
**notarized** `.dmg` for ListenToMe.

> **Build locally.** GitHub-hosted runners lack the macOS 26 SDK (and the audio/GUI stack),
> so the app target cannot be built in CI — see the CI note in the README. Releases are built
> on a local Mac with Xcode 26+.

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
   - runs `xcodegen generate`,
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

The `dist/` artifact is gitignored and is **not** committed. Publish it as a GitHub Release:

```bash
gh release create v1.0.0 dist/ListenToMe-1.0.0.dmg \
  --title "ListenToMe 1.0.0" --generate-notes
```

This creates the `v1.0.0` tag, the release, and auto-generated notes, and uploads the dmg.
