"""Exercise upload decisions without Apple credentials or network access."""
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
        stub.write_text('#!/usr/bin/env python3\nimport json, os, pathlib, sys\n'
                        'pathlib.Path(os.environ["MOCK_ARGUMENTS"]).write_text(json.dumps(sys.argv[1:]))\n'
                        'print(os.environ["MOCK_OUTPUT"])\nsys.exit(int(os.environ["MOCK_EXIT"]))\n')
        stub.chmod(0o755)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   MOCK_OUTPUT=output, MOCK_EXIT=str(code), MOCK_ARGUMENTS=str(self.arguments),
                   LISTENTOME_CONFIG_DIR=str(self.config.parent))
        for name in ('ASC_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'IOS_ASC_CONFIG'):
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
