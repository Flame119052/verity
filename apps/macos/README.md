# VERITY Native for macOS

This is VERITY's real macOS application. It is built with SwiftUI, AppKit, Foundation, and ServiceManagement. It does not embed Electron, Node.js, a browser engine, WebView, or the React application.

The native app reads and writes the same Markdown vault contract as the current VERITY release. Its configuration and timer recovery data are separate, so the native and Electron builds can coexist during migration.

## Local verification

```bash
apps/macos/scripts/test.sh
swift run --package-path apps/macos verity-native-checks
apps/macos/scripts/compare-legacy-parity.sh
apps/macos/scripts/build-app.sh
apps/macos/scripts/create-dmg.sh
```

Run the complete local release gate with:

```bash
apps/macos/scripts/release-gate.sh
```

The gate compiles the native application and standalone uninstaller, runs the compatibility and safety checks, builds and verifies the app bundle, DMG, and update ZIP, and rejects any HTML, JavaScript, or Electron payload in the app. The golden parity script additionally requires the root `npm ci` dependencies and compares a representative legacy vault through the TypeScript and Swift parsers.

## Signed automatic updates

Sparkle 2.9.2 is pinned through Swift Package Manager and embedded in the packaged app. VERITY's public EdDSA key and repository-owned HTTPS appcast URL are embedded in `Info.plist`; the private key remains in the login Keychain under account `app.verity.native`.

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/Flame119052/verity/releases/download/v2.0.1/" \
SPARKLE_KEY_ACCOUNT="app.verity.native" \
apps/macos/scripts/create-update-artifacts.sh
```

Create a symlink-preserving update ZIP and signed appcast from the exact packaged app with:

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/Flame119052/verity/releases/download/v2.0.1/" \
apps/macos/scripts/create-update-artifacts.sh
```

The private update key must stay outside this repository. `SPARKLE_CHANNEL=beta` creates a beta-channel appcast entry; omit it for stable releases.

## Developer ID and notarization

Ad-hoc signing is the local default. For a distributable build, provide the Developer ID Application identity:

```bash
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" apps/macos/scripts/build-app.sh
```

Then submit the DMG using an `xcrun notarytool` keychain profile:

```bash
NOTARY_KEYCHAIN_PROFILE="verity-notary" apps/macos/scripts/create-dmg.sh
```

Full Developer ID signing and notarization require paid Apple Developer Program membership plus the release owner's Apple credentials. They are not part of the zero-cost profile and must never be implied. See `docs/ZERO_COST_DISTRIBUTION.md` for the ad-hoc signing, checksum, Sparkle signature, and honest Gatekeeper workflow.

The DMG also contains **Uninstall VERITY.app**, and the same removal engine is embedded in the installed app under **VERITY → Uninstall VERITY…** and **Settings → About & Removal**. It can remove the installed native app and, with a separate checkbox, its local settings and caches. It never deletes the selected Markdown vault, Electron legacy app, provider tools, or provider credentials.

Settings → Assistant CLIs offers one-click setup. VERITY runs the official global npm packages for Claude and Codex, or downloads Google's official Antigravity installer script over HTTPS and executes it as a separate file without a shell pipe. After installation it opens the provider-owned sign-in command in Terminal; Codex uses device authorization, while Antigravity may request a one-time Google OAuth code. Credentials remain outside VERITY.
