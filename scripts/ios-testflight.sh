#!/bin/bash
# Upload a previously validated archive; see docs/IOS-RELEASING.md for the full release workflow.
set -euo pipefail
usage='Usage: ios-testflight.sh <validated.xcarchive> <source-commit> [--dry-run] [--include-watch-beta]'
if [[ "${1:-}" == "--help" ]]; then
  echo "$usage"
  exit 0
fi
if [[ $# -lt 2 ]]; then
  echo "$usage" >&2
  exit 2
fi
archive=$1
source_ref=$2
shift 2
dry_run=0
watch_beta=0
for flag in "$@"; do
  case "$flag" in
    --dry-run) [[ $dry_run == 0 ]] || { echo "$usage" >&2; exit 2; }; dry_run=1 ;;
    --include-watch-beta) [[ $watch_beta == 0 ]] || { echo "$usage" >&2; exit 2; }; watch_beta=1 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
source_commit=$(git rev-parse --verify "$source_ref^{commit}")
release=$(python3 - "$archive" "$watch_beta" <<'PY'
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
watch_root = root / 'Watch'
watch_beta = sys.argv[2] == '1'
if watch_beta:
    watch = watch_root / 'ListenToMeWatch.app'
    assert (watch / 'Info.plist').is_file(), 'Missing Watch app for the explicitly selected beta'
    assert sorted(p.name for p in watch_root.iterdir()) == ['ListenToMeWatch.app'], 'Unexpected Watch bundle or payload'
    info = plistlib.loads((watch / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.tomwu.ListenToMe.ios.watchkitapp', 'Wrong Watch bundle'
    assert info['WKCompanionAppBundleIdentifier'] == app['CFBundleIdentifier'], 'Wrong Watch companion'
    assert info.get('WKApplication') is True, 'Invalid Watch application'
    assert info.get('WKRunsIndependentlyOfCompanionApp') is False, 'Unexpected independent Watch app'
    assert (info['CFBundleShortVersionString'], info['CFBundleVersion']) == (version, build), 'App/Watch version mismatch'
    assert info.get('CFBundleSupportedPlatforms') == ['WatchOS'], 'Watch beta requires a device archive'
    assert info.get('DTPlatformName') == 'watchos', 'Watch beta cannot upload a simulator bundle'
    assert info.get('MinimumOSVersion') == '26.0', 'Watch deployment target differs from supported watchOS 26.0'
    assert info.get('UIDeviceFamily') == [4], 'Wrong Watch device family'
    executable = info.get('CFBundleExecutable', '')
    assert executable and pathlib.Path(executable).name == executable and (watch / executable).is_file(), 'Missing or invalid Watch executable'
    icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')
    assert icon == 'AppIcon' and (watch / 'Assets.car').is_file(), 'Missing Watch icons'
else:
    assert not watch_root.exists(), 'Watch app requires explicit --include-watch-beta; physical-device acceptance remains unverified'
print(f'ios-{version}-build{build}')
PY
)
evidence="dist/$release-evidence"
marker="$evidence/upload-accepted.json"
if [[ -f "$marker" ]]; then
  echo "Upload already recorded in $marker; check TestFlight instead of uploading again." >&2
  exit 3
fi
# Use an explicit App Store Connect credential when configured. Never source a
# shell file or print/read the private key itself. Partial configuration is an
# error, not permission to silently fall back to the broken Xcode session path.
auth_arguments=$(python3 - <<'PY'
import json, os, pathlib, re, sys
names = ('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID')
config_dir = pathlib.Path(os.environ.get('LISTENTOME_CONFIG_DIR', '~/.config/listentome')).expanduser()
config = pathlib.Path(os.environ.get('IOS_ASC_CONFIG', str(config_dir / 'testflight.json'))).expanduser()
try:
    if any(name in os.environ for name in names):
        values = [os.environ.get(name, '') for name in names]
    elif config.exists() or 'IOS_ASC_CONFIG' in os.environ:
        data = json.loads(config.read_text())
        values = [data.get(name, '') for name in ('key_path', 'key_id', 'issuer_id')]
    else:
        sys.exit(0)
    if not all(isinstance(value, str) and value and not any(c in value for c in '\r\n\0') for value in values):
        raise ValueError('Provide key_path, key_id and issuer_id together, or all three ASC_* environment variables.')
    path, key_id, issuer_id = values
    if not re.fullmatch(r'[A-Z0-9]{10}', key_id) or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', issuer_id):
        raise ValueError('Invalid App Store Connect Key ID or Issuer ID format.')
    key = pathlib.Path(path).expanduser().resolve()
    if not key.is_file() or not os.access(key, os.R_OK):
        raise ValueError('The configured App Store Connect .p8 file is not readable.')
    if pathlib.Path.cwd() in key.parents:
        raise ValueError('Store the App Store Connect .p8 outside the repository.')
    for argument in ('-authenticationKeyPath', str(key), '-authenticationKeyID', key_id,
                     '-authenticationKeyIssuerID', issuer_id):
        print(argument)
except (OSError, ValueError, AttributeError):
    print('Invalid App Store Connect authentication configuration. Check the three fields and local key file; see docs/IOS-RELEASING.md.', file=sys.stderr)
    sys.exit(2)
PY
)
upload_command=(xcodebuild -exportArchive -archivePath "$archive" -exportPath "dist/$release-upload"
  -exportOptionsPlist Config/iOS/TestFlightExportOptions.plist -allowProvisioningUpdates)
authentication=xcode_session
if [[ -n "$auth_arguments" ]]; then
  authentication=app_store_connect_api_key
  while IFS= read -r argument; do upload_command+=("$argument"); done <<< "$auth_arguments"
fi
if [[ $dry_run == 1 ]]; then
  echo "Validated archive identity: $release; declared source: $source_commit"
  echo "Authentication route: $authentication (not authenticated by this dry run)."
  if [[ $watch_beta == 1 ]]; then
    echo 'Watch-enabled beta identity checked; physical-device acceptance unverified. Signing/export checks remain separate.'
  fi
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
if ! "${upload_command[@]}" > "$log" 2>&1; then
  echo "Upload failed; inspect $log. Preserve this archive and diagnose the error before retrying." >&2
  exit 1
fi
if ! grep -Eq 'Upload succeeded\.|Uploaded ListenToMeIOS' "$log"; then
  echo "No upload acceptance in $log. Local export success alone is insufficient." >&2
  exit 1
fi
python3 - "$marker" "$archive" "$source_commit" "$log" "$authentication" "$watch_beta" <<'PY'
import datetime, json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    'status': 'upload_accepted', 'archive': str(pathlib.Path(sys.argv[2]).resolve()),
    'source_commit': sys.argv[3], 'log': sys.argv[4],
    'authentication': sys.argv[5],
    'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'tester_availability': 'unverified',
    'watch_beta_requested': sys.argv[6] == '1',
    'watch_embedded': (pathlib.Path(sys.argv[2]) / 'Products/Applications/ListenToMeIOS.app/Watch/ListenToMeWatch.app/Info.plist').is_file(),
    'physical_device_acceptance': 'unverified'
}, indent=2) + '\n')
PY
echo "Upload accepted. Evidence: $marker. Now verify Apple processing and tester availability."
