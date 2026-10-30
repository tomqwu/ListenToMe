#!/usr/bin/env python3
"""Exercise the repository's real make shell/recipes without executing a native build."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
MAKEFILE = ROOT / "Makefile"
MAKE_BINARIES = list(dict.fromkeys(str(path) for path in [
    Path(shutil.which("make") or "/usr/bin/make"),
    Path("/Applications/Xcode.app/Contents/Developer/usr/bin/make"),
] if path.is_file()))
NATIVE_TARGETS = ["ios-test", "mac-test", "watch-test", "ios-build", "watch-build"]


class MakePipelineTests(unittest.TestCase):
    def exercise(self, success, spaces, native_target=None):
        self.assertTrue(MAKE_BINARIES, "A real make implementation is required")
        for index, make in enumerate(MAKE_BINARIES):
            with self.subTest(make=make, native_target=native_target):
                evidence = os.environ.get("LISTENTOME_MAKE_PIPELINE_EVIDENCE")
                if evidence:
                    root = Path(evidence) / f"{self._testMethodName}-{index}-{native_target or 'pipeline'}"
                    root.mkdir(parents=True, exist_ok=False)
                    self.run_case(root, make, success, spaces, native_target)
                else:
                    with tempfile.TemporaryDirectory(prefix="make pipeline regression ") as folder:
                        self.run_case(Path(folder), make, success, spaces, native_target)

    def run_case(self, root, make, success, spaces, native_target):
        workspace = root / ("workspace with spaces" if spaces else "workspace")
        workspace.mkdir()
        tools = workspace / "fake tools"
        tools.mkdir()
        producer = tools / "controlled producer"
        producer.write_text('#!/bin/sh\nprintf "producer-output\\n"\n'
                            'printf "%s\\n" "$*" > "$MAKE_PIPELINE_PROBE_DIR/producer arguments.txt"\n'
                            'exit "$MAKE_PIPELINE_PRODUCER_EXIT"\n')
        producer.chmod(0o755)
        shutil.copyfile(producer, tools / "xcodebuild")
        (tools / "xcodebuild").chmod(0o755)
        verifier = tools / "python3"
        verifier.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MAKE_PIPELINE_PROBE_DIR/verifier calls.txt"\n')
        verifier.chmod(0o755)
        overlay = workspace / "Pipeline overlay.mk"
        sentinel = workspace / "following sentinel.txt"
        if native_target:
            # Override only generation. The actual repository build/test recipes still run,
            # with harmless PATH stubs replacing xcodebuild and the later log verifier.
            overlay.write_text('.PHONY: gen pipeline_contract\ngen:\n\t@:\n'
                               f'pipeline_contract: {native_target}\n'
                               '\tprintf "following-recipe\\n" > "following sentinel.txt"\n')
        else:
            overlay.write_text('.PHONY: pipeline_contract\npipeline_contract:\n'
                               f'\t{shlex.quote(str(producer))} | tee "pipeline log.txt"\n'
                               '\tprintf "following-recipe\\n" > "following sentinel.txt"\n')
        command = [make, '--no-print-directory', '-f', str(MAKEFILE), '-f', str(overlay),
                   'WATCH_DESTINATION=platform=watchOS Simulator,id=offline-probe', 'pipeline_contract']
        env = {**os.environ, 'PATH': str(tools) + os.pathsep + os.environ.get('PATH', ''),
               'MAKE_PIPELINE_PROBE_DIR': str(workspace), 'MAKE_PIPELINE_PRODUCER_EXIT': '0' if success else '7'}
        result = subprocess.run(command, cwd=workspace, env=env, text=True, capture_output=True, timeout=15)
        calls = workspace / 'verifier calls.txt'
        log = (workspace / 'dist/bdd' / (native_target.split('-')[0] + '-full.log')
               if native_target and native_target.endswith('-test') else workspace / 'pipeline log.txt')
        record = {'command': command, 'cwd': str(workspace), 'exit': result.returncode,
                  'stdout': result.stdout, 'stderr': result.stderr, 'producerExit': 0 if success else 7,
                  'sentinelExists': sentinel.exists(), 'verifierRan': calls.exists(),
                  'log': log.read_text() if log.exists() else None}
        (root / 'actual-result.json').write_text(json.dumps(record, indent=2) + '\n')
        self.assertTrue((workspace / 'producer arguments.txt').exists(), record)
        self.assertIn('producer-output', result.stdout, record)
        if not native_target or native_target.endswith('-test'):
            self.assertTrue(log.exists(), record)
            self.assertEqual(log.read_text(), 'producer-output\n', record)
        if success:
            self.assertEqual(result.returncode, 0, record)
            self.assertEqual(sentinel.read_text(), 'following-recipe\n', record)
            expected = 1 if native_target == 'mac-test' else 2 if native_target in ['ios-test', 'watch-test'] else 0
            self.assertEqual(len(calls.read_text().splitlines()) if calls.exists() else 0, expected, record)
        else:
            self.assertNotEqual(result.returncode, 0, record)
            self.assertFalse(sentinel.exists(), record)
            self.assertFalse(calls.exists(), record)

    def test_failed_pipeline_stops_following_recipe(self):
        self.exercise(success=False, spaces=False)

    def test_failed_pipeline_stops_with_space_paths(self):
        self.exercise(success=False, spaces=True)

    def test_successful_pipeline_continues(self):
        self.exercise(success=True, spaces=False)

    def test_successful_pipeline_continues_with_space_paths(self):
        self.exercise(success=True, spaces=True)

    def test_actual_native_recipes_stop_after_failed_producer(self):
        for target in NATIVE_TARGETS:
            self.exercise(success=False, spaces=True, native_target=target)

    def test_actual_native_recipes_continue_after_successful_producer(self):
        for target in NATIVE_TARGETS:
            self.exercise(success=True, spaces=True, native_target=target)


if __name__ == '__main__':
    unittest.main()
