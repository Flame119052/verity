## VERITY design system — build with these conventions

VERITY is an ATC flight-progress-strip aesthetic: a dark control board holding
cream "paper" strips in colored holders. Ink-on-paper carries the data; the
board is the machinery around it. Keep new UI in that register — don't
introduce flat cards, drop shadows, or rounded-pill buttons; this is a hard,
inked, mechanical look.

### Styling idiom: CSS custom properties + BEM-ish classes, no utility framework

There is no Tailwind/utility layer and no styled-components — style with the
tokens below via plain class names and `var(--*)`, matching the class
vocabulary the source already uses (`strip`, `cap`, `stamp`, `punch`, `chip`,
`keyhint`, `fault`, `loadingrow` …). Don't invent a new naming scheme; extend
this one.

Token families (defined in `styles.css`, i.e. `theme.css`):

| Group | Tokens |
|---|---|
| Board (background/chrome) | `--board`, `--board-hi`, `--board-edge`, `--etch`, `--etch-dim` |
| Paper (strip surfaces) | `--paper`, `--paper-hi`, `--paper-lo`, `--ink`, `--ink-mid`, `--ink-faint`, `--rule` |
| Status ink | `--red-ink`, `--green-ink`, `--amber-ink` |
| Indicator LEDs | `--led-green`, `--led-amber`, `--led-red`, `--led-off` |
| Type | `--mono` (IBM Plex Mono — body/UI text), `--stencil` (Saira Stencil One — headers/branding, e.g. the VERITY wordmark) |

Body text sits on `--board` in `--etch`; strips/cards use the `--paper*`
family with `--ink*` text. Status colors (`Punch`, `Stamp`) map semantically:
green = completed/logged, amber/red-ink = partial/missed, never arbitrary
hues — reuse `trackColor()`'s per-course color logic (in `lib.ts`) rather than
picking new colors for course/subject chips.

### Wrapping and setup

Most components need no provider. `ChronoView` (and anything that calls
`useTimer()`) must be wrapped in `TimerProvider` — it's a plain
`{children}` pass-through that also persists timer state to
`localStorage`, so wrapping it around anything else is harmless:

```jsx
import { TimerProvider, ChronoView } from 'study-command-center-web';

<TimerProvider>
  <ChronoView />
</TimerProvider>
```

The six `*View` components (`RackView`, `ChronoView`, `PendingView`,
`RosterView`, `TallyView`, `DispatchView`) are the app's real screens — each
fetches its own data internally and renders a `Fault`/`Loading` state when
that fetch fails, which is exactly what their preview cards show (there's no
mock data layer to swap in). Building a *new* screen with the same visual
language should compose the smaller primitives (`Strip`, `Stamp`, `Punch`,
`CoursePicker`, `KeyHint`, `Fault`, `Loading`) directly rather than trying to
repurpose a `*View` — those are fixed, single-purpose pages, not layout
components.

### Where the truth lives

- `styles.css` → `theme.css` — every token above, plus the board/paper/strip
  base rules. Read it before styling anything.
- Per-component `.prompt.md` under `components/<group>/<Name>/` — usage notes
  for each primitive.
- `board.tsx` is the shared primitive file (`Strip`, `Stamp`, `Punch`, `Fault`,
  `Loading`, `KeyHint`, `CoursePicker`) — the closest thing this repo has to a
  component library.

### One idiomatic build snippet

A homework strip, built from the real primitives:

```jsx
import { Strip, Stamp, Punch } from 'study-command-center-web';

<Strip capColor="#ef7d95" capText="B·PHY" capSub="12">
  Rotational dynamics — problem set 4
  <Punch status="completed" minutes={45} />
</Strip>
```
