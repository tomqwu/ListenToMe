#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc -swift-version 6 -parse-as-library "$ROOT/App/HotkeyMonitor.swift" "$ROOT/scripts/test-hotkey.swift" -o "$TEMP/hotkey-checks"
"$TEMP/hotkey-checks"
