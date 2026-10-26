#!/usr/bin/env bash
# Source from release.sh; these helpers never search a different build configuration.
release_app_path() {
  local candidate="$1/Build/Products/$2/$3.app"
  if [[ ! -d "$candidate" ]]; then
    echo "release: missing built app at $candidate; refusing another configuration" >&2
    return 1
  fi
  printf '%s\n' "$candidate"
}

release_sign_nested() (
  set -o pipefail
  local app_path="$1" identity="$2" nested
  [[ -d "$app_path/Contents/Frameworks" ]] || return 0
  # Contents before containers, including dylibs inside versioned frameworks.
  find "$app_path/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 |
  while IFS= read -r -d '' nested; do
    codesign --force --options runtime --timestamp --sign "$identity" "$nested" || return
  done
)
