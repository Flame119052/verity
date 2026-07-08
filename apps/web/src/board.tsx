// Shared strip-board primitives: Strip, caps, stamps, punches, key hints.
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { groupColorKey, groupCourses, trackColor } from './lib';
import type { AdherenceStatus } from './types';

/** Short holder code printed on a strip's colored cap. */
export function stripCode(ref: string): string {
  if (ref === 'Homework' || ref === 'HW') return 'HW';
  if (ref.startsWith('Boards-')) {
    const s = ref.slice(7);
    const dash = s.indexOf('-');
    // sub-subject course: code from the sub, e.g. Boards-Science-Physics → B·PHY
    if (dash !== -1) return 'B·' + s.slice(dash + 1, dash + 4).toUpperCase();
    const map: Record<string, string> = {
      Mathematics: 'B·MAT',
      Science: 'B·SCI',
      English: 'B·ENG',
      IT: 'B·IT',
      'Social Science': 'B·SST',
      'Hindi/Sanskrit': 'B·HIN',
    };
    return map[s] ?? 'B·' + s.slice(0, 3).toUpperCase();
  }
  const map: Record<string, string> = {
    'ZCO/ZIO': 'ZCO',
    'IRIS Research': 'IRIS',
    'Project Evidence': 'PROJ',
    CS50AI: 'CS50',
  };
  return map[ref] ?? ref.slice(0, 5).toUpperCase();
}

export function Strip({
  capColor,
  capText,
  capSub,
  children,
  tail,
  selected,
  onClick,
  className,
  formNo,
  style,
}: {
  capColor: string;
  capText: string;
  capSub?: string;
  children: ReactNode;
  tail?: ReactNode;
  selected?: boolean;
  onClick?: () => void;
  className?: string;
  formNo?: string;
  style?: CSSProperties;
}) {
  return (
    <div
      className={[
        'strip',
        selected ? 'sel' : '',
        onClick ? 'clickable' : '',
        className ?? '',
      ].join(' ')}
      onClick={onClick}
      style={style}
    >
      <div className="cap" style={{ background: capColor }}>
        <span>{capText}</span>
        {capSub && <span className="sub">{capSub}</span>}
      </div>
      <div className="strip-body">{children}</div>
      {tail && <div className="strip-tail">{tail}</div>}
      {formNo && <span className="formno">{formNo}</span>}
    </div>
  );
}

export function Stamp({
  children,
  tone,
  animate,
}: {
  children: ReactNode;
  tone?: 'red' | 'green' | 'ink';
  animate?: boolean;
}) {
  return (
    <span
      className={[
        'stamp',
        tone === 'green' ? 'green' : tone === 'ink' ? 'ink' : '',
        animate ? 'stamp-in' : '',
      ].join(' ')}
    >
      {children}
    </span>
  );
}

const PUNCH: Record<AdherenceStatus, { cls: string; text: string }> = {
  completed: { cls: 'ok', text: '● LOGGED' },
  partial: { cls: 'part', text: '◐ PARTIAL' },
  not_logged: { cls: 'miss', text: '○ MISSED' },
  pending: { cls: 'pend', text: '· AHEAD' },
  not_tracked: { cls: 'na', text: '— FIXED' },
};

export function Punch({ status, minutes }: { status: AdherenceStatus; minutes?: number }) {
  const p = PUNCH[status];
  return (
    <>
      <span className={`punch ${p.cls}`}>{p.text}</span>
      {(status === 'completed' || status === 'partial') && minutes != null && (
        <span className="fine">{minutes}m on clock</span>
      )}
    </>
  );
}

export function Fault({ msg }: { msg: string }) {
  return <div className="fault">FEED FAULT — {msg}</div>;
}

export function Loading({ label = 'READING FEED' }: { label?: string }) {
  return <div className="loadingrow">{label} …</div>;
}

export function KeyHint({ k, label }: { k: string; label: string }) {
  return (
    <span className="keyhint">
      <span className="keycap">{k}</span>
      {label}
    </span>
  );
}

/**
 * Two-level course picker: a chip row of base subjects (Science / SST /
 * English / … / IOQM / SAT), then — only for grouped Boards subjects — a
 * second chip row of sub-subjects (Physics / Chemistry / Biology…).
 * Single-level tracks resolve immediately on the first click.
 */
export function CoursePicker({
  courses,
  value,
  onPick,
}: {
  courses: string[];
  value: string;
  onPick: (course: string) => void;
}) {
  const groups = groupCourses(courses);
  // base selected but not yet resolved to a full course (grouped subjects)
  const [openBase, setOpenBase] = useState<string | null>(null);

  // keep the open group in sync when a value arrives from outside (edit mode)
  useEffect(() => {
    if (!value) return;
    const g = groups.find((gr) => gr.subs.some((s) => s.course === value));
    setOpenBase(g ? g.base : null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, courses.join('|')]);

  const open = groups.find((g) => g.base === openBase && g.subs.length > 0) ?? null;

  return (
    <div className="pickstack">
      <div className="chiprow">
        {groups.map((g) => {
          const active =
            g.base === openBase ||
            (g.course != null && g.course === value) ||
            g.subs.some((s) => s.course === value);
          return (
            <button
              key={g.base}
              type="button"
              className={'chip' + (active ? ' on' : '')}
              style={{ borderColor: trackColor(groupColorKey(g)), color: trackColor(groupColorKey(g)) }}
              onClick={() => {
                if (g.subs.length > 0) setOpenBase(g.base);
                else {
                  setOpenBase(null);
                  onPick(g.course!);
                }
              }}
            >
              {g.base.toUpperCase()}
            </button>
          );
        })}
      </div>
      {open && (
        <div className="chiprow subrow">
          {open.subs.map((s) => (
            <button
              key={s.course}
              type="button"
              className={'chip' + (s.course === value ? ' on' : '')}
              style={{ borderColor: trackColor(s.course), color: trackColor(s.course) }}
              onClick={() => onPick(s.course)}
            >
              {s.name.toUpperCase()}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** true if the keydown originated inside a form control */
export function inField(e: KeyboardEvent): boolean {
  const t = e.target as HTMLElement | null;
  return !!t && typeof t.closest === 'function' && !!t.closest('input, textarea, select, [contenteditable]');
}
