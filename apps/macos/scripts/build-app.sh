#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$MACOS_DIR/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="$MACOS_DIR/dist"
APP="$OUTPUT_DIR/VERITY.app"
UNINSTALLER_APP="$OUTPUT_DIR/Uninstall VERITY.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MACOS_DIR/Resources/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MACOS_DIR/Resources/Info.plist")"

swift build --package-path "$MACOS_DIR" -c "$CONFIGURATION" --product VERITY
swift build --package-path "$MACOS_DIR" -c "$CONFIGURATION" --product verity-uninstaller

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) TRIPLE="arm64-apple-macosx" ;;
  x86_64) TRIPLE="x86_64-apple-macosx" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

BINARY="$MACOS_DIR/.build/$TRIPLE/$CONFIGURATION/VERITY"
UNINSTALLER_BINARY="$MACOS_DIR/.build/$TRIPLE/$CONFIGURATION/verity-uninstaller"
if [[ ! -x "$BINARY" ]]; then
  echo "Built VERITY binary not found at $BINARY" >&2
  exit 1
fi
if [[ ! -x "$UNINSTALLER_BINARY" ]]; then
  echo "Built VERITY uninstaller binary not found at $UNINSTALLER_BINARY" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/VERITY"
cp "$MACOS_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$MACOS_DIR/Resources/mcp-config.json" "$APP/Contents/Resources/mcp-config.json"
cp "$ROOT_DIR/apps/desktop/assets/icon.icns" "$APP/Contents/Resources/VERITY.icns"

DESIGN_RESOURCES="$MACOS_DIR/.build/$TRIPLE/$CONFIGURATION/VERITYNative_VerityDesign.bundle"
if [[ ! -d "$DESIGN_RESOURCES" ]]; then
  echo "Built VerityDesign resource bundle not found at $DESIGN_RESOURCES" >&2
  exit 1
fi
/usr/bin/ditto "$DESIGN_RESOURCES" "$APP/Contents/Resources/VERITYNative_VerityDesign.bundle"

SPARKLE_FRAMEWORK="$MACOS_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework was not resolved by SwiftPM." >&2
  exit 1
fi
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# VERITY is not App-Sandboxed, so Sparkle's sandbox-only XPC services are unnecessary.
# Removing them is supported by Sparkle and reduces the nested signing surface.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

if ! /usr/bin/otool -l "$APP/Contents/MacOS/VERITY" | /usr/bin/grep -F -q '@executable_path/../Frameworks'; then
  /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/VERITY"
fi

if [[ -n "${SPARKLE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  if [[ -z "${SPARKLE_FEED_URL:-}" || -z "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    echo "SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY must be supplied together." >&2
    exit 1
  fi
  case "$SPARKLE_FEED_URL" in
    https://*) ;;
    *) echo "SPARKLE_FEED_URL must use HTTPS." >&2; exit 1 ;;
  esac
  /usr/bin/plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
  /usr/bin/plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
  /usr/bin/plutil -replace SUEnableAutomaticChecks -bool true "$APP/Contents/Info.plist"
  /usr/bin/plutil -replace SUAutomaticallyUpdate -bool false "$APP/Contents/Info.plist"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$SPARKLE_B/Autoupdate"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$SPARKLE_B/Updater.app"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$UNINSTALLER_APP"
mkdir -p "$UNINSTALLER_APP/Contents/MacOS" "$UNINSTALLER_APP/Contents/Resources"
cp "$UNINSTALLER_BINARY" "$UNINSTALLER_APP/Contents/MacOS/verity-uninstaller"
cp "$ROOT_DIR/apps/desktop/assets/icon.icns" "$UNINSTALLER_APP/Contents/Resources/VERITY.icns"
/usr/bin/plutil -create xml1 "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Uninstall VERITY" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Uninstall VERITY" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "app.verity.native.uninstaller" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "verity-uninstaller" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIconFile -string "VERITY.icns" "$UNINSTALLER_APP/Contents/Info.plist"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$UNINSTALLER_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$UNINSTALLER_APP"

echo "$APP"
