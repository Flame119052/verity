# VERITY Native

**VERITY Native 2 is the recommended macOS app.** It is a genuine SwiftUI/AppKit application—not a webpage, WebView, localhost UI, or Electron wrapper.

VERITY is a local-first study command center for planning a day, tracking homework, logging focused time, following course progress, and working with an optional approval-gated AI assistant. Study data remains ordinary Markdown in a folder you choose, including an existing Obsidian vault.

## Install the recommended app

1. Open the [latest release](../../releases/latest).
2. Download `VERITY-Native.dmg`.
3. Open the DMG and drag `VERITY.app` to Applications.
4. Because this free build is not Apple-notarized, Control-click the app, choose **Open**, then confirm **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**.

VERITY is ad-hoc code signed, its Sparkle update archive is EdDSA signed, and release downloads include SHA-256 checksums. Apple requires a paid Developer Program membership for Developer ID and notarization; VERITY does not misrepresent the free build as notarized and never asks you to disable Gatekeeper.

## What Native includes

- RACK for the daily strip-board schedule.
- CHRONO for persistent study timers and verified time logs.
- PENDING for homework capture, priority, editing, completion, and deletion.
- ROSTER for syllabus and course-cursor progress.
- TALLY for weekly study and completion statistics.
- DISPATCH for Claude, Codex, or Antigravity sessions, attachments, research, and reviewed vault proposals.
- A real macOS menu bar, complete application menus and shortcuts, Settings, Dock badges, notifications, launch-at-login controls, signed automatic updates, and a native uninstaller.
- The original VERITY Strip Board design: stencil command plate, LED tabs, paper strips in colored holders, live instrumentation, and function-key rail.

There are no VERITY accounts, hosted dashboards, analytics, telemetry, or subscription service.

## Your data and privacy

The selected vault is the source of truth. Native reads and writes the same Markdown formats as VERITY 1.x and Obsidian, with path-confined coordinated writes and stale-edit rejection. Opening and closing a vault does not rewrite it.

Nothing is sent to an AI provider unless you use DISPATCH. Provider credentials remain owned by the provider's command-line tool. A provider cannot write the vault directly: it can return a proposal, but VERITY writes only after you inspect the current/proposed contents and explicitly apply the exact reviewed snapshot.

See [Native migration](docs/NATIVE_MIGRATION.md), [zero-cost distribution](docs/ZERO_COST_DISTRIBUTION.md), and the [native architecture and verification contract](NATIVE_TRANSITION.md).

## Migrating from VERITY 1.x

Native can open the existing VERITY 1.x vault without conversion. On first launch, choose the former vault (or accept the detected suggestion), verify the six workspaces, and continue. Native keeps separate app settings, so the old installation can remain available as a rollback copy.

Do not actively edit the same vault from both apps at once. Native detects stale coordinated writes; Electron 1.x predates that protection.

## Electron 1.x legacy edition

The Electron edition is sunset and retained only for compatibility and rollback. **It is not the recommended download and receives no new product development.** The final compatibility build is [VERITY Legacy 1.1.6](../../releases/tag/v1.1.6); the prior 1.1.5 release and its original assets remain available.

Legacy still uses Electron, React, Node.js, and a localhost Express process. It can read the same vault, displays a permanent **LEGACY · GET NATIVE** notice, and links directly to the recommended Native release.

## Build and verify

Native requires full Xcode:

```bash
apps/macos/scripts/test.sh
swift run --package-path apps/macos verity-native-checks
apps/macos/scripts/compare-legacy-parity.sh
apps/macos/scripts/release-gate.sh
```

The retained Electron baseline is built separately:

```bash
npm ci
npm run build:legacy
cd apps/desktop && npm run dist
```

## Uninstall

The Native DMG contains **Uninstall VERITY.app**. It removes the Native app and, if requested, Native settings and caches; it always preserves the Markdown vault, provider tools, provider credentials, and the separate Electron legacy installation.
