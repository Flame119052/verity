const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

// Shape-only regex accepts calendar-impossible dates like 2026-13-99 or
// 2026-02-30, which then produce Invalid Date / NaN downstream (homework
// scoring, stats rollups) — so also reject anything JS's own Date object
// doesn't consider real, via its well-known day-of-month rollover behavior
// (e.g. new Date(2026, 1, 30) rolls over to March, so comparing the
// round-tripped components back against the input catches it).
export function isValidDate(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const match = DATE_RE.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const d = new Date(year, month - 1, day);
  return d.getFullYear() === year && d.getMonth() === month - 1 && d.getDate() === day;
}

export function isValidTime(value: unknown): value is string {
  return typeof value === 'string' && TIME_RE.test(value);
}

// Time-log entries store full ISO 8601 instants (e.g. "2026-07-06T15:45:32.636Z",
// as produced by `new Date().toISOString()` in the timer), unlike schedule
// slots which use plain HH:MM — don't reuse isValidTime for these fields.
export function isValidIsoDateTime(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const d = new Date(value);
  return !Number.isNaN(d.getTime()) && d.toISOString() === value;
}

/** A finite number >= 0 (rejects strings, NaN, Infinity, and negative values). */
export function isPositiveNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

export function isOneOf<T extends string>(value: unknown, options: readonly T[]): value is T {
  return typeof value === 'string' && (options as readonly string[]).includes(value);
}
