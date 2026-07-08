# VERITY

A personal study-schedule, homework, and course-tracking app for any curriculum, board, or self-directed
study plan. Reads and writes to an Obsidian vault as its sole data store, with a built-in AI research/edit
assistant (Claude, Codex, or Gemini) for building out course content.

## Install (recommended)

Drag `VERITY.app` (from the built `.dmg`) into `/Applications` and open it. On first launch it either lets
you point at an existing Obsidian vault or auto-creates a fresh empty one at `~/VERITY/Vault` — no manual
config needed. Settings live in `~/Library/Application Support/VERITY/config.json`.

## Development

```bash
npm install && npm run build && npm run start --workspace=apps/server
```

The dev server reads `VAULT_PATH`/`PORT` from a root `.env` file (see `.env.example`) — copy it and set your
own vault path for local development. This is only used when no installed-app config exists yet.

To build the desktop app + installer yourself:

```bash
cd apps/desktop && npm install && npm run dist
```

Produces `apps/desktop/dist-electron/VERITY.dmg` and the `.app` bundle.

## Documentation

Full usage guide: see `Reference/Study-Command-Center-Guide.md` in your vault (created via the app's guide,
if present).
