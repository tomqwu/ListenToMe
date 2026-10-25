#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).with_name("release-paths.sh")


class ReleasePathsTests(unittest.TestCase):
    def run_helper(self, command, *args, env=None):
        return subprocess.run(["bash", "-c", 'source "$1"; shift; ' + command, "test", str(HELPER), *map(str, args)],
                              env=env, capture_output=True, text=True)

    def test_debug_app_cannot_substitute_for_missing_release(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "Build/Products/Debug/ListenToMe.app").mkdir(parents=True)
            result = self.run_helper('release_app_path "$1" Release ListenToMe', folder)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("refusing another configuration", result.stderr)

    def test_exact_release_product_with_spaces_is_returned(self):
        with tempfile.TemporaryDirectory(prefix="release test ") as folder:
            app = Path(folder) / "Build/Products/Release/ListenToMe.app"
            app.mkdir(parents=True)
            result = self.run_helper('release_app_path "$1" Release ListenToMe', folder)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(app))

    def test_nested_library_is_signed_before_its_framework(self):
        with tempfile.TemporaryDirectory(prefix="release test ") as folder:
            root = Path(folder)
            app = root / "ListenToMe.app"
            framework = app / "Contents/Frameworks/Outer.framework"
            library = framework / "Versions/A/Libraries/inner.dylib"
            library.parent.mkdir(parents=True); library.touch()
            log = root / "calls"
            fake = root / "codesign"
            fake.write_text(f'#!{sys.executable}\nimport sys\nwith open({str(log)!r}, "a") as f: f.write(sys.argv[-1]+"\\n")\n')
            fake.chmod(0o755)
            result = self.run_helper('release_sign_nested "$1" TestIdentity', app,
                                    env={**os.environ, "PATH": folder + os.pathsep + os.environ["PATH"]})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().splitlines(), [str(library), str(framework)])

    def test_nested_signing_failure_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            app = root / "Test.app"
            framework = app / "Contents/Frameworks/Fail.framework"
            framework.mkdir(parents=True)
            fake = root / "codesign"; fake.write_text("#!/bin/bash\nexit 9\n"); fake.chmod(0o755)
            result = self.run_helper('release_sign_nested "$1" TestIdentity', app,
                                    env={**os.environ, "PATH": folder + os.pathsep + os.environ["PATH"]})
            self.assertEqual(result.returncode, 9)


if __name__ == "__main__":
    unittest.main()
