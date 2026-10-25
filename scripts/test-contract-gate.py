#!/usr/bin/env python3
"""Exercise the process-level contract gate without making model requests."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GATE = Path(__file__).with_name("run-contract-tests.py")


class ContractGateTests(unittest.TestCase):
    def run_gate(self, output, code=0):
        with tempfile.TemporaryDirectory() as folder:
            swift = Path(folder) / "swift"
            swift.write_text(f"#!{sys.executable}\nprint({output!r})\nraise SystemExit({code})\n")
            swift.chmod(0o755)
            return subprocess.run([sys.executable, str(GATE), "OllamaContractE2ETests"],
                                  env={**os.environ, "PATH": folder + os.pathsep + os.environ["PATH"]},
                                  capture_output=True, text=True)

    def test_empty_success_is_not_acceptance(self):
        self.assertNotEqual(self.run_gate("Test run with 0 tests passed").returncode, 0)

    def test_all_skipped_is_not_acceptance(self):
        self.assertNotEqual(self.run_gate(
            "Test Case '-[ListenToMeCoreTests.OllamaContractE2ETests testReal]' skipped (0.001 seconds)."
        ).returncode, 0)

    def test_another_suite_cannot_satisfy_the_gate(self):
        self.assertNotEqual(self.run_gate("Test Case 'OtherTests.testReal' passed (0.001 seconds).").returncode, 0)

    def test_real_xctest_passes_on_mac_and_linux(self):
        for name in ["-[ListenToMeCoreTests.OllamaContractE2ETests testReal]", "OllamaContractE2ETests.testReal"]:
            with self.subTest(name=name):
                result = self.run_gate(f"Test Case '{name}' passed (0.001 seconds).\nTest run with 0 tests passed")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("verified 1 passing", result.stdout)

    def test_failed_process_cannot_be_hidden_by_a_passing_case(self):
        self.assertEqual(self.run_gate("Test Case 'OllamaContractE2ETests.testReal' passed (0.001 seconds).",
                                       code=7).returncode, 7)


if __name__ == "__main__":
    unittest.main()
