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

    def run_upload(self, output='Upload succeeded.', code=0, flags=()):
        stub = self.bin / 'xcodebuild'
        stub.write_text('#!/bin/sh\necho "${MOCK_OUTPUT}"\nexit "${MOCK_EXIT}"\n')
        stub.chmod(0o755)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   MOCK_OUTPUT=output, MOCK_EXIT=str(code))
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


if __name__ == '__main__':
    unittest.main()
