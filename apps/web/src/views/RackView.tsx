// RACK — the day's strip rack. Each schedule slot is a paper strip in a
// colored holder; strips slot in from the right and settle into their bay.
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api';
import type { AdherenceRow, Block, BreakdownRow, HomeworkItem } from '../types';
import {
  decodeCourseFromLabel,
  encodeCourseLabel,
  FIXED_COLOR,
  fmtMinutes,
  hhmmToMins,
  minsToHHMM,
  nowMins,
  shiftISO,
  todayISO,
  trackColor,
} from '../lib';
import { CoursePicker, Fault, inField, Loading, Punch, Stamp, Strip, stripCode } from '../board';

type RefType = 'course' | 'homework' | 'fixed';

interface Composer {
  originalTime: string | null; // non-null → editing that slot
  time: string;
  dur: string;
  refType: RefType;
  course: string;
  next: Block | null;
  nextLoading: boolean;
  nextErr: string | null;
  // manual manifest pick (escape hatch from the auto next-in-sequence fill)
  browse: boolean;
  manifest: BreakdownRow[] | null;
  manifestLoading: boolean;
  manifestErr: string | null;
  manual: Block | null;
  hw: HomeworkItem[] | null;
  hwIdx: number;
  hwLoading: boolean;
  fixedLabel: string;
  saving: boolean;
  err: string | null;
  confirmOverwrite?: boolean;
}

function normTime(raw: string): string | null {
  const m = raw.trim().match(/^(\d{1,2}):?(\d{2})$/);
  if (!m) return null;
  const h = Number(m[1]);
  const mm = Number(m[2]);
  if (h > 23 || mm > 59) return null;
  return `${String(h).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
}

function defaultNewTime(rows: AdherenceRow[]): string {
  if (rows.length > 0) {
    const last = rows[rows.length - 1];
    return minsToHHMM(hhmmToMins(last.start_time) + last.duration_min);
  }
  return minsToHHMM(Math.ceil(nowMins() / 15) * 15);
}

function firstDurationOf(range: string): number | null {
  const m = range.match(/(\d+)/);
  return m ? Number(m[1]) : null;
}

export function RackView() {
  const [date, setDate] = useState(todayISO());
  const [rows, setRows] = useState<AdherenceRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [courses, setCourses] = useState<string[]>([]);
  const [sel, setSel] = useState(0);
  const [composer, setComposer] = useState<Composer | null>(null);
  const [justSlotted, setJustSlotted] = useState<string | null>(null);
  const composerRef = useRef<Composer | null>(null);
  composerRef.current = composer;

  const load = useCallback(async (d: string) => {
    setError(null);
    try {
      const res = await api.adherence(d);
      setRows(res.adherence.slice().sort((a, b) => a.start_time.localeCompare(b.start_time)));
    } catch {
      // adherence needs the timelog store; fall back to the raw schedule
      try {
        const res = await api.schedule(d);
        setRows(
          res.schedule
            .slice()
            .sort((a, b) => a.start_time.localeCompare(b.start_time))
            .map((s) => ({ ...s, status: 'not_tracked' as const, logged_minutes: 0 })),
        );
      } catch (e) {
        setError(e instanceof Error ? e.message : 'load failed');
        setRows(null);
      }
    }
  }, []);

  useEffect(() => {
    setRows(null);
    load(date);
  }, [date, load]);

  useEffect(() => {
    api.courses().then((r) => setCourses(r.courses)).catch(() => {});
  }, []);

  const openComposer = useCallback(
    (row: AdherenceRow | null) => {
      const base: Composer = {
        originalTime: row ? row.start_time : null,
        time: row ? row.start_time : defaultNewTime(rows ?? []),
        dur: row ? String(row.duration_min) : '45',
        refType: row ? row.ref_type : 'course',
        course: row && row.ref_type === 'course' ? decodeCourseFromLabel(row.ref_label) : '',
        next: null,
        nextLoading: false,
        nextErr: null,
        browse: false,
        manifest: null,
        manifestLoading: false,
        manifestErr: null,
        manual: null,
        hw: null,
        hwIdx: 0,
        hwLoading: false,
        fixedLabel: row && row.ref_type === 'fixed' ? row.ref_label : '',
        saving: false,
        err: null,
      };
      setComposer(base);
      if (base.refType === 'course' && base.course) pullNext(base.course);
      if (base.refType === 'homework') pullHomework();
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows],
  );

  // -- the auto-fill moment: fetch "next in sequence" the instant a course is picked
  const pullNext = useCallback((course: string) => {
    setComposer((c) =>
      c
        ? {
            ...c,
            course,
            next: null,
            nextErr: null,
            nextLoading: true,
            browse: false,
            manifest: null,
            manifestErr: null,
            manual: null,
          }
        : c,
    );
    api
      .next(course)
      .then((r) => {
        setComposer((c) => {
          if (!c || c.course !== course) return c;
          const d = firstDurationOf(r.next.durationRange);
          return { ...c, next: r.next, nextLoading: false, dur: d ? String(d) : c.dur };
        });
      })
      .catch((e) => {
        setComposer((c) =>
          c && c.course === course
            ? { ...c, nextLoading: false, nextErr: e instanceof Error ? e.message : 'no next block' }
            : c,
        );
      });
  }, []);

  // -- manual pick: open the course manifest and let any row override the auto fill
  const toggleBrowse = useCallback(() => {
    const c = composerRef.current;
    if (!c || !c.course) return;
    if (c.browse) {
      setComposer({ ...c, browse: false });
      return;
    }
    if (c.manifest) {
      setComposer({ ...c, browse: true });
      return;
    }
    const course = c.course;
    setComposer({ ...c, browse: true, manifestLoading: true, manifestErr: null });
    api
      .breakdown(course)
      .then((r) => {
        setComposer((cur) =>
          cur && cur.course === course
            ? { ...cur, manifest: r.breakdown, manifestLoading: false }
            : cur,
        );
      })
      .catch((e) => {
        setComposer((cur) =>
          cur && cur.course === course
            ? { ...cur, manifestLoading: false, manifestErr: e instanceof Error ? e.message : 'manifest failed' }
            : cur,
        );
      });
  }, []);

  const pickManual = useCallback((row: BreakdownRow) => {
    const c = composerRef.current;
    if (!c) return;
    const d = firstDurationOf(row.durationRange);
    setComposer({ ...c, manual: row, browse: false, dur: d ? String(d) : c.dur });
  }, []);

  const pullHomework = useCallback(() => {
    setComposer((c) => (c ? { ...c, hwLoading: true } : c));
    api
      .homework()
      .then((r) => {
        const open = r.homework.filter((h) => h.status === 'open');
        setComposer((c) => (c ? { ...c, hw: open, hwIdx: 0, hwLoading: false } : c));
      })
      .catch(() => setComposer((c) => (c ? { ...c, hw: [], hwLoading: false } : c)));
  }, []);

  const setType = useCallback(
    (t: RefType) => {
      setComposer((c) => (c ? { ...c, refType: t, err: null } : c));
      if (t === 'homework') pullHomework();
    },
    [pullHomework],
  );

  const confirm = useCallback(async () => {
    const c = composerRef.current;
    if (!c || c.saving) return;
    const time = normTime(c.time);
    const dur = parseInt(c.dur, 10);
    if (!time) return setComposer({ ...c, err: 'bad time — use HH:MM' });
    if (!dur || dur <= 0) return setComposer({ ...c, err: 'bad duration' });

    let ref_label: string;
    if (c.refType === 'course') {
      if (!c.course) return setComposer({ ...c, err: 'pick a course' });
      const block = c.manual ?? c.next;
      ref_label = block
        ? encodeCourseLabel(block.course, block.topic, block.blockType)
        : c.course;
    } else if (c.refType === 'homework') {
      const item = c.hw?.[c.hwIdx];
      if (!item) return setComposer({ ...c, err: 'no open homework to slot' });
      ref_label = `HW · ${item.subject} — ${item.task}`;
    } else {
      if (!c.fixedLabel.trim()) return setComposer({ ...c, err: 'label the fixed block' });
      ref_label = c.fixedLabel.trim();
    }

    // Moving/creating a slot at `time` silently overwrites whatever is
    // already there (the backend upserts by start_time with no collision
    // check) — warn before destroying a different existing slot's data.
    const collision = rows?.find((r) => r.start_time === time && r.start_time !== c.originalTime);
    if (collision && !c.confirmOverwrite) {
      return setComposer({
        ...c,
        err: `${time} is already taken by "${collision.ref_label}" — confirm again to overwrite it, or pick a different time.`,
        confirmOverwrite: true
      });
    }

    setComposer({ ...c, saving: true, err: null });
    try {
      if (c.originalTime && c.originalTime !== time) {
        await api.deleteSlot(date, c.originalTime);
      }
      await api.setSlot(date, { start_time: time, duration_min: dur, ref_type: c.refType, ref_label });
      setComposer(null);
      setJustSlotted(time);
      window.setTimeout(() => setJustSlotted(null), 500);
      await load(date);
    } catch (e) {
      setComposer({ ...c, saving: false, err: e instanceof Error ? e.message : 'save failed' });
    }
  }, [date, load]);

  const pull = useCallback(
    async (row: AdherenceRow) => {
      try {
        await api.deleteSlot(date, row.start_time);
        await load(date);
        setSel((s) => Math.max(0, s - 1));
      } catch (e) {
        setError(e instanceof Error ? e.message : 'delete failed');
      }
    },
    [date, load],
  );

  // keyboard
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setComposer(null);
        return;
      }
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (composerRef.current) return; // composer fields own the keyboard
      const n = rows?.length ?? 0;
      switch (e.key) {
        case 'j':
        case 'ArrowDown':
          e.preventDefault();
          setSel((s) => Math.min(n, s + 1));
          break;
        case 'k':
        case 'ArrowUp':
          e.preventDefault();
          setSel((s) => Math.max(0, s - 1));
          break;
        case 'Enter':
          e.preventDefault();
          if (rows && sel < n) openComposer(rows[sel]);
          else openComposer(null);
          break;
        case 'a':
          e.preventDefault();
          openComposer(null);
          break;
        case 'x':
        case 'Backspace':
          e.preventDefault();
          if (rows && sel < n) pull(rows[sel]);
          break;
        case '[':
          setDate((d) => shiftISO(d, -1));
          break;
        case ']':
          setDate((d) => shiftISO(d, 1));
          break;
        case 't':
          setDate(todayISO());
          break;
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [rows, sel, openComposer, pull]);

  const isToday = date === todayISO();
  const now = nowMins();
  const totalMin = (rows ?? []).reduce((s, r) => s + r.duration_min, 0);

  // where the NOW line sits (index of first slot starting after now)
  let nowIdx = -1;
  if (isToday && rows) {
    nowIdx = rows.findIndex((r) => hhmmToMins(r.start_time) + r.duration_min > now);
    if (nowIdx === -1) nowIdx = rows.length;
  }

  const dayLabel = new Date(date + 'T00:00:00').toLocaleDateString('en-IN', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
  });

  return (
    <section>
      <div className="viewhead">
        <h2>DAY RACK</h2>
        <span className="sub">
          {rows ? `${rows.length} strips racked · ${fmtMinutes(totalMin)} planned` : ''}
        </span>
        <span className="spacer" />
        <span className="plate">
          <button onClick={() => setDate((d) => shiftISO(d, -1))} title="[">
            ◂
          </button>
          <b>
            {dayLabel}
            {isToday ? ' · TODAY' : ''}
          </b>
          <button onClick={() => setDate((d) => shiftISO(d, 1))} title="]">
            ▸
          </button>
          {!isToday && (
            <button onClick={() => setDate(todayISO())} title="t">
              TODAY
            </button>
          )}
        </span>
      </div>

      {error && <Fault msg={error} />}
      {!rows && !error && <Loading label="READING RACK" />}

      {rows && (
        <div>
          {rows.length === 0 && !composer && (
            <div className="emptynote">RACK EMPTY — press A to slot the first strip</div>
          )}

          {rows.map((row, i) => {
            const editingThis = composer && composer.originalTime === row.start_time;
            const isFixed = row.ref_type === 'fixed';
            const isHw = row.ref_type === 'homework';
            const course = row.ref_type === 'course' ? decodeCourseFromLabel(row.ref_label) : null;
            const color = isFixed ? FIXED_COLOR : isHw ? trackColor('Homework') : trackColor(course!);
            const parts = row.ref_label.split(' · ');
            const live =
              isToday &&
              hhmmToMins(row.start_time) <= now &&
              now < hhmmToMins(row.start_time) + row.duration_min;
            return (
              <div key={row.start_time}>
                {isToday && nowIdx === i && (
                  <div className="nowline">
                    <span className="bar" />
                    NOW {minsToHHMM(now)}
                  </div>
                )}
                {editingThis ? (
                  <ComposerStrip
                    c={composer!}
                    courses={courses}
                    setComposer={setComposer}
                    setType={setType}
                    pullNext={pullNext}
                    toggleBrowse={toggleBrowse}
                    pickManual={pickManual}
                    confirm={confirm}
                  />
                ) : (
                  <div className="rackrow striprow">
                    <div className="time-cell">
                      <b>{row.start_time}</b>
                      <span className="dur">+{row.duration_min}m</span>
                    </div>
                    <Strip
                      capColor={color}
                      capText={isFixed ? 'FIX' : isHw ? 'HW' : stripCode(course!)}
                      capSub={live ? '● LIVE' : undefined}
                      selected={sel === i && !composer}
                      onClick={() => {
                        setSel(i);
                        openComposer(row);
                      }}
                      className={justSlotted === row.start_time ? 'slot-in' : ''}
                      formNo={`SCC-2/${date.split('-').join('')}/${row.start_time.replace(':', '')}`}
                      tail={<Punch status={row.status} minutes={row.logged_minutes} />}
                    >
                      <span className="l1">{isFixed || isHw ? row.ref_label : parts.slice(1).join(' · ') || course}</span>
                      {!isFixed && !isHw && parts.length > 1 && <span className="l3">{course}</span>}
                    </Strip>
                  </div>
                )}
              </div>
            );
          })}

          {isToday && rows.length > 0 && nowIdx === rows.length && (
            <div className="nowline">
              <span className="bar" />
              NOW {minsToHHMM(now)}
            </div>
          )}

          {composer && composer.originalTime === null ? (
            <div className="rackrow striprow">
              <div className="time-cell">
                <b>{normTime(composer.time) ?? '--:--'}</b>
              </div>
              <ComposerStrip
                c={composer}
                courses={courses}
                setComposer={setComposer}
                setType={setType}
                pullNext={pullNext}
                toggleBrowse={toggleBrowse}
                pickManual={pickManual}
                confirm={confirm}
              />
            </div>
          ) : (
            !composer && (
              <div className="rackrow striprow">
                <div className="time-cell" />
                <button
                  className={'bay' + (sel === rows.length ? ' sel' : '')}
                  onClick={() => openComposer(null)}
                >
                  ▸ EMPTY BAY — SLOT A STRIP (A)
                </button>
              </div>
            )
          )}
        </div>
      )}
    </section>
  );
}

function ComposerStrip({
  c,
  courses,
  setComposer,
  setType,
  pullNext,
  toggleBrowse,
  pickManual,
  confirm,
}: {
  c: Composer;
  courses: string[];
  setComposer: (fn: Composer | null) => void;
  setType: (t: RefType) => void;
  pullNext: (course: string) => void;
  toggleBrowse: () => void;
  pickManual: (row: BreakdownRow) => void;
  confirm: () => void;
}) {
  const timeRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    timeRef.current?.focus();
    timeRef.current?.select();
  }, []);

  const upd = (patch: Partial<Composer>) => setComposer({ ...c, ...patch });
  const hwItem = c.hw?.[c.hwIdx];

  return (
    <div
      className="composer striprow"
      onKeyDown={(e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          confirm();
        }
        if (e.key === 'Escape') setComposer(null);
      }}
    >
      <div className="strip sel" style={{ flexDirection: 'row' }}>
        <div className="cap">
          <span>{c.originalTime ? 'EDIT' : 'NEW'}</span>
          <span className="sub">{c.originalTime ?? 'strip'}</span>
        </div>
        <div className="strip-main">
          <div className="fields">
            <div className="fld">
              <label>start</label>
              <input
                ref={timeRef}
                className="w-time"
                value={c.time}
                onChange={(e) => upd({ time: e.target.value, confirmOverwrite: false })}
                placeholder="HH:MM"
              />
            </div>
            <div className="fld">
              <label>min</label>
              <input
                className="w-dur"
                value={c.dur}
                onChange={(e) => upd({ dur: e.target.value.replace(/\D/g, '') })}
              />
            </div>
            <div className="fld">
              <label>type</label>
              <div className="seg">
                {(['course', 'homework', 'fixed'] as const).map((t) => (
                  <button key={t} type="button" className={c.refType === t ? 'on' : ''} onClick={() => setType(t)}>
                    {t === 'course' ? 'COURSE' : t === 'homework' ? 'HW' : 'FIXED'}
                  </button>
                ))}
              </div>
            </div>
            {c.refType === 'course' && (
              <div className="fld" style={{ flex: 1, minWidth: 220 }}>
                <label>track</label>
                <CoursePicker courses={courses} value={c.course} onPick={pullNext} />
              </div>
            )}
            {c.refType === 'fixed' && (
              <div className="fld" style={{ flex: 1, minWidth: 160 }}>
                <label>label</label>
                <input
                  value={c.fixedLabel}
                  onChange={(e) => upd({ fixedLabel: e.target.value })}
                  placeholder="School / Meals / Sleep…"
                />
              </div>
            )}
          </div>

          {c.refType === 'course' && (c.nextLoading || c.next || c.nextErr || c.manual) && (
            <div className="preview">
              {c.nextLoading && <span className="l3">PULLING NEXT IN SEQUENCE…</span>}
              {c.nextErr && !c.manual && <span className="ink-err">{c.nextErr}</span>}
              {(() => {
                const block = c.manual ?? c.next;
                if (!block || c.nextLoading) return null;
                return (
                  <>
                    <div className="pv-main">
                      <div className="l1">
                        {block.topic ? `${block.topic} · ` : ''}
                        {block.blockType}
                      </div>
                      <div className="l2">
                        {block.action} → {block.output}
                      </div>
                      <div className="l3">
                        {block.durationRange} · src {block.source} · bench: {block.benchmark}
                      </div>
                    </div>
                    <Stamp animate>{c.manual ? 'MANUAL PICK' : 'NEXT IN SEQ'}</Stamp>
                  </>
                );
              })()}
              {c.course && (
                <button type="button" className="inkbtn ghost" onClick={toggleBrowse}>
                  {c.browse ? 'CLOSE MANIFEST' : 'BROWSE MANIFEST ▾'}
                </button>
              )}
              {c.manual && (
                <button
                  type="button"
                  className="inkbtn ghost"
                  onClick={() => {
                    const d = c.next ? firstDurationOf(c.next.durationRange) : null;
                    setComposer({ ...c, manual: null, dur: d ? String(d) : c.dur });
                  }}
                >
                  ← AUTO NEXT
                </button>
              )}
            </div>
          )}

          {c.refType === 'course' && c.browse && (
            <div className="manifest-pick">
              {c.manifestLoading && <span className="l3">PRINTING MANIFEST…</span>}
              {c.manifestErr && <span className="ink-err">{c.manifestErr}</span>}
              {c.manifest &&
                c.manifest.map((r, i) => {
                  const isAuto = !!c.next && r.topic === c.next.topic && r.blockType === c.next.blockType;
                  const isPicked = !!c.manual && r.topic === c.manual.topic && r.blockType === c.manual.blockType;
                  return (
                    <button
                      key={i}
                      type="button"
                      className={'manifest-row' + (isPicked ? ' on' : '')}
                      onClick={() => pickManual(r)}
                    >
                      <b>{r.topic ?? '—'}</b>
                      <span>{r.blockType}</span>
                      <span className="dim">{r.durationRange}</span>
                      {isAuto && <span className="nextmark">▶ NEXT</span>}
                    </button>
                  );
                })}
            </div>
          )}

          {c.refType === 'homework' && (
            <div className="preview">
              {c.hwLoading && <span className="l3">PULLING PENDING QUEUE…</span>}
              {!c.hwLoading && c.hw && c.hw.length === 0 && (
                <span className="ink-err">no open homework</span>
              )}
              {hwItem && (
                <>
                  <div className="pv-main">
                    <div className="l1">
                      {hwItem.subject} — {hwItem.task}
                    </div>
                    <div className="l3">
                      due {hwItem.due_date} · est {hwItem.est_minutes}m · {hwItem.priority_tag}
                      {c.hw!.length > 1 && ` · item ${c.hwIdx + 1}/${c.hw!.length}`}
                    </div>
                  </div>
                  <Stamp animate tone="ink">
                    SCORE {hwItem.score ?? '—'}
                  </Stamp>
                  {c.hw!.length > 1 && (
                    <button
                      type="button"
                      className="inkbtn ghost"
                      onClick={() => upd({ hwIdx: (c.hwIdx + 1) % c.hw!.length })}
                    >
                      NEXT ▸
                    </button>
                  )}
                </>
              )}
            </div>
          )}

          <div className="actions">
            <button className="inkbtn" onClick={confirm} disabled={c.saving}>
              {c.saving ? 'SLOTTING…' : '⏎ SLOT IT'}
            </button>
            <button className="inkbtn ghost" onClick={() => setComposer(null)}>
              ESC CANCEL
            </button>
            {c.err && <span className="ink-err">{c.err}</span>}
          </div>
        </div>
      </div>
    </div>
  );
}
