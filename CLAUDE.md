# VERITY — AI agent instructions

This is the single instructions file for any AI coding agent (Claude, Codex, Antigravity, or otherwise)
working in this repository. It replaces any older/scattered per-tool instruction files — if you find another
one, this file wins.

## What this app is

VERITY is a local-first, single-user macOS desktop app: a study/course/homework tracker that reads and writes
plain Markdown files in an "Obsidian vault" folder the user points it at (or that the app auto-creates). It
ships as a signed-ad-hoc `.dmg`/`.app` via Electron. There is no server, no accounts, no cloud sync — all
state is either in the vault (user's study data) or in a hidden per-user config file.

## Repo layout (npm workspaces monorepo)

- `apps/server` — Express + TypeScript API. Compiled with `tsc` then bundled with `esbuild` into a single
  `dist/index.js` (all deps inlined — no `node_modules` needed at runtime, see "Packaging gotchas" below).
  - `src/parsers/` — read-only parsers for vault Markdown (`blockLibrary.ts` = course/topic block banks,
    `syllabus.ts` = syllabus checklist).
  - `src/stores/` — read/write persistence for vault Markdown tables (homework, course cursor, schedule,
    time log, DISPATCH chat sessions).
  - `src/routes/` — Express routers, one per resource (`courses`, `homework`, `schedule`, `stats`, `timeLog`,
    `assistant`).
  - `src/providers/` — the multi-provider AI CLI abstraction (Claude / Codex / Antigravity): detection,
    install, login, and invocation. `index.ts` is the entry point; `setup.ts` handles the install/login flow;
    `mcp-config.json` configures the tools/MCP servers granted to each provider.
  - `src/utils/` — `markdown.ts` (table parse/write helpers), `safeFs.ts` (path-traversal-safe filesystem
    helpers — **always** use these instead of raw `fs` when a path is derived from user input or a vault-
    relative string), `validate.ts`.
  - `src/index.ts` — server bootstrap. Handles the "no vault configured yet" first-run state (serves a setup
    page, mounts nothing) vs. the normal state (`mountNormalRoutes()` mounts every router into the
    already-running process — no restart needed once setup completes).
- `apps/web` — React + Vite frontend, one view per screen under `src/views/`: `RackView` (course composer),
  `ChronoView` (schedule + timer), `PendingView` (homework), `RosterView` (syllabus), `TallyView` (stats),
  `DispatchView` (the AI research/edit assistant, chat-session based). `src/theme.css` is the entire visual
  system — see `DESIGN.md`. `public/setup.html` is a **separate, static, non-React** onboarding wizard served
  directly by the Express server before a vault is configured — it has its own inline CSS/JS, it is not part
  of the Vite bundle.
- `apps/desktop` — Electron shell. `main.js` spawns the compiled server as a child process, opens a
  `BrowserWindow` pointed at `http://localhost:4477`, and adds a menu-bar `Tray`. `scripts/prepare.js` stages
  the server+web builds into `apps/desktop/server` and `apps/desktop/web/dist` before packaging;
  `scripts/after-sign.js` ad-hoc codesigns the built `.app`; `scripts/create-dmg.js` builds the installer.
- `config/`, `launchd/`, `scripts/install-launchd.sh` — legacy always-on-service (launchd) setup for running
  from a source checkout in dev. Not part of the shipped `.app` (Electron owns process lifecycle there via
  its own login-item registration).

## How the AI research assistant works (DISPATCH)

The in-app assistant (`apps/server/src/routes/assistant.ts` + `src/providers/`) is **propose-then-approve,
vault-content only**: it can read the vault and the CLI's own tools (web search, MCP), but every file change
it wants to make comes back as a structured proposal the user must explicitly approve before anything is
written — enforced by `POST /api/assistant/apply` being the *only* code path that writes to the vault on the
assistant's behalf. It never touches this app's own source code and never gets Bash/Edit/Write tool access
directly. Do not weaken this gate.

## Editing vault content vs. editing app code

- **Vault content** (course block banks, syllabus checklist) lives in the *user's* vault, not this repo — do
  not edit vault Markdown files as if they were part of the app. The block-bank format is a Markdown table;
  match the exact column headers `parsers/blockLibrary.ts` expects for a given section heading (e.g.
  `## Science Physics Block Bank`) or the parser will silently skip it.
- **App code** is everything in `apps/`. Follow the "Packaging gotchas" section below religiously — this repo
  has a documented history of packaging bugs from dev/production path assumptions silently diverging.

## Packaging gotchas (read before touching anything in `apps/desktop`)

Electron's asar packing means `__dirname` inside a packed module is a *virtual* path — not spawnable, and not
necessarily where you think. Two real bugs already happened here from this:
1. `spawn()`-ing the server needs `server/dist/index.js` and `server/package.json` on the **real** filesystem
   (`asarUnpack` in `apps/desktop/package.json`), and the server is esbuild-bundled specifically so it needs
   no `node_modules` at runtime.
2. `apps/server/src/index.ts` resolves the web build via `path.resolve(__dirname, '../../web/dist/...')` —
   this only works if the packaged layout mirrors the dev-mode layout exactly (`server/dist` next to
   `web/dist`). `apps/desktop/scripts/prepare.js` stages the web build into `apps/desktop/web/dist/` (not
   flat `apps/desktop/web/`) specifically to preserve this. If you change either side, change both, and
   verify by spawning the *packaged, unpacked* server directly and curling `/`, `/setup`, and
   `POST /api/setup` — do not assume it works from reading the code.

## Build & test

```bash
npm install && npm run build          # builds apps/server + apps/web
npm run start --workspace=apps/server # run the server directly (dev)
cd apps/desktop && npm run dist       # build the local .app + .dmg (no publish)
cd apps/desktop && npm run release    # build AND publish a GitHub Release (needs GH_TOKEN)
```

There is no automated test suite yet — verification is manual: run the build, spawn the server, curl the
routes, and/or use the browser preview tools against `apps/web`'s dev server (`.claude/launch.json` has both
launch configs already defined).

## Security rules

- Never hardcode this developer's name, absolute home-directory paths, or any personal identifying detail —
  this repo is public. Run a secrets/personal-path grep before every commit that touches config or docs.
- Never commit `.env`, `config/local.env`, or resolved `launchd/*.plist` (all gitignored already — keep it
  that way).
- Any path built from user input (vault path, course/topic names, attachment filenames) must go through
  `apps/server/src/utils/safeFs.ts`, never raw `fs` calls.
