"""Exercise upload decisions without Apple credentials or network access."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('ios-testflight.sh')


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy(SCRIPT, self.root / 'scripts/ios-testflight.sh')
        (self.root / 'Config/iOS').mkdir(parents=True)
        shutil.copy(SCRIPT.parent.parent / 'Config/iOS/TestFlightExportOptions.plist',
                    self.root / 'Config/iOS/TestFlightExportOptions.plist')
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '--allow-empty', '-qm', 'fixture'], cwd=self.root, check=True)
        app = self.root / 'fixture.xcarchive/Products/Applications/ListenToMeIOS.app'
        for path, bundle in [(app, 'com.tomwu.ListenToMe.ios'),
                             (app / 'PlugIns/ListenToMeShare.appex', 'com.tomwu.ListenToMe.ios.share')]:
            path.mkdir(parents=True, exist_ok=True)
            (path / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': '1.0.0',
                'CFBundleVersion': '1'}))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.evidence = self.root / 'dist/ios-1.0.0-build1-evidence'
        self.marker = self.evidence / 'upload-accepted.json'
        self.config = self.root / 'local-config/testflight.json'
        self.arguments = self.root / 'xcode-arguments.json'

    def run_upload(self, output='Upload succeeded.', code=0, flags=(), auth=None):
        stub = self.bin / 'xcodebuild'
        stub.write_text('#!/usr/bin/env python3\nimport json, os, pathlib, plistlib, sys\n'
                        'if os.environ.get("MOCK_OPTIONS_ORIGINAL"):\n'
                        '    pathlib.Path(os.environ["MOCK_OPTIONS_ORIGINAL"]).write_bytes(plistlib.dumps({"destination": "export"}))\n'
                        '    selected = pathlib.Path(sys.argv[sys.argv.index("-exportOptionsPlist") + 1])\n'
                        '    pathlib.Path(os.environ["MOCK_OBSERVED_OPTIONS"]).write_text(json.dumps(plistlib.loads(selected.read_bytes())))\n'
                        'pathlib.Path(os.environ["MOCK_ARGUMENTS"]).write_text(json.dumps(sys.argv[1:]))\n'
                        'print(os.environ["MOCK_OUTPUT"])\nsys.exit(int(os.environ["MOCK_EXIT"]))\n')
        stub.chmod(0o755)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   MOCK_OUTPUT=output, MOCK_EXIT=str(code), MOCK_ARGUMENTS=str(self.arguments),
                   LISTENTOME_CONFIG_DIR=str(self.config.parent))
        for name in ('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'IOS_ASC_CONFIG', 'IOS_EXPORT_OPTIONS'):
            env.pop(name, None)
        env.update(auth or {})
        return subprocess.run(['bash', 'scripts/ios-testflight.sh', 'fixture.xcarchive',
                               'HEAD', *flags], cwd=self.root, env=env, capture_output=True, text=True)

    def test_failed_upload_leaves_no_receipt_and_releases_lock(self):
        self.assertEqual(self.run_upload('Failed to Use Accounts', 70).returncode, 1)
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.evidence / 'upload.lock').exists())

    def test_export_alone_is_not_acceptance(self):
        self.assertEqual(self.run_upload('** EXPORT SUCCEEDED **').returncode, 1)
        self.assertFalse(self.marker.exists())

    def test_acceptance_receipt_and_duplicate_guard(self):
        self.assertEqual(self.run_upload().returncode, 0)
        receipt = json.loads(self.marker.read_text())
        self.assertEqual(receipt['status'], 'upload_accepted')
        self.assertEqual(receipt['tester_availability'], 'unverified')
        self.assertEqual(receipt['signing_style'], 'automatic')
        options = self.root / 'Config/iOS/TestFlightExportOptions.plist'
        self.assertEqual(receipt['export_options_sha256'], hashlib.sha256(options.read_bytes()).hexdigest())
        self.assertEqual(self.run_upload().returncode, 3)

    def test_active_upload_guard(self):
        (self.evidence / 'upload.lock').mkdir(parents=True)
        self.assertEqual(self.run_upload().returncode, 3)
        self.assertFalse(self.marker.exists())

    def test_dry_run_does_not_upload(self):
        self.assertEqual(self.run_upload(code=70, flags=['--dry-run']).returncode, 0)
        self.assertFalse(self.evidence.exists())

    def test_wrong_bundle_is_rejected(self):
        path = self.root / 'fixture.xcarchive/Products/Applications/ListenToMeIOS.app/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleIdentifier'] = 'wrong.app'
        path.write_bytes(plistlib.dumps(info))
        self.assertNotEqual(self.run_upload().returncode, 0)
        self.assertFalse(self.evidence.exists())

    def watch_fixture(self):
        watch = self.root / 'fixture.xcarchive/Products/Applications/ListenToMeIOS.app/Watch/ListenToMeWatch.app'
        watch.mkdir(parents=True)
        (watch / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.tomwu.ListenToMe.ios.watchkitapp',
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
            'WKCompanionAppBundleIdentifier': 'com.tomwu.ListenToMe.ios',
            'WKApplication': True, 'WKRunsIndependentlyOfCompanionApp': False,
            'CFBundleSupportedPlatforms': ['WatchOS'], 'DTPlatformName': 'watchos',
            'MinimumOSVersion': '26.0', 'UIDeviceFamily': [4],
            'CFBundleExecutable': 'ListenToMeWatch',
            'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}}}))
        (watch / 'ListenToMeWatch').write_bytes(b'fixture executable; signing is a separate candidate gate')
        (watch / 'Assets.car').write_bytes(b'fixture icons')
        return watch

    def test_embedded_watch_app_requires_explicit_watch_beta_mode(self):
        self.watch_fixture()
        result = self.run_upload(flags=['--dry-run'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--include-watch-beta', result.stderr + result.stdout)
        self.assertFalse(self.evidence.exists())

    def test_explicit_watch_beta_records_pending_physical_acceptance(self):
        self.watch_fixture()
        result = self.run_upload(flags=['--include-watch-beta'])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        receipt = json.loads(self.marker.read_text())
        self.assertEqual(receipt['status'], 'upload_accepted')
        self.assertTrue(receipt['watch_beta_requested'])
        self.assertTrue(receipt['watch_embedded'])
        self.assertEqual(receipt['physical_device_acceptance'], 'unverified')
        self.assertEqual(receipt['tester_availability'], 'unverified')
        self.assertEqual(self.run_upload(flags=['--include-watch-beta']).returncode, 3)

    def test_watch_beta_dry_run_checks_but_never_uploads(self):
        self.watch_fixture()
        for flags in [('--include-watch-beta', '--dry-run'), ('--dry-run', '--include-watch-beta')]:
            result = self.run_upload(flags=flags)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('Watch-enabled beta', result.stdout)
            self.assertIn('physical-device acceptance unverified', result.stdout)
            self.assertFalse(self.arguments.exists())
            self.assertFalse(self.evidence.exists())

    def test_watch_beta_requires_a_watch_bundle(self):
        result = self.run_upload(flags=['--include-watch-beta'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing Watch app', result.stderr + result.stdout)
        self.assertFalse(self.arguments.exists())

    def test_watch_beta_rejects_malformed_companion_before_upload(self):
        watch = self.watch_fixture()
        original = plistlib.loads((watch / 'Info.plist').read_bytes())
        for field, bad in [('CFBundleIdentifier', 'wrong.watch'),
                           ('WKCompanionAppBundleIdentifier', 'wrong.phone'),
                           ('WKApplication', False),
                           ('WKRunsIndependentlyOfCompanionApp', True),
                           ('CFBundleShortVersionString', '2.0.0'), ('CFBundleVersion', '2'),
                           ('CFBundleSupportedPlatforms', ['WatchSimulator']),
                           ('DTPlatformName', 'watchsimulator'), ('MinimumOSVersion', '25.0'),
                           ('MinimumOSVersion', '27.0'), ('UIDeviceFamily', [1]),
                           ('CFBundleExecutable', '../escape'), ('CFBundleIcons', {})]:
            with self.subTest(field=field, value=bad):
                (watch / 'Info.plist').write_bytes(plistlib.dumps(dict(original, **{field: bad})))
                result = self.run_upload(flags=['--include-watch-beta'])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Watch', result.stderr + result.stdout)
                self.assertFalse(self.arguments.exists())
                self.assertFalse(self.marker.exists())
        (watch / 'Info.plist').write_bytes(plistlib.dumps(original))
        for required in ['ListenToMeWatch', 'Assets.car']:
            with self.subTest(missing=required):
                file = watch / required
                file.unlink()
                self.assertNotEqual(self.run_upload(flags=['--include-watch-beta']).returncode, 0)
                self.assertFalse(self.arguments.exists())
                file.write_bytes(b'fixture')

    def test_watch_beta_rejects_unexpected_extra_bundle(self):
        watch = self.watch_fixture()
        extra = watch.parent / 'Unexpected.app'
        extra.mkdir()
        result = self.run_upload(flags=['--include-watch-beta'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected Watch', result.stderr + result.stdout)
        self.assertFalse(self.arguments.exists())

    def test_unknown_and_duplicate_flags_never_upload(self):
        for flags in [('--unknown',), ('--dry-run', '--dry-run'),
                      ('--include-watch-beta', '--include-watch-beta')]:
            with self.subTest(flags=flags):
                self.assertNotEqual(self.run_upload(flags=flags).returncode, 0)
                self.assertFalse(self.arguments.exists())
                self.assertFalse(self.marker.exists())

    def test_make_forwards_watch_beta_and_dry_run_flags(self):
        self.watch_fixture()
        source_makefile = SCRIPT.parent.parent / 'Makefile'
        (self.root / 'Makefile').write_text(source_makefile.read_text())
        result = subprocess.run(['make', 'ios-testflight', 'IOS_ARCHIVE=fixture.xcarchive',
                                 'IOS_RELEASE_SOURCE=HEAD',
                                 'IOS_RELEASE_FLAGS=--include-watch-beta --dry-run'],
                                cwd=self.root, capture_output=True, text=True,
                                env=dict(os.environ, LISTENTOME_CONFIG_DIR=str(self.config.parent)))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('Watch-enabled beta', result.stdout)
        self.assertFalse(self.marker.exists())

    def manual_options(self, watch=True):
        profiles = {
            'com.tomwu.ListenToMe.ios': '11111111-1111-4111-8111-111111111111',
            'com.tomwu.ListenToMe.ios.share': '22222222-2222-4222-8222-222222222222'}
        if watch:
            profiles['com.tomwu.ListenToMe.ios.watchkitapp'] = '33333333-3333-4333-8333-333333333333'
        options = {'destination': 'upload', 'method': 'app-store-connect',
                   'manageAppVersionAndBuildNumber': False, 'teamID': 'T32FW7PZ3S',
                   'signingStyle': 'manual', 'signingCertificate': 'A' * 40,
                   'provisioningProfiles': profiles, 'uploadSymbols': True}
        path = self.root / 'local options/manual upload.plist'
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(plistlib.dumps(options))
        return path, options

    def test_manual_watch_options_reach_upload_and_receipt(self):
        self.watch_fixture()
        path, _ = self.manual_options()
        result = self.run_upload(flags=['--include-watch-beta'],
                                 auth={'IOS_EXPORT_OPTIONS': str(path)})
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads(self.arguments.read_text())
        snapshot = Path(arguments[arguments.index('-exportOptionsPlist') + 1])
        self.assertNotEqual(snapshot, path.resolve())
        self.assertEqual(snapshot.read_bytes(), path.read_bytes())
        self.assertTrue(snapshot.is_relative_to(self.evidence.resolve()))
        receipt = json.loads(self.marker.read_text())
        self.assertEqual(receipt['signing_style'], 'manual')
        self.assertEqual(receipt['export_options_sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(receipt['source_commit'], subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip())
        self.assertTrue(receipt['watch_embedded'])
        self.assertEqual(receipt['physical_device_acceptance'], 'unverified')

    def test_manual_options_without_watch_keep_exact_phone_map(self):
        path, _ = self.manual_options(watch=False)
        result = self.run_upload(auth={'IOS_EXPORT_OPTIONS': str(path.relative_to(self.root))})
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads(self.arguments.read_text())
        snapshot = Path(arguments[arguments.index('-exportOptionsPlist') + 1])
        self.assertNotEqual(snapshot, path.resolve())
        self.assertEqual(snapshot.read_bytes(), path.read_bytes())
        self.assertTrue(snapshot.is_relative_to(self.evidence.resolve()))
        self.assertEqual(json.loads(self.marker.read_text())['signing_style'], 'manual')

    def test_original_options_change_cannot_change_validated_upload(self):
        path, options = self.manual_options(watch=False)
        original_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        observed = self.root / 'observed-options.json'
        result = self.run_upload(auth={'IOS_EXPORT_OPTIONS': str(path),
                                      'MOCK_OPTIONS_ORIGINAL': str(path),
                                      'MOCK_OBSERVED_OPTIONS': str(observed)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(observed.read_text()), options)
        self.assertEqual(plistlib.loads(path.read_bytes())['destination'], 'export')
        receipt = json.loads(self.marker.read_text())
        snapshot = Path(receipt['export_options'])
        self.assertNotEqual(snapshot, path.resolve())
        self.assertEqual(plistlib.loads(snapshot.read_bytes()), options)
        self.assertEqual(receipt['export_options_sha256'], original_hash)
        self.assertEqual(receipt['export_options_original'], str(path.resolve()))
        self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
        self.assertEqual(snapshot.parent.stat().st_mode & 0o777, 0o700)

    def test_unsafe_manual_options_never_invoke_xcode(self):
        self.watch_fixture()
        path, original = self.manual_options()
        bad_profiles = dict(original['provisioningProfiles'])
        bad_profiles.pop('com.tomwu.ListenToMe.ios.watchkitapp')
        extra_profiles = dict(original['provisioningProfiles'], **{'another.app': '4' * 36})
        invalid_profiles = dict(original['provisioningProfiles'])
        invalid_profiles['com.tomwu.ListenToMe.ios'] = 'profile-name-instead-of-uuid'
        cases = [('destination', 'export'), ('method', 'development'),
                 ('teamID', 'OTHERTEAM1'), ('manageAppVersionAndBuildNumber', True),
                 ('manageAppVersionAndBuildNumber', 0), ('signingStyle', 'automatic'),
                 ('signingCertificate', 'Apple Distribution'), ('signingCertificate', ''),
                 ('uploadSymbols', False), ('provisioningProfiles', bad_profiles),
                 ('provisioningProfiles', extra_profiles), ('provisioningProfiles', invalid_profiles),
                 ('provisioningProfiles', []), ('thinning', '<thin-for-all-variants>')]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                path.write_bytes(plistlib.dumps(dict(original, **{field: value})))
                result = self.run_upload(flags=['--include-watch-beta'],
                                         auth={'IOS_EXPORT_OPTIONS': str(path)})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.arguments.exists())
                self.assertFalse(self.marker.exists())
        for missing in original:
            with self.subTest(missing=missing):
                options = dict(original)
                options.pop(missing)
                path.write_bytes(plistlib.dumps(options))
                self.assertNotEqual(self.run_upload(flags=['--include-watch-beta'],
                    auth={'IOS_EXPORT_OPTIONS': str(path)}).returncode, 0)
                self.assertFalse(self.arguments.exists())
                self.assertFalse(self.marker.exists())
        path.write_bytes(plistlib.dumps(original))
        shutil.rmtree(self.root / 'fixture.xcarchive/Products/Applications/ListenToMeIOS.app/Watch')
        result = self.run_upload(auth={'IOS_EXPORT_OPTIONS': str(path)})
        self.assertNotEqual(result.returncode, 0, 'Non-Watch mode must reject an extra Watch profile')
        self.assertFalse(self.arguments.exists())

    def test_missing_or_malformed_manual_options_never_invoke_xcode(self):
        path, _ = self.manual_options(watch=False)
        for content in [b'PRIVATE_OPTIONS_MUST_NOT_BE_PRINTED', plistlib.dumps([]),
                        plistlib.dumps({'destination': 'upload'})]:
            with self.subTest(content=content[:16]):
                path.write_bytes(content)
                result = self.run_upload(auth={'IOS_EXPORT_OPTIONS': str(path)})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PRIVATE_OPTIONS_MUST_NOT_BE_PRINTED', result.stderr + result.stdout)
                self.assertFalse(self.arguments.exists())
                self.assertFalse(self.marker.exists())
        path.unlink()
        self.assertNotEqual(self.run_upload(auth={'IOS_EXPORT_OPTIONS': str(path)}).returncode, 0)
        self.assertFalse(self.arguments.exists())

    def test_manual_dry_run_and_failure_never_claim_acceptance(self):
        self.watch_fixture()
        path, _ = self.manual_options()
        auth = {'IOS_EXPORT_OPTIONS': str(path)}
        result = self.run_upload(flags=['--include-watch-beta', '--dry-run'], auth=auth)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path.resolve()), result.stdout)
        self.assertIn('manual', result.stdout)
        self.assertFalse(self.arguments.exists())
        self.assertFalse(self.evidence.exists())
        for output, code in [('Signing failed', 70), ('** EXPORT SUCCEEDED **', 0)]:
            self.assertEqual(self.run_upload(output, code, flags=['--include-watch-beta'],
                                            auth=auth).returncode, 1)
            self.assertFalse(self.marker.exists())
            self.assertFalse((self.evidence / 'upload.lock').exists())

    def test_manual_options_preserve_duplicate_and_active_upload_guards(self):
        self.watch_fixture()
        path, _ = self.manual_options()
        auth = {'IOS_EXPORT_OPTIONS': str(path)}
        lock = self.evidence / 'upload.lock'
        lock.mkdir(parents=True)
        self.assertEqual(self.run_upload(flags=['--include-watch-beta'], auth=auth).returncode, 3)
        self.assertFalse(self.arguments.exists())
        lock.rmdir()
        self.assertEqual(self.run_upload(flags=['--include-watch-beta'], auth=auth).returncode, 0)
        self.arguments.unlink()
        self.assertEqual(self.run_upload(flags=['--include-watch-beta'], auth=auth).returncode, 3)
        self.assertFalse(self.arguments.exists())

    def test_make_forwards_explicit_manual_export_options(self):
        path, _ = self.manual_options(watch=False)
        (self.root / 'Makefile').write_text((SCRIPT.parent.parent / 'Makefile').read_text())
        result = subprocess.run(['make', 'ios-testflight', 'IOS_ARCHIVE=fixture.xcarchive',
                                 'IOS_RELEASE_SOURCE=HEAD', 'IOS_RELEASE_FLAGS=--dry-run',
                                 'IOS_EXPORT_OPTIONS=' + str(path)], cwd=self.root,
                                capture_output=True, text=True,
                                env=dict(os.environ, LISTENTOME_CONFIG_DIR=str(self.config.parent)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(path.resolve()), result.stdout)
        self.assertIn('manual', result.stdout)
        self.assertFalse(self.arguments.exists())
        self.assertFalse(self.marker.exists())

    def test_default_generated_project_embeds_the_watch_companion(self):
        # Inspect a fresh generated project, with both old opt-in values removed/disabled.
        # The actual built and exported app is also inspected in the release acceptance run.
        repository = SCRIPT.parent.parent
        for legacy in [None, 'NO']:
            with self.subTest(legacy_embed=legacy):
                env = dict(os.environ)
                env.pop('WATCH_EMBED', None)
                if legacy is not None:
                    env['WATCH_EMBED'] = legacy
                destination = self.root / ('generated-' + str(legacy))
                destination.mkdir()
                result = subprocess.run(['xcodegen', 'generate', '--quiet', '--spec',
                                         str(repository / 'project.yml'), '--project', str(destination),
                                         '--project-root', str(repository)], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                project = json.loads(subprocess.check_output([
                    'plutil', '-convert', 'json', '-o', '-',
                    str(destination / 'ListenToMe.xcodeproj/project.pbxproj')]))
                objects = project['objects']
                phone = next(v for v in objects.values()
                             if v.get('isa') == 'PBXNativeTarget' and v['name'] == 'ListenToMeIOS')
                watch_id, watch = next((k, v) for k, v in objects.items()
                                      if v.get('isa') == 'PBXNativeTarget' and v['name'] == 'ListenToMeWatch')
                self.assertIn(watch_id, [objects[k].get('target') for k in phone['dependencies']])
                copy_phases = [objects[k] for k in phone['buildPhases']
                               if objects[k]['isa'] == 'PBXCopyFilesBuildPhase']
                copies = [(phase, objects[build]['fileRef']) for phase in copy_phases for build in phase['files']]
                self.assertTrue(any(product == watch['productReference'] and 'Watch' in phase.get('dstPath', '')
                                    for phase, product in copies), 'Default app must copy the Watch companion')

    def credentials(self):
        key_dir = tempfile.TemporaryDirectory(prefix='upload key ')
        self.addCleanup(key_dir.cleanup)
        key = Path(key_dir.name) / 'AuthKey_TESTKEY123.p8'
        key.write_text('PRIVATE_KEY_MUST_NOT_APPEAR_IN_OUTPUT')
        return {'key_path': str(key.resolve()), 'key_id': 'TESTKEY123',
                'issuer_id': '12345678-1234-1234-1234-123456789abc'}

    def test_api_key_config_is_passed_as_individual_arguments(self):
        credentials = self.credentials()
        self.config.parent.mkdir()
        self.config.write_text(json.dumps(credentials))
        result = self.run_upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.arguments.read_text())
        for flag, value in zip(('-authenticationKeyPath', '-authenticationKeyID', '-authenticationKeyIssuerID'),
                               credentials.values()):
            self.assertEqual(args[args.index(flag) + 1], value)
        receipt = json.loads(self.marker.read_text())
        self.assertEqual(receipt['authentication'], 'app_store_connect_api_key')
        for text in (result.stdout, result.stderr, self.marker.read_text(),
                     *(p.read_text() for p in self.evidence.glob('*.log'))):
            self.assertNotIn('PRIVATE_KEY_MUST_NOT_APPEAR_IN_OUTPUT', text)

    def test_environment_credential_and_dry_run(self):
        credentials = self.credentials()
        auth = dict(zip(('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID'), credentials.values()))
        result = self.run_upload(flags=['--dry-run'], auth=auth)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('app_store_connect_api_key', result.stdout)
        self.assertFalse(self.arguments.exists())
        self.assertEqual(self.run_upload(auth=auth).returncode, 0)

    def test_partial_environment_does_not_fall_back_to_session(self):
        result = self.run_upload(auth={'ASC_KEY_ID': 'TESTKEY123'})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.arguments.exists())

    def test_missing_configured_key_does_not_upload(self):
        credentials = self.credentials()
        Path(credentials['key_path']).unlink()
        self.config.parent.mkdir()
        self.config.write_text(json.dumps(credentials))
        self.assertNotEqual(self.run_upload().returncode, 0)
        self.assertFalse(self.arguments.exists())

    def test_invalid_config_does_not_print_its_contents(self):
        self.config.parent.mkdir()
        self.config.write_text('SECRET_MALFORMED_CONFIG')
        result = self.run_upload()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('SECRET_MALFORMED_CONFIG', result.stderr)
        self.assertFalse(self.arguments.exists())

    def test_key_inside_repository_is_rejected(self):
        credentials = self.credentials()
        key = self.root / 'accidental-key.p8'
        key.write_text('TEST')
        credentials['key_path'] = str(key)
        self.config.parent.mkdir()
        self.config.write_text(json.dumps(credentials))
        self.assertNotEqual(self.run_upload().returncode, 0)
        self.assertFalse(self.arguments.exists())


if __name__ == '__main__':
    unittest.main()
