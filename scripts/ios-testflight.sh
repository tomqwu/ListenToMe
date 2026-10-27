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
options_temp=$(mktemp -d "${TMPDIR:-/tmp}/listentome-export-options.XXXXXX")
owned_upload_lock=''
cleanup_upload() {
  if [[ -n "$owned_upload_lock" ]]; then rmdir "$owned_upload_lock"; fi
  rm -rf -- "$options_temp"
}
trap cleanup_upload EXIT
python3 - "$watch_beta" "$options_temp" <<'PY'
import hashlib, json, os, pathlib, plistlib, re, sys

def require(condition, message):
    if not condition:
        raise ValueError(message)

try:
    default = pathlib.Path('Config/iOS/TestFlightExportOptions.plist')
    selected = os.environ.get('IOS_EXPORT_OPTIONS', '')
    path = pathlib.Path(selected) if selected else default
    require(not any(c in str(path) for c in '\r\n\t\0'), 'Invalid options path')
    raw = path.read_bytes()
    options = plistlib.loads(raw)
    require(isinstance(options, dict), 'Options must be a dictionary')
    require(options.get('destination') == 'upload', 'Destination must be upload')
    require(options.get('method') == 'app-store-connect', 'Method must be app-store-connect')
    require(options.get('manageAppVersionAndBuildNumber') is False, 'Version management must be disabled')
    require(options.get('uploadSymbols') is True, 'Symbol upload must stay enabled')
    expected_team = 'T32FW7PZ3S'
    require(options.get('teamID') == expected_team, 'Team must match the checked-in production team')
    if selected:
        allowed = {'destination', 'method', 'manageAppVersionAndBuildNumber', 'uploadSymbols',
                   'teamID', 'signingStyle', 'signingCertificate', 'provisioningProfiles'}
        require(set(options) == allowed, 'Manual options must contain exactly the supported fields')
        require(options.get('signingStyle') == 'manual', 'Explicit options must use manual signing')
        certificate = options.get('signingCertificate')
        require(isinstance(certificate, str) and re.fullmatch(r'[0-9a-fA-F]{40}', certificate),
                'Manual signing requires the existing certificate SHA-1 selector')
        expected = {'com.tomwu.ListenToMe.ios', 'com.tomwu.ListenToMe.ios.share'}
        if sys.argv[1] == '1':
            expected.add('com.tomwu.ListenToMe.ios.watchkitapp')
        profiles = options.get('provisioningProfiles')
        require(isinstance(profiles, dict) and set(profiles) == expected,
                'Manual profiles must match exactly the archived bundle IDs')
        pattern = r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
        require(all(isinstance(value, str) and re.fullmatch(pattern, value) for value in profiles.values()),
                'Manual profiles require UUID selectors')
    else:
        require(options.get('signingStyle') == 'automatic', 'Default signing must remain automatic')
    directory = pathlib.Path(sys.argv[2])
    with (directory / 'ExportOptions.plist').open('xb') as stream:
        os.chmod(stream.name, 0o600)
        stream.write(raw)
    metadata = {'original': str(path.resolve()), 'sha256': hashlib.sha256(raw).hexdigest(),
                'signingStyle': options['signingStyle']}
    with (directory / 'metadata.json').open('x') as stream:
        os.chmod(stream.name, 0o600)
        json.dump(metadata, stream)
except (OSError, ValueError, TypeError, KeyError, plistlib.InvalidFileException):
    # Never echo malformed plist contents, credentials or arbitrary input values.
    print('Invalid TestFlight export options; check the documented upload/signing fields.', file=sys.stderr)
    sys.exit(2)
PY
IFS=$'\t' read -r export_options_original export_options_sha256 signing_style <<< "$(python3 - "$options_temp/metadata.json" <<'PY'
import json, pathlib, sys
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(metadata['original'], metadata['sha256'], metadata['signingStyle'], sep='\t')
PY
)"
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
authentication=xcode_session
if [[ -n "$auth_arguments" ]]; then authentication=app_store_connect_api_key; fi
if [[ $dry_run == 1 ]]; then
  echo "Validated archive identity: $release; declared source: $source_commit"
  echo "Authentication route: $authentication (not authenticated by this dry run)."
  if [[ $watch_beta == 1 ]]; then
    echo 'Watch-enabled beta identity checked; physical-device acceptance unverified. Signing/export checks remain separate.'
  fi
  echo "Upload settings: $export_options_original ($signing_style signing); no upload performed."
  exit 0
fi
mkdir -p "$evidence"
lock="$evidence/upload.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "Another upload may be active ($lock). Inspect it before retrying." >&2
  exit 3
fi
owned_upload_lock=$lock
# Recheck after acquiring the lock in case another session just completed.
if [[ -f "$marker" ]]; then
  echo "Upload already recorded in $marker; check TestFlight instead." >&2
  exit 3
fi
# Preserve the validated bytes, not a later read of the caller's mutable options file.
export_options=$(python3 - "$options_temp" "$evidence" <<'PY'
import hashlib, json, os, pathlib, sys, tempfile
source = pathlib.Path(sys.argv[1])
raw = (source / 'ExportOptions.plist').read_bytes()
metadata = json.loads((source / 'metadata.json').read_text())
if hashlib.sha256(raw).hexdigest() != metadata['sha256']:
    raise SystemExit('Validated export-options snapshot changed')
directory = pathlib.Path(tempfile.mkdtemp(prefix='export-options-', dir=sys.argv[2]))
path = directory / 'ExportOptions.plist'
with path.open('xb') as stream:
    os.chmod(stream.name, 0o600)
    stream.write(raw)
with (directory / 'metadata.json').open('x') as stream:
    os.chmod(stream.name, 0o600)
    json.dump(metadata, stream, indent=2)
print(path.resolve())
PY
)
upload_command=(xcodebuild -exportArchive -archivePath "$archive" -exportPath "dist/$release-upload"
  -exportOptionsPlist "$export_options" -allowProvisioningUpdates)
if [[ -n "$auth_arguments" ]]; then
  while IFS= read -r argument; do upload_command+=("$argument"); done <<< "$auth_arguments"
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
python3 - "$marker" "$archive" "$source_commit" "$log" "$authentication" "$watch_beta" "$export_options" "$export_options_sha256" "$signing_style" "$export_options_original" <<'PY'
import datetime, json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    'status': 'upload_accepted', 'archive': str(pathlib.Path(sys.argv[2]).resolve()),
    'source_commit': sys.argv[3], 'log': sys.argv[4],
    'authentication': sys.argv[5],
    'export_options': sys.argv[7], 'export_options_sha256': sys.argv[8],
    'signing_style': sys.argv[9], 'export_options_original': sys.argv[10],
    'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'tester_availability': 'unverified',
    'watch_beta_requested': sys.argv[6] == '1',
    'watch_embedded': (pathlib.Path(sys.argv[2]) / 'Products/Applications/ListenToMeIOS.app/Watch/ListenToMeWatch.app/Info.plist').is_file(),
    'physical_device_acceptance': 'unverified'
}, indent=2) + '\n')
PY
echo "Upload accepted. Evidence: $marker. Now verify Apple processing and tester availability."
