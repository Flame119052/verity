# Migrating from VERITY 1.x to VERITY Native

VERITY Native is a separate, real macOS application. It does not wrap the existing React app and it does not start the Express server. SwiftUI and AppKit render the interface; Foundation reads and writes the vault directly.

## Safe migration and optional coexistence

1. Keep the current VERITY 1.x application only if you want a rollback copy.
2. Open VERITY Native. If the former vault is detected, verify the displayed path and choose **Use previous VERITY vault**. Otherwise choose the folder manually.
3. Confirm that RACK, PENDING, ROSTER, TALLY, and DISPATCH show the expected data.
4. Make one low-risk change, quit Native, and confirm VERITY 1.x and Obsidian can both read it.
5. Do not run both apps while actively editing the same row. Native detects stale coordinated writes, but VERITY 1.x predates that protection.

Native stores its own configuration under `Application Support/VERITY Native`; it does not replace the 1.x configuration. Study data remains in the selected Markdown vault. Removing either application does not remove the vault.

Native can optionally register itself at login and schedule local study-strip notifications. Both are off until the user enables them in Settings. Stable is the default update channel; Beta additionally receives prereleases. Native 2 is the recommended application; Electron 1.x is sunset.

## First-run choices

- **Use previous VERITY vault** appears only when a readable legacy configuration exists. It is a suggestion, never an automatic migration.
- **Choose Existing Vault** accepts a VERITY or compatible Obsidian folder and validates that it is readable and writable.
- **Create New Vault** atomically creates the supported `Progress`, `Boards`, and `Courses` structure. It refuses to scaffold over an existing destination.

## DISPATCH boundary

Provider credentials remain owned by Claude, Codex, or Antigravity. Native only discovers their command-line tools. Providers cannot write the vault directly. A proposed file change shows the coordinated current and proposed contents side by side; Apply is bound to that exact snapshot and fails if an external edit occurs first.

## Rollback

To return to VERITY 1.x, quit Native and open the former app against the same vault. No conversion step is required. If Native's saved location is wrong, choose **Change Vault**; clearing Native's app settings is never required to protect or recover the vault.

## Release profiles

The default zero-cost profile requires no Apple subscription. It uses:

- Free Xcode with a supported macOS SDK for the complete local test suite.
- An ad-hoc code signature with strict nested verification.
- A SHA-256 manifest for the DMG and update ZIP.
- The production HTTPS Sparkle appcast and VERITY EdDSA key already configured in Keychain.

Apple's Developer ID and notarization services require paid program membership. If those credentials are ever supplied, the same build scripts can add hardened-runtime signing, notarization, and stapling. Without them, Gatekeeper may require the standard Control-click **Open** or Privacy & Security **Open Anyway** path. VERITY never asks users to disable Gatekeeper.

The installer includes **Uninstall VERITY.app**. It can remove the native app and optionally its native settings, timer recovery, and caches. It always preserves the Markdown vault, VERITY 1.x, provider tools, and provider credentials.
