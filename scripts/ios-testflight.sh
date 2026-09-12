#!/bin/bash
# Upload a previously validated archive; see docs/IOS-RELEASING.md for the full release workflow.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: ios-testflight.sh <validated.xcarchive> <source-commit> [--dry-run]'
  exit 0
fi
if [[ $# -lt 2 || $# -gt 3 || ( $# -eq 3 && "$3" != "--dry-run" ) ]]; then
  echo 'Usage: ios-testflight.sh <validated.xcarchive> <source-commit> [--dry-run]' >&2
  exit 2
fi
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
archive=$1
source_commit=$(git rev-parse --verify "$2^{commit}")
release=$(python3 - "$archive" <<'PY'
import pathlib, plistlib, re, sys
root = pathlib.Path(sys.argv[1]) / 'Products/Applications/ListenToMeIOS.app'
app = plistlib.loads((root / 'Info.plist').read_bytes())
ext = plistlib.loads((root / 'PlugIns/ListenToMeShare.appex/Info.plist').read_bytes())
assert app['CFBundleIdentifier'] == 'com.tomwu.ListenToMe.ios', 'Wrong app bundle'
assert ext['CFBundleIdentifier'] == 'com.tomwu.ListenToMe.ios.share', 'Wrong extension bundle'
version, build = app['CFBundleShortVersionString'], app['CFBundleVersion']
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version), 'Invalid version'
assert re.fullmatch(r'[0-9]+', build), 'Invalid build'
assert (version, build) == (ext['CFBundleShortVersionString'], ext['CFBundleVersion']), 'App/extension mismatch'
print(f'ios-{version}-build{build}')
PY
)
evidence="dist/$release-evidence"
marker="$evidence/upload-accepted.json"
if [[ -f "$marker" ]]; then
  echo "Upload already recorded in $marker; check TestFlight instead of uploading again." >&2
  exit 3
fi
if [[ "${3:-}" == "--dry-run" ]]; then
  echo "Validated archive identity: $release; declared source: $source_commit"
  echo 'Upload settings: Config/iOS/TestFlightExportOptions.plist; no upload performed.'
  exit 0
fi
mkdir -p "$evidence"
lock="$evidence/upload.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "Another upload may be active ($lock). Inspect it before retrying." >&2
  exit 3
fi
trap 'rmdir "$lock"' EXIT
# Recheck after acquiring the lock in case another session just completed.
if [[ -f "$marker" ]]; then
  echo "Upload already recorded in $marker; check TestFlight instead." >&2
  exit 3
fi
log="$evidence/upload-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "dist/$release-upload" \
  -exportOptionsPlist Config/iOS/TestFlightExportOptions.plist -allowProvisioningUpdates > "$log" 2>&1; then
  echo "Upload failed; inspect $log. Preserve this archive and diagnose the error before retrying." >&2
  exit 1
fi
if ! grep -Eq 'Upload succeeded\.|Uploaded ListenToMeIOS' "$log"; then
  echo "No upload acceptance in $log. Local export success alone is insufficient." >&2
  exit 1
fi
python3 - "$marker" "$archive" "$source_commit" "$log" <<'PY'
import datetime, json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    'status': 'upload_accepted', 'archive': str(pathlib.Path(sys.argv[2]).resolve()),
    'source_commit': sys.argv[3], 'log': sys.argv[4],
    'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'tester_availability': 'unverified'
}, indent=2) + '\n')
PY
echo "Upload accepted. Evidence: $marker. Now verify Apple processing and tester availability."
