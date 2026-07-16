#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  SELECTED="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ "$SELECTED" == */Xcode*.app/Contents/Developer && -d "$SELECTED" ]]; then
    export DEVELOPER_DIR="$SELECTED"
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  else
    echo "Full Xcode is required for Swift Testing. Install free Xcode from the Mac App Store or Apple Developer downloads." >&2
    exit 1
  fi
fi

echo "Using $DEVELOPER_DIR"
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -version

# Xcode 27 beta can build without executing when no filter is supplied. A
# match-all filter executes every discovered Swift Testing case on both stable
# and beta Xcode toolchains.
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/swift test --package-path "$MACOS_DIR" --filter '.*'
