#!/usr/bin/env bash
#
# Enforces a minimum line-coverage floor on the ListenToMeCore package.
# Usage: scripts/check-coverage.sh [THRESHOLD]   (default 95)
#
# Runs `swift test --enable-code-coverage`, then computes total line coverage
# (excluding the test target and build artifacts) via llvm-cov and fails if it
# is below THRESHOLD.
set -euo pipefail

THRESHOLD="${1:-95}"

echo "==> Running tests with coverage"
swift test --enable-code-coverage

BIN=$(swift build --show-bin-path)
PROF="$BIN/codecov/default.profdata"
XCTEST=$(find "$BIN" -maxdepth 1 -name "*.xctest" | head -1)
if [ -z "$XCTEST" ] || [ ! -f "$PROF" ]; then
  echo "ERROR: could not locate test bundle or coverage profile under $BIN" >&2
  exit 1
fi
EXE="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"

# Total line-coverage percent for source files (Tests/ and .build/ excluded).
PCT=$(xcrun llvm-cov export "$EXE" \
        -instr-profile "$PROF" \
        -ignore-filename-regex='Tests|\.build' \
        --summary-only \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["totals"]["lines"]["percent"])')

echo "==> ListenToMeCore line coverage: ${PCT}%  (floor: ${THRESHOLD}%)"

# Per-file report for visibility in CI logs.
xcrun llvm-cov report "$EXE" -instr-profile "$PROF" -ignore-filename-regex='Tests|\.build'

awk -v pct="$PCT" -v thr="$THRESHOLD" 'BEGIN { exit !(pct + 0 >= thr + 0) }' || {
  echo "FAIL: coverage ${PCT}% is below the ${THRESHOLD}% floor" >&2
  exit 1
}
echo "PASS: coverage ${PCT}% meets the ${THRESHOLD}% floor"
