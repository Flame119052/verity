# VERITY Native 2.0.2

VERITY is now a real SwiftUI and AppKit macOS application. It no longer needs Electron, React, Node.js, a localhost server, WebView, an account, or a cloud backend to run.

This is the recommended VERITY release. Electron 1.x is now a retained legacy compatibility edition.

## Highlights

- A completely redesigned Settings control center with detailed General, Study, Assistant CLI, Updates, Privacy, and About & Removal stations.
- An in-app **Uninstall VERITY…** command in Settings and the application menu. The embedded uninstaller preserves the Markdown vault, legacy app, provider CLIs, and credentials.
- One-click provider setup: VERITY automatically runs the official Claude, Codex, or Antigravity CLI installer, then opens only the secure sign-in step when needed. Codex uses device authorization and Antigravity exposes its Google OAuth authorization-code flow in Terminal.
- The status-menu layer is now owned directly by AppKit, so it refreshes on every open and always dismisses after a command instead of leaving a stranded SwiftUI menu.

- Six native workspaces: RACK, CHRONO, PENDING, ROSTER, TALLY, and DISPATCH.
- The original Strip Board identity is preserved as a flush ATC-style board with a VERITY/STUDY OPS plate, six LED hardware tabs, paper strips, live clock/timer instrumentation, and a function-key rail—without a generic macOS sidebar.
- Exact compatibility with the existing Markdown vault contract, including coordinated writes and conflict rejection when Obsidian changes a file first.
- A persistent study timer, Dock badge, opt-in native reminders, launch at login, keyboard commands, native settings, and a menu-bar cockpit.
- DISPATCH sessions for Claude, Codex, and Antigravity with safe subprocess limits, attachments, cancellation, visible line diffs, Apply One, and transactional Apply All.
- An approval-only assistant write boundary: provider output cannot change the vault until the user reviews and applies an exact, unexpired snapshot.
- Sparkle 2 stable/beta channels with a Keychain-backed EdDSA signature and repository HTTPS appcast, a native uninstaller, DMG, update ZIP, and SHA-256 manifest generation.
- A true dismissing status menu that exposes timer, next-strip, urgent-homework, quick-add, update, settings, launch-at-login, and quit commands without a persistent popover.

## Migration

VERITY Native can coexist with VERITY 1.x and opens the same vault without conversion. The former app may be kept as an optional rollback copy. Removing Native never deletes the Markdown vault or provider tools.

## Zero-cost distribution note

The public build is ad-hoc signed and Sparkle-EdDSA signed. Apple reserves Developer ID and notarization for paid program members, so first launch may require Control-click **Open** or **System Settings → Privacy & Security → Open Anyway**. This build does not disable Gatekeeper and is never described as notarized.
