// CHRONO — the active strip pulled out of the rack, with the clock running
// against it. Stopping stamps the minutes onto the strip and deposits them
// into the day's tally.
import { useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import type { AdherenceRow, HomeworkItem, RollupRow } from '../types';
import { useTimer, type TimerTarget } from '../timer';
import {
  decodeCourseFromLabel,
  fmtClock,
  fmtMinutes,
  hhmmToMins,
  nowMins,
  todayISO,
  trackColor,
} from '../lib';
import { CoursePicker, Fault, inField, Loading, Stamp, Strip, stripCode } from '../board';

interface BindOption {
  key: string;
  group: 'slot' | 'homework';
  capText: string;
  capColor: string;
  l1: string;
  l2?: string;
  live?: boolean;
  make: () => Promise<TimerTarget>;
}

function targetFromSlot(row: AdherenceRow): TimerTarget {
  if (row.ref_type === 'homework') {
    return { ref_type: 'homework', ref_label: row.ref_label, course: null, topic: null, blockType: null };
  }
  const parts = row.ref_label.split(' · ');
  const course = parts[0];
  const topic = parts.length === 3 ? parts[1] : null;
  const blockType = parts.length >= 2 ? parts[parts.length - 1] : null;
  return { ref_type: 'course', ref_label: row.ref_label, course, topic, blockType };
}

export function ChronoView() {
  const timer = useTimer();
  const [slots, setSlots] = useState<AdherenceRow[] | null>(null);
  const [courses, setCourses] = useState<string[]>([]);
  const [topHw, setTopHw] = useState<HomeworkItem | null>(null);
  const [rollup, setRollup] = useState<RollupRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sel, setSel] = useState(0);
  const [binding, setBinding] = useState(false);
  const [advanced, setAdvanced] = useState<string | null>(null);
  const [advanceErr, setAdvanceErr] = useState<string | null>(null);
  const [stamped, setStamped] = useState(false);

  const today = todayISO();

  const loadRollup = useCallback(() => {
    api
      .rollup(today, today)
      .then((r) => setRollup(r.rollup))
      .catch(() => setRollup([]));
  }, [today]);

  useEffect(() => {
    api
      .adherence(today)
      .then((r) => setSlots(r.adherence.filter((s) => s.ref_type !== 'fixed')))
      .catch((e) => setError(e instanceof Error ? e.message : 'load failed'));
    api.courses().then((r) => setCourses(r.courses)).catch(() => {});
    api
      .homework()
      .then((r) => setTopHw(r.homework.find((h) => h.status === 'open') ?? null))
      .catch(() => {});
    loadRollup();
  }, [today, loadRollup]);

  const now = nowMins();
  const options: BindOption[] = [];
  (slots ?? []).forEach((row) => {
    const course = row.ref_type === 'course' ? decodeCourseFromLabel(row.ref_label) : null;
    options.push({
      key: 'slot:' + row.start_time,
      group: 'slot',
      capText: row.ref_type === 'homework' ? 'HW' : stripCode(course!),
      capColor: trackColor(course ?? 'Homework'),
      l1: row.ref_label,
      l2: `${row.start_time} +${row.duration_min}m`,
      live: hhmmToMins(row.start_time) <= now && now < hhmmToMins(row.start_time) + row.duration_min,
      make: async () => targetFromSlot(row),
    });
  });
  if (topHw) {
    options.push({
      key: 'hw:' + topHw.id,
      group: 'homework',
      capText: 'HW',
      capColor: trackColor('Homework'),
      l1: `${topHw.subject} — ${topHw.task}`,
      l2: `top of queue · score ${topHw.score ?? '—'}`,
      make: async () => ({
        ref_type: 'homework',
        ref_label: `HW · ${topHw.subject} — ${topHw.task}`,
        course: null,
        topic: null,
        blockType: null,
      }),
    });
  }

  // default selection: the live slot
  useEffect(() => {
    if (!slots) return;
    const liveIdx = options.findIndex((o) => o.live);
    if (liveIdx >= 0) setSel(liveIdx);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slots]);

  // -- bind straight from a track picked in the two-level course picker
  const bindCourse = useCallback(
    async (course: string) => {
      if (timer.running || binding) return;
      setBinding(true);
      setAdvanced(null);
      setAdvanceErr(null);
      setStamped(false);
      try {
        const r = await api.next(course);
        const label = [r.next.course, r.next.topic, r.next.blockType].filter(Boolean).join(' · ');
        timer.start({
          ref_type: 'course',
          ref_label: label,
          course: r.next.course,
          topic: r.next.topic,
          blockType: r.next.blockType,
        });
      } catch (e) {
        setError(e instanceof Error ? e.message : 'bind failed');
      }
      setBinding(false);
    },
    [timer, binding],
  );

  const bind = useCallback(
    async (opt: BindOption) => {
      if (timer.running || binding) return;
      setBinding(true);
      setAdvanced(null);
      setAdvanceErr(null);
      setStamped(false);
      try {
        const target = await opt.make();
        timer.start(target);
      } catch (e) {
        setError(e instanceof Error ? e.message : 'bind failed');
      }
      setBinding(false);
    },
    [timer, binding],
  );

  const stop = useCallback(async () => {
    if (!timer.running) return;
    await timer.stop();
    setStamped(true);
    loadRollup();
  }, [timer, loadRollup]);

  const advance = useCallback(async () => {
    const t = timer.target;
    if (timer.running || !t || t.ref_type !== 'course' || !t.course || !t.blockType) return;
    try {
      const r = await api.advance(t.course, t.topic, t.blockType);
      setAdvanced(
        r.next
          ? `cursor → ${[r.next.topic, r.next.blockType].filter(Boolean).join(' · ')}`
          : 'cursor → end of course plan',
      );
      setAdvanceErr(null);
    } catch (e) {
      setAdvanceErr(e instanceof Error ? e.message : 'advance failed');
    }
  }, [timer]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      switch (e.key) {
        case 'j':
        case 'ArrowDown':
          e.preventDefault();
          setSel((s) => Math.min(options.length - 1, s + 1));
          break;
        case 'k':
        case 'ArrowUp':
          e.preventDefault();
          setSel((s) => Math.max(0, s - 1));
          break;
        case 'Enter':
          e.preventDefault();
          if (!timer.running && options[sel]) bind(options[sel]);
          break;
        case ' ':
          e.preventDefault();
          if (timer.running) stop();
          break;
        case 'd':
          e.preventDefault();
          advance();
          break;
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [options, sel, timer.running, bind, stop, advance]);

  const t = timer.target;
  const capColor = t ? trackColor(t.course ?? 'Homework') : '#9aa3b2';
  const canAdvance = !timer.running && !!t && t.ref_type === 'course' && timer.lastLoggedMinutes != null;

  const groups: { id: BindOption['group']; label: string }[] = [
    { id: 'slot', label: "TODAY'S RACK" },
    { id: 'homework', label: 'PENDING QUEUE' },
  ];

  return (
    <section>
      <div className="viewhead">
        <h2>CHRONOMETER</h2>
        <span className="sub">stop logs time — it never marks work done; advance is explicit</span>
      </div>

      {error && <Fault msg={error} />}

      <div className="chrono-wrap">
        <div className="chrono-main">
          <div className="strip" style={{ flexDirection: 'column' }}>
            <div className="chrono-cap-row">
              <div className="cap" style={{ background: capColor }}>
                <span>{t ? (t.course ? stripCode(t.course) : 'HW') : '——'}</span>
                <span className="sub">{timer.running ? '● LIVE' : 'standby'}</span>
              </div>
              <div className="strip-body">
                <span className="l1">{t ? t.ref_label : 'NO STRIP BOUND'}</span>
                <span className="l3">
                  {timer.running
                    ? `running since ${new Date(timer.startedAt!).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}`
                    : t
                      ? 'stopped'
                      : 'pick a strip from the right, or press ⏎ on one'}
                </span>
              </div>
              {!timer.running && timer.lastLoggedMinutes != null && (
                <div className="strip-tail">
                  <Stamp animate={stamped}>+{timer.lastLoggedMinutes}m LOGGED</Stamp>
                </div>
              )}
            </div>

            <div className={'chrono-digits' + (timer.running ? '' : ' idle')}>
              {fmtClock(timer.elapsedSec)}
            </div>

            <div className="chrono-under">
              {timer.running ? (
                <>
                  <button className="inkbtn" onClick={stop}>
                    ␣ STOP + LOG
                  </button>
                  <button className="inkbtn ghost" onClick={timer.discard}>
                    DISCARD
                  </button>
                </>
              ) : (
                <>
                  {canAdvance && (
                    <button className="inkbtn" onClick={advance}>
                      D MARK DONE · ADVANCE CURSOR
                    </button>
                  )}
                  {t && !timer.running && (
                    <button className="inkbtn ghost" onClick={() => bind(options.find((o) => o.l1 === t.ref_label) ?? { make: async () => t } as BindOption)}>
                      ⏎ RESTART SAME STRIP
                    </button>
                  )}
                </>
              )}
              {timer.error && <span className="ink-err">{timer.error}</span>}
              {advanced && <Stamp tone="green" animate>{advanced}</Stamp>}
              {advanceErr && <span className="ink-err">{advanceErr}</span>}
            </div>
            <span className="formno">FORM SCC-3 · CHRONO LOG</span>
          </div>

          <div className="grouplab" style={{ marginTop: 20 }}>
            TODAY'S DEPOSITS
          </div>
          {rollup === null && <Loading label="READING LEDGER" />}
          {rollup && rollup.length === 0 && <div className="emptynote">nothing logged today yet</div>}
          {rollup && rollup.length > 0 && (
            <div className="tally-grid">
              {rollup.map((r, i) => (
                <div className="tally-card" key={i} style={{ minHeight: 60 }}>
                  <div className="cap" style={{ background: trackColor(r.course) }} />
                  <div className="tally-body">
                    <div className="name">
                      {r.course}
                      {r.topic ? ` · ${r.topic}` : ''}
                      {r.blockType ? ` · ${r.blockType}` : ''}
                    </div>
                    <div className="mins">
                      {fmtMinutes(r.total_minutes)} <small>on clock</small>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="bindlist">
          {slots === null && !error && <Loading label="READING RACK" />}
          {groups.map((g) => {
            const opts = options.filter((o) => o.group === g.id);
            const picker =
              g.id === 'slot' && courses.length > 0 ? (
                <div>
                  <div className="grouplab">ANY TRACK (BINDS NEXT IN SEQ)</div>
                  <CoursePicker courses={courses} value="" onPick={bindCourse} />
                </div>
              ) : null;
            if (opts.length === 0)
              return picker ? <div key={g.id}>{picker}</div> : null;
            return (
              <div key={g.id}>
                <div className="grouplab">{g.label}</div>
                {opts.map((o) => {
                  const idx = options.indexOf(o);
                  return (
                    <Strip
                      key={o.key}
                      capColor={o.capColor}
                      capText={o.capText}
                      capSub={o.live ? '● NOW' : undefined}
                      selected={idx === sel && !timer.running}
                      onClick={() => {
                        setSel(idx);
                        bind(o);
                      }}
                    >
                      <span className="l1">{o.l1}</span>
                      {o.l2 && <span className="l3">{o.l2}</span>}
                    </Strip>
                  );
                })}
                {picker}
              </div>
            );
          })}
          {binding && <div className="loadingrow">BINDING …</div>}
        </div>
      </div>
    </section>
  );
}
