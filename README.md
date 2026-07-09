# VERITY

A local-first study companion for macOS: schedule tracking, homework, and course/syllabus progress for any
curriculum or board, plus a built-in AI research assistant that helps you build out course content. Your data
lives entirely in a plain-text [Obsidian](https://obsidian.md) vault on your own disk — VERITY never uploads
anything, and there's no account, server, or cloud sync involved.

## Features

- **Course & syllabus tracking** — break any subject into chapters/topics, mark progress, and track syllabus
  coverage against your board's official weightings.
- **Homework tracker** — add, edit, and clear homework with due dates and time estimates.
- **Time logging** — log study/homework sessions per course and topic.
- **AI research assistant** — connect Claude, Codex, or Antigravity (whichever you already have, or let VERITY
  install and log you into one) to research and draft course content. Every change is proposed first and only
  written to your vault after you explicitly approve it — the assistant never edits files on its own.
- **Menu-bar native app** — runs as a small always-on macOS app with a menu-bar icon, not a browser tab.
- **Your data, your format** — everything is stored as plain Markdown tables in your own vault. Nothing is
  proprietary, nothing is locked in.

## Install

Download the latest `.dmg` from [Releases](../../releases), open it, and drag `VERITY.app` into
`/Applications`.

On first launch you'll either point VERITY at an existing Obsidian vault or let it create a fresh one for you
at `~/VERITY/Vault` — no manual configuration required. App settings (which vault, which port) live in
`~/Library/Application Support/VERITY/config.json`, never inside the app bundle or in this repo.

**Gatekeeper warning on first open**: the app is ad-hoc signed, not notarized through a paid Apple Developer
account, so macOS will show an "unidentified developer" prompt the first time. Right-click `VERITY.app` →
Open, then confirm — this is a one-time step, not a sign of anything actually being wrong.

## Updates

VERITY checks GitHub Releases for a newer version on every launch and installs it automatically the next time
you quit the app — no manual downloads after the first install.

## The menu-bar icon

VERITY runs as a small persistent service, similar to apps like Dropbox or 1Password. The menu-bar icon shows
whether the server is running and gives you quick access to open the app, check for updates, or uninstall —
you don't need to keep a window open for VERITY to keep working in the background.

## Privacy & data

- All data is stored as Markdown files in the Obsidian vault you choose. Nothing leaves your machine except
  the specific request text you explicitly send to an AI provider (Claude/Codex/Antigravity) when using the
  research assistant — and even then, only after you've reviewed and approved what it's allowed to change.
- No telemetry, no analytics, no account system.

## Development

This is a monorepo: `apps/server` (Express + TypeScript API), `apps/web` (React + Vite frontend), and
`apps/desktop` (Electron shell that wraps both into a native app).

```bash
npm install && npm run build && npm run start --workspace=apps/server
```

The dev server reads `VAULT_PATH`/`PORT` from a root `.env` file (copy `.env.example` and set your own vault
path). This dev workflow — cloning the repo and running these commands from a terminal — is the only way to
reach "dev mode." It has no effect on, and is not reachable from, the packaged `.app`; a regular installed-app
user never sees or can accidentally enable it.

To build the desktop app + installer yourself, without publishing a release:

```bash
cd apps/desktop && npm install && npm run dist
```

Produces `apps/desktop/dist-electron/VERITY-<version>-arm64.dmg`. To actually publish a new version as a
GitHub Release (which is what the auto-updater checks against), bump `version` in
`apps/desktop/package.json`, then:

```bash
cd apps/desktop
export GH_TOKEN=<a GitHub personal access token with repo scope>
npm run release
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned work.
