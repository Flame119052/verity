# design-sync notes — apps/web (study-command-center-web)

## Repo shape

`apps/web` is a Vite **app**, not a component library — no `dist/`, no
`.storybook/`, no published `.d.ts`. The converter's package-shape src-synth
fallback is used deliberately (see the skill's "Known limitations": tokens-only
DS handling extends naturally to this — a real-app source tree with real,
exported PascalCase components and no library packaging).

## Why a hand-written entry (`cfg.entry` → `.design-sync/synth-entry.tsx`)

The converter's default synth-entry mode re-exports **every** `src/*.tsx`
file it finds, including `main.tsx`. `main.tsx` has a top-level side effect —
`ReactDOM.createRoot(document.getElementById('root')).render(<App/>)` — which
throws in any environment without a real `#root` element (headless render
check, and the claude.ai/design runtime itself). That throw happens *inside*
the bundle's IIFE before `window.Verity` is assigned, so with the default
entry **all 15 components** failed `[BUNDLE_EXPORT]` at once — not a
per-component issue, a whole-bundle one.

Fix: `.design-sync/synth-entry.tsx` hand-lists named re-exports of the 15 real
components (no `main.tsx`). `cfg.entry` points at it; `cfg.componentSrcMap`
re-declares each name (required once `--entry` is set — the src synth fallback
that would otherwise discover components no longer runs) with `apps/web`-
relative paths (`cfg.srcDir: "apps/web/src"` makes `PKG_DIR` resolve there via
the `.design-sync-entry`'s package.json walk-up landing on the monorepo
root — see below).

**Re-sync risk**: if a new component is added to `apps/web/src`, it will NOT
appear automatically — add it to both `synth-entry.tsx` and
`componentSrcMap` by hand. This is the standing cost of not having a real
library build; re-syncs are not a bare re-run of the converter until that's
fixed.

## PKG_DIR resolution quirk (`--entry` mode)

With `cfg.entry` set, the converter resolves `PKG_DIR` by walking up from the
entry file's directory looking for the nearest `package.json` **with a
`name` field**. Since the entry lives at `.design-sync/synth-entry.tsx`,
that walk skips past `apps/web` (no package.json in `.design-sync/`) and
lands on the **monorepo root** `package.json` (`study-command-center`).
So every `PKG_DIR`-relative config field — `componentSrcMap`, `cssEntry`,
`srcDir` — is **repo-root-relative**, not `apps/web`-relative, e.g.
`"cssEntry": "apps/web/src/theme.css"` not `"src/theme.css"`. `extraFonts`
is workspaceRoot-relative (same root here) — `"node_modules/@fontsource/…"`.

## No `docsDir` — all `.prompt.md` synthesized

No `docs/` tree in this repo; every component's `.prompt.md` was synthesized
from its `.d.ts` + JSDoc + authored preview, not a real doc. `[DTS]` prop
extraction also came back as `[key: string]: unknown` for most components —
their real prop types are inline object-literal params in the source
(`board.tsx`, views), which the `.d.ts` extractor didn't flatten. Fine for now
(previews compose real props from the source directly), but a future
`dtsPropsFor` override would make the shipped `<Name>Props` interfaces useful
to the design agent instead of `unknown`.

## Provider

`cfg.provider = TimerProvider` is applied globally (wraps every preview).
Only `ChronoView` actually calls `useTimer()`; `TimerProvider` is a
side-effect-free `{children}` pass-through otherwise, so this is safe and
simpler than scoping it per-component.

## The 6 `*View` components render their real fault/loading states, not mocks

`RackView`, `ChronoView`, `PendingView`, `RosterView`, `TallyView`,
`DispatchView` all fetch from `apps/server`'s API internally (`api.ts`) with
no dependency-injection seam. In the design-sync sandbox those fetches fail,
and each view's own error-boundary path renders (`Fault`/`Loading` — this
app already handles that gracefully) — so their preview cards are honest,
not blank, and needed **no authored preview or mock layer**. This is also why
they were left un-authored (floor-card in the grading sense, though
render-check-clean) rather than composed with fake data: there is no seam to
inject fake data through without editing app source, and the fault-state
render is itself a real, representative state of these components.

**Re-sync risk**: if `apps/web/src/api.ts`'s base URL or fetch shape changes
such that requests no longer fail cleanly (e.g. they hang instead of
rejecting), these 6 previews could start rendering blank/loading forever.
Re-check the render check's screenshots for these 6 on any re-sync after an
`api.ts` change.

## Authored previews

`KeyHint`, `CoursePicker`, `Punch`, `TimerProvider` have real authored
previews under `previews/` — the only ones that needed fixing (KeyHint
rendered blank with default/floor props) or that benefited from showing their
real variant sweep (Punch's 5 adherence states, CoursePicker's grouped vs.
flat chip rows).

## Fonts / CSS

`main.tsx` (excluded from the entry, see above) is where `theme.css` and the
`@fontsource/ibm-plex-mono` + `@fontsource/saira-stencil-one` imports live —
none of that reaches the bundle automatically once `main.tsx` is excluded.
Wired explicitly via `cfg.cssEntry` (`apps/web/src/theme.css`) and
`cfg.extraFonts` (the fontsource package CSS files). If VERITY's fonts or
theme file ever move, update both config fields — they will NOT be
rediscovered automatically the way they would with the default entry.
