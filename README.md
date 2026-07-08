# VERITY

A personal study-schedule, homework, and course-tracking app for any curriculum, board, or self-directed
study plan. Reads and writes to an Obsidian vault as its sole data store, with a built-in AI research/edit
assistant (Claude, Codex, or Antigravity) for building out course content.

## Install (recommended)

Drag `VERITY.app` (from the built `.dmg`) into `/Applications` and open it. On first launch it either lets
you point at an existing Obsidian vault or auto-creates a fresh empty one at `~/VERITY/Vault` — no manual
config needed. Settings live in `~/Library/Application Support/VERITY/config.json`.

The app is unsigned (no paid Apple Developer account) — macOS Gatekeeper will warn on first open. Right-click
the app → Open, or System Settings → Privacy & Security → "Open Anyway", once.

## Updates

VERITY checks GitHub Releases for a newer version automatically on launch (via `electron-updater`) and
installs it in the background the next time the app quits — no manual download needed once v1.0.0 is
installed. To ship a new version yourself:

```bash
cd apps/desktop
export GH_TOKEN=<a GitHub personal access token with repo scope>
npm run release
```

This builds the `.dmg`/`.zip`, generates the update feed metadata (`latest-mac.yml`), and uploads everything
to a new GitHub Release on this repo — that's the entire publish step. Bump `version` in
`apps/desktop/package.json` first so the release is actually newer than what's already out.

## Development

```bash
npm install && npm run build && npm run start --workspace=apps/server
```

The dev server reads `VAULT_PATH`/`PORT` from a root `.env` file (see `.env.example`) — copy it and set your
own vault path for local development. This is only used when no installed-app config exists yet.

To build the desktop app + installer yourself (without publishing):

```bash
cd apps/desktop && npm install && npm run dist
```

Produces `apps/desktop/dist-electron/VERITY-<version>-arm64.dmg` and the `.app` bundle.

## Documentation

- Full usage guide: see `Reference/Study-Command-Center-Guide.md` in your vault (created via the app's
  guide, if present).
- Future plans: see `ROADMAP.md`.
