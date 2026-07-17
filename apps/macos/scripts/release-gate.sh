#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$MACOS_DIR/dist/VERITY.app"
UNINSTALLER_APP="$MACOS_DIR/dist/Uninstall VERITY.app"
DMG="$MACOS_DIR/dist/VERITY-Native.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MACOS_DIR/Resources/Info.plist")"

"$SCRIPT_DIR/test.sh"
swift run --package-path "$MACOS_DIR" verity-native-checks
"$SCRIPT_DIR/build-app.sh"
"$SCRIPT_DIR/create-dmg.sh"
"$SCRIPT_DIR/create-update-artifacts.sh"

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$UNINSTALLER_APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP/Contents/Helpers/verity-uninstaller"
/usr/bin/otool -L "$APP/Contents/MacOS/VERITY" | /usr/bin/grep -F -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
test -d "$APP/Contents/Frameworks/Sparkle.framework"
test -x "$APP/Contents/Helpers/verity-uninstaller"
test -f "$MACOS_DIR/dist/updates/VERITY-$VERSION.zip"
test -f "$APP/Contents/Resources/VERITYNative_VerityDesign.bundle/IBMPlexMono-Regular.ttf"
test -f "$APP/Contents/Resources/VERITYNative_VerityDesign.bundle/IBMPlexMono-SemiBold.ttf"
test -f "$APP/Contents/Resources/VERITYNative_VerityDesign.bundle/SairaStencilOne-Regular.ttf"

{
  (cd "$MACOS_DIR/dist" && /usr/bin/shasum -a 256 "VERITY-Native.dmg")
  (cd "$MACOS_DIR/dist/updates" && /usr/bin/shasum -a 256 "VERITY-$VERSION.zip")
} > "$MACOS_DIR/dist/SHA256SUMS"
CHECKSUMS_ACTUAL="$(mktemp "${TMPDIR:-/tmp}/verity-checksums.XXXXXX")"
{
  (cd "$MACOS_DIR/dist" && /usr/bin/shasum -a 256 "VERITY-Native.dmg")
  (cd "$MACOS_DIR/dist/updates" && /usr/bin/shasum -a 256 "VERITY-$VERSION.zip")
} > "$CHECKSUMS_ACTUAL"
/usr/bin/diff -u "$MACOS_DIR/dist/SHA256SUMS" "$CHECKSUMS_ACTUAL"
rm -f "$CHECKSUMS_ACTUAL"
echo "VERITY-Native.dmg: OK"
echo "VERITY-$VERSION.zip: OK"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/verity-release-gate.XXXXXX")"
cleanup_mount() {
  /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_POINT"
}
trap cleanup_mount EXIT
/usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet
test -d "$MOUNT_POINT/VERITY.app"
test -d "$MOUNT_POINT/Uninstall VERITY.app"
test -L "$MOUNT_POINT/Applications"
/usr/bin/hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$MOUNT_POINT"
trap - EXIT
/usr/bin/file "$APP/Contents/MacOS/VERITY" | /usr/bin/grep -q "Mach-O"

if /usr/bin/grep -R -n -E '/Users/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|GH_TOKEN[[:space:]]*=|APPLE_ID[[:space:]]*=|NOTARY_PASSWORD[[:space:]]*=' \
  "$MACOS_DIR/Sources" "$MACOS_DIR/Resources" "$MACOS_DIR/README.md"; then
  echo "Release gate failed: personal path or secret material found in native sources/resources." >&2
  exit 1
fi

if /usr/bin/find "$APP" \( -name '*.html' -o -name '*.js' -o -name '*Electron*' -o -name 'node' -o -name 'node_modules' \) | /usr/bin/grep -q .; then
  echo "Release gate failed: web or Electron payload found in the native app bundle." >&2
  exit 1
fi

if /usr/bin/strings "$APP/Contents/MacOS/VERITY" | /usr/bin/grep -E -q 'localhost:4477|WKWebView|Electron Framework'; then
  echo "Release gate failed: wrapper or localhost UI marker found in the native executable." >&2
  exit 1
fi

if /usr/bin/otool -L "$APP/Contents/MacOS/VERITY" | /usr/bin/grep -E -q 'Electron|node\.dylib|WebKit\.framework'; then
  echo "Release gate failed: browser or Electron runtime linkage found." >&2
  exit 1
fi

echo "VERITY native release gate passed."
