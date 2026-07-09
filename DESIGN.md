# VERITY visual system — "Strip Board"

The entire UI (`apps/web/src/theme.css`) is one consistent metaphor: an air-traffic-control flight-progress-
strip board. A dark hardware **board** holds physical **strips** of cream **paper** in colored **holders** —
the board is the machinery, the paper carries the data. Every view is a variation on this: a rack of strips
(RackView), a control panel with a big digit readout (ChronoView), a printed manifest sheet (RosterView), a
row of gauge cards (TallyView), or a desk with paper replies (DispatchView).

This file exists so any agent adding a new view or component reuses these primitives instead of inventing a
new visual language. If you're building something new, find the closest existing pattern below first.

## Palette (all as CSS variables in `:root`, theme.css:8-34)

- **Board (dark, hardware)**: `--board #0d0f12`, `--board-hi #14171d`, `--board-edge #262b34`. Text on board:
  `--etch #8a93a3` (dim: `--etch-dim #4a515e`).
- **Paper (cream, data)**: `--paper #ece4d0` (highlight `--paper-hi`, shadow `--paper-lo`). Text on paper:
  `--ink #211f19` (mid: `--ink-mid`, faint: `--ink-faint`).
- **Status inks** (used on paper): `--red-ink` (miss/error/danger), `--green-ink` (done/ok), `--amber-ink`
  (in-progress/partial).
- **LEDs** (used on board): `--led-green`, `--led-amber`, `--led-red`, `--led-off` — small 7px circles, glow
  via `box-shadow`, pulse via the shared `@keyframes pulse` for anything "live" (running timer, error banner).
- **Fonts**: `--mono` (IBM Plex Mono — body/data text everywhere) and `--stencil` (Saira Stencil One — display
  headings only: view titles, the wordmark). Never use any other font family.

## Core primitives

- **`.board`** — the max-width page frame with left/right hairline edges. Every view lives inside it.
- **`.strip`** — the fundamental data unit: a paper card with a colored `.cap` (holder) on the left showing a
  short category label, a `.strip-body` with up to 3 lines (`l1` bold title, `l2` subtitle, `l3` fine print),
  and often a `.strip-tail` with a big right-aligned number. Selected state (`.strip.sel`) slides right 10px.
  Completed state (`.strip.struck`) fades and draws a strike-through line. New strips animate in via
  `.slot-in`. This is what a homework item, a course topic, a schedule slot, and a chat reply all render as —
  reuse it rather than building a new card style.
- **`.bay`** — an empty dashed slot (the strip-shaped "nothing here yet, click to fill" affordance).
- **`.chip`** / **`.chiprow`** — small pill buttons for picking between options (sub-subject pickers, model
  selectors). `.subrow` chips are visually indented under a parent chip with an `└` prefix for two-level
  pickers (e.g. Science → Physics/Chemistry/Biology).
- **`.plate`** — a small engraved-looking info readout on the dark board (e.g. today's date, a stat).
- **`.stamp`** — a rotated rubber-stamp label (red by default, `.green`/`.ink` variants) for a strong status
  callout, animates in via `.stamp-in`.
- **`.sheet`** — a full paper page (used by RosterView) with a `.manifest` table styled like a printed form.
- **`.inkbtn`** — the primary paper-context button (dark ink-filled, `.ghost` for secondary). `.btn` /
  `.plate button` are the board-context equivalent (dark, bordered).
- **`.fault`** — an error banner (dark red-tinted, pulsing LED bar prefix). Use for any user-facing error
  state instead of inventing a new one.
- **`.keybar`** — the fixed bottom function-key strip (keyboard shortcut hints).

## DISPATCH-specific (chat UI)

User messages render as `.msg-plate` (dark engraved plate, right-aligned) — assistant replies render as
`.msg-paper` (a cream strip, left-aligned) — this mirrors the board/paper duality: the user's input is a board
control, the AI's reply is paper output. Proposed file changes render as `.strip`s with a `.proposal-body`
diff preview underneath. Attachments are `.att-chip`s.

## Adding a new view

1. Wrap content in the existing `.stage` / `.viewhead` header pattern (see any `views/*.tsx`).
2. Represent list items as `.strip` rows inside a `.striprow` wrapper, not ad-hoc `<div>`s.
3. Use `--red-ink`/`--green-ink`/`--amber-ink` for status, never arbitrary hex colors.
4. Empty states use `.emptynote`, loading states use `.loadingrow` — both already have the correct letter-
   spacing/pulse treatment, don't restyle per-view.
5. `apps/web/public/setup.html` is intentionally a lighter-weight echo of this system (dark board + cream
   card, hand-picked from these same variables since it's a static file outside the Vite/theme.css bundle) —
   keep it in sync by eye if the core palette ever changes.
