// Shared helpers: track colors, time math, homework quick-add parsing.

// ---- track colors -------------------------------------------------------

const NEUTRALS = ['#7fa7d4', '#5fb0b7', '#b8a965', '#8f9dc9', '#c9a08f', '#7fbf9e'];

// One steady ink per Boards base subject — every sub-subject of a base
// (Boards-Science-Physics, -Chemistry, -Biology…) shares its base's color.
const BOARDS_COLORS: Record<string, string> = {
  Mathematics: '#ef7d95',
  Science: '#7fbf9e',
  SST: '#c9a08f',
  English: '#8f9dc9',
  Sanskrit: '#b8a965',
  IT: '#5fb0b7',
};

export function trackColor(course: string): string {
  if (course === 'Homework' || course.startsWith('HW')) return '#9ece6a';
  if (course === 'IOQM') return '#f0a63a';
  if (course.startsWith('ZCO')) return '#3fd0c9';
  if (course.startsWith('Boards-')) {
    const base = course.slice(7).split('-')[0];
    return BOARDS_COLORS[base] ?? '#ef7d95';
  }
  let h = 0;
  for (let i = 0; i < course.length; i++) h = (h * 31 + course.charCodeAt(i)) | 0;
  return NEUTRALS[Math.abs(h) % NEUTRALS.length];
}

// ---- course grouping (two-level picker) -----------------------------------
// "Boards-Science-Physics" → group "Science", sub "Physics".
// "Boards-Mathematics", "IOQM", "SAT"… → single-level, no second row.

export interface CourseGroup {
  /** display label: "Science", "SST", "IOQM"… */
  base: string;
  /** resolved full course when the group has no sub-subjects, else null */
  course: string | null;
  boards: boolean;
  subs: { name: string; course: string }[];
}

export function groupCourses(courses: string[]): CourseGroup[] {
  const out: CourseGroup[] = [];
  const byBase = new Map<string, CourseGroup>();
  for (const c of courses) {
    if (c.startsWith('Boards-')) {
      const rest = c.slice(7);
      const dash = rest.indexOf('-');
      const base = dash === -1 ? rest : rest.slice(0, dash);
      let g = byBase.get(base);
      if (!g) {
        g = { base, course: null, boards: true, subs: [] };
        byBase.set(base, g);
        out.push(g);
      }
      if (dash === -1) g.course = c;
      else g.subs.push({ name: rest.slice(dash + 1).replace(/-/g, ' '), course: c });
    } else {
      out.push({ base: c, course: c, boards: false, subs: [] });
    }
  }
  return out;
}

/** representative course string for coloring a group's chip */
export function groupColorKey(g: CourseGroup): string {
  return g.course ?? (g.boards ? `Boards-${g.base}` : g.base);
}

export const FIXED_COLOR = '#6b6f7b';

// ---- time ---------------------------------------------------------------

export function todayISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export function shiftISO(iso: string, days: number): string {
  const d = new Date(iso + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** ISO date of the Monday of the week containing `iso` (weeks run Mon–Sun). */
export function mondayOfWeek(iso: string): string {
  const d = new Date(iso + 'T00:00:00');
  const back = (d.getDay() + 6) % 7; // Mon=0 … Sun=6
  return shiftISO(iso, -back);
}

export function minsToHHMM(mins: number): string {
  const h = Math.floor(mins / 60) % 24;
  const m = mins % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function hhmmToMins(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

export function nowMins(): number {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes();
}

export function fmtClock(totalSec: number): string {
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export function fmtMinutes(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h${String(m).padStart(2, '0')}`;
}

// ---- slot label encode/decode -------------------------------------------
// Course slots are stored as "Course · Topic · BlockType" (topic may be absent).

export function encodeCourseLabel(course: string, topic: string | null, blockType: string): string {
  return [course, topic, blockType].filter(Boolean).join(' · ');
}

export function decodeCourseFromLabel(label: string): string {
  return label.split(' · ')[0].trim();
}

// ---- homework quick-add parser ------------------------------------------
// One line, typed naturally:  "Science: lab report due 12/07 45m high"
// subject before ":", "NNm" = est minutes, high/low/normal = priority,
// due = yyyy-mm-dd | dd/mm | today | tom(orrow) | mon..sun | +Nd

export interface ParsedHomework {
  subject: string;
  task: string;
  due_date: string;
  est_minutes: number;
  priority_tag: 'High' | 'Normal' | 'Low';
}

const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

function resolveDate(token: string): string | null {
  const t = token.toLowerCase();
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t;
  const dm = t.match(/^(\d{1,2})\/(\d{1,2})$/); // dd/mm
  if (dm) {
    const now = new Date();
    let d = new Date(now.getFullYear(), Number(dm[2]) - 1, Number(dm[1]));
    if (d.getTime() < now.getTime() - 86400000) d.setFullYear(d.getFullYear() + 1);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  if (t === 'today') return todayISO();
  if (t === 'tom' || t === 'tomorrow' || t === 'tmr') return shiftISO(todayISO(), 1);
  const plus = t.match(/^\+(\d+)d$/);
  if (plus) return shiftISO(todayISO(), Number(plus[1]));
  const wd = WEEKDAYS.indexOf(t.slice(0, 3));
  if (wd >= 0 && /^[a-z]+$/.test(t)) {
    const now = new Date();
    let delta = (wd - now.getDay() + 7) % 7;
    if (delta === 0) delta = 7;
    return shiftISO(todayISO(), delta);
  }
  return null;
}

export function parseHomework(raw: string): ParsedHomework | null {
  let text = raw.trim();
  if (!text) return null;

  let subject = '';
  const colon = text.indexOf(':');
  if (colon > 0 && colon < 30) {
    subject = text.slice(0, colon).trim();
    text = text.slice(colon + 1).trim();
  }

  let est = 30;
  let priority: 'High' | 'Normal' | 'Low' = 'Normal';
  let due = shiftISO(todayISO(), 1);
  let dueSet = false;

  const tokens = text.split(/\s+/);
  const kept: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    const low = tok.toLowerCase().replace(/^!/, '');
    const min = tok.match(/^(\d+)(m|min)$/i);
    if (min) { est = Number(min[1]); continue; }
    if (low === 'high' || low === 'low' || low === 'normal') {
      priority = (low[0].toUpperCase() + low.slice(1)) as ParsedHomework['priority_tag'];
      continue;
    }
    if (low === 'due' && i + 1 < tokens.length) {
      const d = resolveDate(tokens[i + 1]);
      if (d) { due = d; dueSet = true; i++; continue; }
      continue;
    }
    if (!dueSet) {
      const d = resolveDate(tok);
      if (d) { due = d; dueSet = true; continue; }
    }
    kept.push(tok);
  }

  let task = kept.join(' ').trim();
  if (!task) return null;
  if (!subject) {
    // No explicit "subject:" — infer from the first word, and remove it from
    // the task text so it isn't duplicated. Single-word input stays as both.
    const words = task.split(' ');
    subject = words[0];
    if (words.length > 1) task = words.slice(1).join(' ').trim();
  }
  return { subject, task, due_date: due, est_minutes: est, priority_tag: priority };
}
