# VERITY Roadmap

This is a living plan for where VERITY goes after v1.0.0. Nothing here is scheduled — it's
a backlog of real, concrete next steps, roughly grouped by theme.

## 1. A more powerful AI research tool

- **Deeper web research.** Today's web access is Playwright MCP (browse + read) plus each
  provider's own built-in search. Next: give the Research agent a proper multi-source
  synthesis pass — fetch several pages, cross-check them against each other, and only then
  propose content, instead of proposing after the first plausible source.
- **PDF and image ingestion.** Attachments currently work best as plain text. Real course
  material is often a scanned PDF or a photographed textbook page. Add PDF text extraction
  and OCR before handing attachment content to the assistant.
- **Long-running research jobs.** A deep "build out this entire subject" request can take
  many minutes across many turns. Support a background job model — kick off a research task,
  see progress, come back later — instead of one request blocking one HTTP response.
- **Source citation and confidence.** When the assistant proposes content from a web source,
  keep a durable record of what it pulled from where, so the student (or a parent/teacher)
  can trace a claim back to its origin, not just trust the model.
- **Provider parity.** Antigravity's `--continue`/`--conversation` flags don't reliably
  resume context across cold invocations (worked around today by prepending history into
  the prompt, which doesn't scale forever). Revisit if/when Antigravity's CLI matures, or
  find an alternative approach for very long research sessions.

## 2. Customization

- **Generic curriculum model.** The vault scaffold and block-type system are still shaped
  around the Boards/Competition split that fits Krish's own use case. Make the subject list,
  block types (First Pass/Drill/Timed Benchmark, etc.), and syllabus structure fully
  user-defined instead of hardcoded, so a different student's curriculum isn't fighting the
  app's assumptions.
- **Configurable AI behavior.** Let the user edit the Ask/Research system prompts from
  Settings instead of them being fixed strings in the server — useful once the tool has more
  than one real user.
- **Multiple vaults / profiles.** Right now the app points at exactly one vault. Supporting
  a vault switcher would matter for a household with more than one student, or for someone
  who wants a separate "test" vault.
- **Theming.** The dark ATC control-board look is deliberate and good, but a light-mode or
  alternate palette option is a reasonable ask once there's more than one user with an opinion.

## 3. Cross-platform

The app is macOS-only right now in several concrete ways, not just "untested elsewhere":

- `apps/desktop/main.js` shells out to macOS-specific commands (`open -a Terminal`,
  `open -a Antigravity`) for the login-flow smoothing — Windows/Linux need real equivalents
  (a real terminal emulator invocation on Windows, `xterm`/`x-terminal-emulator` or similar
  on Linux).
- `electron-builder`'s config only targets `mac` (`dmg`/`zip`). Adding `win` (NSIS installer)
  and `linux` (AppImage/deb) targets, plus testing the app actually runs there, is real work,
  not a config toggle.
- The PATH-resolution fix (`$SHELL -ilc 'echo $PATH'`) is Unix-shell-specific. Windows needs
  its own equivalent (reading the registry-based user PATH, since Windows doesn't have the
  same "GUI apps get a minimal PATH" problem in quite the same way, but Node/npm-based CLI
  discovery still needs verifying there).
- Claude/Codex/Antigravity's own install mechanisms differ per OS — the current
  `npm install -g` / curl-script approach needs Windows (likely a `.exe`/npm) and Linux
  equivalents confirmed for each provider.
- Code signing and notarization: today's `.dmg` is unsigned (no paid Apple Developer
  account), so Gatekeeper shows a real warning on first launch. A public release aimed at
  non-technical users benefits from proper signing — same story for Windows (Authenticode)
  if that platform gets added.

## 4. Distribution and reliability

- **Zero-dependency provider install.** Claude/Codex both install via `npm`, which itself
  requires Node.js already present — a genuinely fresh machine can't bootstrap this on its
  own today (confirmed and documented as a real limitation in v1.0.0). Antigravity's
  self-contained installer script doesn't have this problem. Worth exploring: bundling a
  minimal Node runtime with the app (Electron already ships one internally) so `npm install -g`
  can run against it without requiring a separate system-wide Node install.
- **Automated tests.** Everything in v1.0.0 was verified by hand against the live service.
  A real test suite (at least for the parsers, the propose/apply safety gate, and the
  provider-invocation argument-building logic) would catch regressions faster than another
  manual pass every time.
- **CI.** Wire up GitHub Actions to run typecheck/build (and eventually tests) on every push,
  so a broken commit is caught before it's tagged as a release.
