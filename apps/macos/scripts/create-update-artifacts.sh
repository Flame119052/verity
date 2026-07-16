#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$MACOS_DIR/../.." && pwd)"
APP="$MACOS_DIR/dist/VERITY.app"
ARCHIVES_DIR="${ARCHIVES_DIR:-$MACOS_DIR/dist/updates}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MACOS_DIR/Resources/Info.plist")}"
ZIP="$ARCHIVES_DIR/VERITY-$VERSION.zip"
SPARKLE_BIN="$MACOS_DIR/.build/artifacts/sparkle/Sparkle/bin"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-app.verity.native}"

if [[ ! -d "$APP" ]]; then
  "$SCRIPT_DIR/build-app.sh"
fi
mkdir -p "$ARCHIVES_DIR"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ -n "${SPARKLE_DOWNLOAD_URL_PREFIX:-}" ]]; then
  ARGS=(--account "$SPARKLE_KEY_ACCOUNT" --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX" --link "${SPARKLE_PRODUCT_URL:-https://github.com/Flame119052/verity}")
  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
  fi
  if [[ -n "${SPARKLE_CHANNEL:-}" ]]; then
    ARGS+=(--channel "$SPARKLE_CHANNEL")
  fi
  "$SPARKLE_BIN/generate_appcast" "${ARGS[@]}" "$ARCHIVES_DIR"
  cp "$ARCHIVES_DIR/appcast.xml" "${SPARKLE_APPCAST_DESTINATION:-$ROOT_DIR/appcast.xml}"
elif [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  "$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$ZIP"
else
  echo "Created unsigned local update archive. Set SPARKLE_DOWNLOAD_URL_PREFIX to sign with Keychain account $SPARKLE_KEY_ACCOUNT and generate an appcast." >&2
fi

if [[ -f "$MACOS_DIR/dist/VERITY-Native.dmg" ]]; then
  {
    (cd "$MACOS_DIR/dist" && /usr/bin/shasum -a 256 "VERITY-Native.dmg")
    (cd "$MACOS_DIR/dist/updates" && /usr/bin/shasum -a 256 "VERITY-$VERSION.zip")
  } > "$MACOS_DIR/dist/SHA256SUMS"
fi

echo "$ZIP"
