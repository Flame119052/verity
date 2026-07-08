// TALLY — the week's ledger: time deposited per track, tasks punched
// through, printed on tally cards.
import { useEffect, useState } from 'react';
import { api } from '../api';
import type { StatsCourseRow, StatsHomework } from '../types';
import { fmtMinutes, mondayOfWeek, shiftISO, todayISO, trackColor } from '../lib';
import { Fault, inField, Loading } from '../board';

const TICKS = 20;

function TickBar({ pct }: { pct: number }) {
  const filled = Math.round((Math.max(0, Math.min(100, pct)) / 100) * TICKS);
  return (
    <div className="tickbar" title={`${pct}% complete`}>
      {Array.from({ length: TICKS }, (_, i) => (
        <i key={i} className={i < filled ? 'f' : ''} />
      ))}
    </div>
  );
}

export function TallyView() {
  const [monday, setMonday] = useState(mondayOfWeek(todayISO()));
  const [data, setData] = useState<{ courses: StatsCourseRow[]; homework: StatsHomework } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const sunday = shiftISO(monday, 6);

  useEffect(() => {
    setData(null);
    setError(null);
    api
      .stats(monday, sunday)
      .then(setData)
      .catch((e) => setError(e instanceof Error ? e.message : 'load failed'));
  }, [monday, sunday]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === '[') setMonday((m) => shiftISO(m, -7));
      if (e.key === ']') setMonday((m) => shiftISO(m, 7));
      if (e.key === 't') setMonday(mondayOfWeek(todayISO()));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const active = data ? data.courses.filter((c) => c.total_minutes > 0 || c.total_tasks > 0) : [];
  const weekTotal =
    (data?.courses.reduce((s, c) => s + c.total_minutes, 0) ?? 0) + (data?.homework.total_minutes ?? 0);
  const thisWeek = monday === mondayOfWeek(todayISO());

  return (
    <section>
      <div className="viewhead">
        <h2>TALLY</h2>
        <span className="sub">{data ? `${fmtMinutes(weekTotal)} deposited this period` : ''}</span>
        <span className="spacer" />
        <span className="plate">
          <button onClick={() => setMonday((m) => shiftISO(m, -7))} title="[">
            ◂
          </button>
          <b>
            WK {monday} → {sunday}
            {thisWeek ? ' · CURRENT' : ''}
          </b>
          <button onClick={() => setMonday((m) => shiftISO(m, 7))} title="]">
            ▸
          </button>
          {!thisWeek && (
            <button onClick={() => setMonday(mondayOfWeek(todayISO()))} title="t">
              NOW
            </button>
          )}
        </span>
      </div>

      {error && <Fault msg={error} />}
      {!data && !error && <Loading label="READING LEDGER" />}

      {data && (
        <>
          <div className="tally-grid">
            {active.map((c) => (
              <div className="tally-card" key={c.course}>
                <div className="cap" style={{ background: trackColor(c.course) }} />
                <div className="tally-body">
                  <div className="name">{c.course}</div>
                  <div className="mins">
                    {fmtMinutes(c.total_minutes)} <small>on clock</small>
                  </div>
                  <TickBar pct={c.percent_complete} />
                  <div className="frac">
                    {c.completed_tasks}/{c.total_tasks} blocks · {c.percent_complete}% of plan
                  </div>
                </div>
                <span className="formno">SCC-5</span>
              </div>
            ))}

            <div className="tally-card">
              <div className="cap" style={{ background: trackColor('Homework') }} />
              <div className="tally-body">
                <div className="name">HOMEWORK</div>
                <div className="mins">
                  {fmtMinutes(data.homework.total_minutes)} <small>on clock</small>
                </div>
                <TickBar pct={data.homework.percent_complete} />
                <div className="frac">
                  {data.homework.completed_count}/{data.homework.total_count} items ·{' '}
                  {data.homework.percent_complete}% cleared
                </div>
              </div>
              <span className="formno">SCC-5</span>
            </div>
          </div>

          {active.length === 0 && data.homework.total_count === 0 && (
            <div className="emptynote" style={{ marginTop: 12 }}>
              NO ACTIVITY ON RECORD FOR THIS PERIOD
            </div>
          )}
        </>
      )}
    </section>
  );
}
