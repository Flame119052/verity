import { useEffect, useState } from 'react';
import type { ViewId } from './types';
import { TimerProvider, useTimer } from './timer';
import { fmtClock, trackColor } from './lib';
import { inField, KeyHint, stripCode } from './board';
import { RackView } from './views/RackView';
import { ChronoView } from './views/ChronoView';
import { PendingView } from './views/PendingView';
import { RosterView } from './views/RosterView';
import { TallyView } from './views/TallyView';
import { DispatchView } from './views/DispatchView';

const VIEWS: { id: ViewId; key: string; code: string }[] = [
  { id: 'schedule', key: '1', code: 'RACK' },
  { id: 'tracker', key: '2', code: 'CHRONO' },
  { id: 'homework', key: '3', code: 'PENDING' },
  { id: 'courses', key: '4', code: 'ROSTER' },
  { id: 'stats', key: '5', code: 'TALLY' },
  { id: 'assistant', key: '6', code: 'DISPATCH' },
];

const VIEW_KEYS: Record<ViewId, { k: string; label: string }[]> = {
  schedule: [
    { k: 'J/K', label: 'move' },
    { k: '⏎', label: 'edit / new' },
    { k: 'A', label: 'new strip' },
    { k: 'X', label: 'pull strip' },
    { k: '[ ]', label: 'day ±' },
    { k: 'T', label: 'today' },
  ],
  tracker: [
    { k: 'J/K', label: 'move' },
    { k: '⏎', label: 'bind + start' },
    { k: 'SPACE', label: 'stop + log' },
    { k: 'D', label: 'advance cursor' },
  ],
  homework: [
    { k: 'J/K', label: 'move' },
    { k: 'X', label: 'mark done' },
    { k: 'N', label: 'quick add' },
  ],
  courses: [
    { k: 'J/K', label: 'course' },
  ],
  stats: [
    { k: '[ ]', label: 'week ±' },
    { k: 'T', label: 'this week' },
  ],
  assistant: [
    { k: '⌘⏎', label: 'send' },
  ],
};

function Clock() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);
  const p = (n: number) => String(n).padStart(2, '0');
  return (
    <div className="head-clock">
      <span className="hm">
        {p(now.getHours())}:{p(now.getMinutes())}
        <span className="sec">:{p(now.getSeconds())}</span>
      </span>
      <span className="dt">
        {now.toLocaleDateString('en-IN', { weekday: 'long', day: '2-digit', month: 'short', year: 'numeric' })}
      </span>
    </div>
  );
}

function TimerChip({ goChrono }: { goChrono: () => void }) {
  const t = useTimer();
  if (!t.running || !t.target) return null;
  const code = t.target.course ? stripCode(t.target.course) : 'HW';
  return (
    <button
      className="timer-chip"
      onClick={goChrono}
      style={{ color: trackColor(t.target.course ?? 'Homework') }}
      title={t.target.ref_label}
    >
      <span className="led" />
      {code} {fmtClock(t.elapsedSec)}
    </button>
  );
}

function Board() {
  const firstCourse = new URLSearchParams(window.location.search).get('firstCourse') === '1';
  const [view, setView] = useState<ViewId>(firstCourse ? 'assistant' : 'schedule');

  useEffect(() => {
    if (firstCourse) {
      const url = new URL(window.location.href);
      url.searchParams.delete('firstCourse');
      window.history.replaceState({}, '', url.toString());
    }
  }, [firstCourse]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      const hit = VIEWS.find((v) => v.key === e.key);
      if (hit) {
        e.preventDefault();
        setView(hit.id);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="board">
      <header className="head">
        <div className="head-title">
          <span className="t1">VERITY</span>
          <span className="t2">STUDY OPS</span>
        </div>
        <nav className="tabs">
          {VIEWS.map((v) => (
            <button
              key={v.id}
              className={'tab' + (view === v.id ? ' on' : '')}
              onClick={() => setView(v.id)}
            >
              <span className="led" />
              {v.code}
              <span className="keynum">{v.key}</span>
            </button>
          ))}
        </nav>
        <TimerChip goChrono={() => setView('tracker')} />
        <Clock />
      </header>

      <main className="stage">
        {view === 'schedule' && <RackView />}
        {view === 'tracker' && <ChronoView />}
        {view === 'homework' && <PendingView />}
        {view === 'courses' && <RosterView />}
        {view === 'stats' && <TallyView />}
        {view === 'assistant' && <DispatchView autoOpenNewResearch={firstCourse} />}
      </main>

      <footer className="keybar">
        <KeyHint k="1–6" label="board" />
        {VIEW_KEYS[view].map((h) => (
          <KeyHint key={h.k + h.label} k={h.k} label={h.label} />
        ))}
        <KeyHint k="ESC" label="cancel" />
      </footer>
    </div>
  );
}

export default function App() {
  return (
    <TimerProvider>
      <Board />
    </TimerProvider>
  );
}
