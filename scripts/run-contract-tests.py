#!/usr/bin/env python3
"""Run a real-model XCTest suite and reject a vacuous or entirely skipped pass."""
import re
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: run-contract-tests.py XCTestSuite", file=sys.stderr)
        return 2
    suite = sys.argv[1]
    process = subprocess.Popen(["swift", "test", "--filter", suite], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    passed = 0
    pattern = re.compile(r"Test Case .+" + re.escape(suite) + r"[ .].+ passed \(")
    for line in process.stdout:
        print(line, end="", flush=True)
        if pattern.search(line):
            passed += 1
    code = process.wait()
    if code:
        return code
    if not passed:
        print(f"e2e: {suite} executed no passing contract tests; refusing an empty/skipped gate", file=sys.stderr)
        return 1
    print(f"e2e: verified {passed} passing {suite} tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
