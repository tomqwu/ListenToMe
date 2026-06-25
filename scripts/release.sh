#!/usr/bin/env bash
#
# release.sh — Build, (optionally) sign + notarize, and package ListenToMe as a .dmg.
#
# This script builds a Release ListenToMe.app, stages it with an /Applications symlink,
# and packages a compressed .dmg into dist/ListenToMe-<version>.dmg.
#
# Signing and notarization are CONDITIONAL on environment variables so the pipeline is
# runnable/testable without Apple Developer credentials (it degrades to an UNSIGNED dmg
# with a prominent warning). See docs/RELEASING.md for the full maintainer workflow.
#
# Env vars (all optional):
#   DEVELOPER_ID_APP  - "Developer ID Application: …" identity used to deep-codesign the
#                       app with a hardened runtime + secure timestamp before packaging.
#                       If unset, the dmg is built UNSIGNED (not distributable).
#
#   Notarization (only attempted if the app was signed). Provide EITHER:
#     NOTARY_PROFILE   - a `xcrun notarytool store-credentials` profile name
#   OR the trio:
#     NOTARY_APPLE_ID  - Apple ID email
#     NOTARY_PASSWORD  - app-specific password
#     NOTARY_TEAM_ID   - Apple Developer Team ID
#
set -euo pipefail

# --- locate repo root (script lives in scripts/) ---------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="ListenToMe"
VOLNAME="ListenToMe"
SCHEME="ListenToMe"
PROJECT="ListenToMe.xcodeproj"
DERIVED="${REPO_ROOT}/.build/release"
DIST_DIR="${REPO_ROOT}/dist"

# --- read MARKETING_VERSION from project.yml -------------------------------------------
VERSION="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)"
if [[ -z "${VERSION}" ]]; then
  echo "release: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi
echo "==> Releasing ${APP_NAME} ${VERSION}"

DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

# --- regenerate the Xcode project ------------------------------------------------------
echo "==> xcodegen generate"
xcodegen generate

# --- build a Release .app --------------------------------------------------------------
USED_CONFIG="Release"
build_config() {
  local config="$1"
  echo "==> xcodebuild (${config})"
  # `-destination generic/platform=macOS` builds for the platform, not the host architecture, so the
  # released app isn't accidentally arm64-only on an Apple Silicon release machine.
  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
      -configuration "${config}" -destination 'generic/platform=macOS' \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      -derivedDataPath "${DERIVED}" build | xcbeautify
  else
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
      -configuration "${config}" -destination 'generic/platform=macOS' \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      -derivedDataPath "${DERIVED}" build
  fi
}

if ! build_config "Release"; then
  if [[ "${ALLOW_DEBUG_PACKAGE:-0}" == "1" ]]; then
    echo "release: WARNING — Release build failed; ALLOW_DEBUG_PACKAGE=1, packaging DEBUG (testing only)." >&2
    USED_CONFIG="Debug"
    build_config "Debug"
  else
    echo "release: Release-configuration build failed — aborting so an official dmg is never built" >&2
    echo "release: from a Debug app. Set ALLOW_DEBUG_PACKAGE=1 only to test the pipeline." >&2
    exit 1
  fi
fi

# --- locate the built app --------------------------------------------------------------
APP_PATH="${DERIVED}/Build/Products/${USED_CONFIG}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  # Fall back to a search in case the products dir differs.
  APP_PATH="$(find "${DERIVED}/Build/Products" -maxdepth 2 -name "${APP_NAME}.app" -type d 2>/dev/null | head -1 || true)"
fi
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "release: could not locate built ${APP_NAME}.app under ${DERIVED}/Build/Products" >&2
  exit 1
fi
echo "==> Built app: ${APP_PATH}"

# --- conditional code signing ----------------------------------------------------------
SIGNED="no"
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "==> Code signing (hardened runtime) with: ${DEVELOPER_ID_APP}"
  # Sign nested code (embedded frameworks/dylibs, e.g. WhisperKit's) inside-out FIRST, without the
  # app entitlements — frameworks must not carry the app's entitlements.
  if [[ -d "${APP_PATH}/Contents/Frameworks" ]]; then
    find "${APP_PATH}/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) -print0 \
      | while IFS= read -r -d '' nested; do
          codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APP}" "${nested}"
        done
  fi
  # Sign the outer app bundle LAST, WITH the release entitlements, so the notarized build keeps the
  # microphone entitlement (com.apple.security.device.audio-input). Not --deep (would re-sign nested
  # with the app's entitlements).
  codesign --force --options runtime --timestamp \
    --entitlements "App/ListenToMe.entitlements" \
    --sign "${DEVELOPER_ID_APP}" "${APP_PATH}"
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
  SIGNED="yes"
else
  echo ""
  echo "############################################################################"
  echo "# WARNING: DEVELOPER_ID_APP is not set.                                     #"
  echo "# The resulting .dmg will be UNSIGNED and NOT notarized.                    #"
  echo "# Gatekeeper WILL block it on other Macs — this build is NOT distributable. #"
  echo "# Set DEVELOPER_ID_APP (and notary credentials) for a real release.         #"
  echo "# See docs/RELEASING.md.                                                    #"
  echo "############################################################################"
  echo ""
fi

# --- package the .dmg ------------------------------------------------------------------
echo "==> Packaging dmg"
mkdir -p "${DIST_DIR}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

# Stage the app + an /Applications symlink for drag-to-install.
cp -R "${APP_PATH}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

rm -f "${DMG_PATH}"
hdiutil create -volname "${VOLNAME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG_PATH}"

# Sign the dmg container itself (hdiutil produces an unsigned dmg) so its primary signature is valid
# before notarization, matching docs/RELEASING.md's verification step.
if [[ "${SIGNED}" == "yes" ]]; then
  echo "==> Signing the dmg container"
  codesign --force --timestamp --sign "${DEVELOPER_ID_APP}" "${DMG_PATH}"
fi

# --- conditional notarization + stapling -----------------------------------------------
NOTARIZED="no"
if [[ "${SIGNED}" == "yes" ]]; then
  NOTARY_ARGS=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
  elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    NOTARY_ARGS=(--apple-id "${NOTARY_APPLE_ID}" --password "${NOTARY_PASSWORD}" --team-id "${NOTARY_TEAM_ID}")
  fi

  if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    echo "==> Submitting for notarization (this can take a few minutes)"
    xcrun notarytool submit "${DMG_PATH}" "${NOTARY_ARGS[@]}" --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "${DMG_PATH}"
    NOTARIZED="yes"
  else
    echo "release: app is signed but no notary credentials provided" >&2
    echo "release: set NOTARY_PROFILE or NOTARY_APPLE_ID/NOTARY_PASSWORD/NOTARY_TEAM_ID to notarize." >&2
  fi
fi

# --- final summary ---------------------------------------------------------------------
DMG_SIZE="$(du -h "${DMG_PATH}" | awk '{print $1}')"
echo ""
echo "========================================================================"
echo " ${APP_NAME} ${VERSION} — release summary"
echo "------------------------------------------------------------------------"
echo " dmg path  : ${DMG_PATH}"
echo " dmg size  : ${DMG_SIZE}"
echo " build cfg : ${USED_CONFIG}"
echo " signed    : ${SIGNED}"
echo " notarized : ${NOTARIZED} (stapled: ${NOTARIZED})"
if [[ "${SIGNED}" != "yes" || "${NOTARIZED}" != "yes" ]]; then
  echo ""
  echo " NOTE: This dmg is NOT fully signed+notarized and should NOT be published"
  echo "       as the official release. See docs/RELEASING.md."
fi
echo "------------------------------------------------------------------------"
echo " To publish (after a signed + notarized build):"
echo ""
echo "   gh release create v${VERSION} \"${DMG_PATH}\" \\"
echo "     --title \"${APP_NAME} ${VERSION}\" --generate-notes"
echo "========================================================================"
