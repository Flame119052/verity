#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$MACOS_DIR/dist/VERITY.app"
UNINSTALLER_APP="$MACOS_DIR/dist/Uninstall VERITY.app"
DMG="$MACOS_DIR/dist/VERITY-Native.dmg"

if [[ ! -d "$APP" || ! -d "$UNINSTALLER_APP" ]]; then
  "$SCRIPT_DIR/build-app.sh"
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/verity-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP" "$STAGING/VERITY.app"
/usr/bin/ditto "$UNINSTALLER_APP" "$STAGING/Uninstall VERITY.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
/usr/bin/hdiutil create \
  -volname "VERITY" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG"
if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  /usr/bin/codesign --verify --strict --verbose=2 "$DMG"
fi
/usr/bin/hdiutil verify "$DMG"

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  /usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$DMG"
  /usr/bin/xcrun stapler validate "$DMG"
fi

echo "$DMG"
