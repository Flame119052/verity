import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { api } from './api';

// What the timer is bound to. Captured at start so a stop always logs
// exactly what was running, even if the selection changes mid-session.
export interface TimerTarget {
  ref_type: 'course' | 'homework';
  ref_label: string;
  course: string | null;
  topic: string | null;
  blockType: string | null;
}

interface TimerState {
  running: boolean;
  startedAt: number | null; // epoch ms
  target: TimerTarget | null;
  elapsedSec: number;
  lastLoggedMinutes: number | null;
  error: string | null;
  start: (target: TimerTarget) => void;
  stop: () => Promise<void>;
  discard: () => void;
}

const TimerCtx = createContext<TimerState | null>(null);

const LS_KEY = 'scc-timer-v1';

export function TimerProvider({ children }: { children: ReactNode }) {
  const [running, setRunning] = useState(false);
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [target, setTarget] = useState<TimerTarget | null>(null);
  const [elapsedSec, setElapsedSec] = useState(0);
  const [lastLoggedMinutes, setLastLoggedMinutes] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const startedAtRef = useRef<number | null>(null);

  // Resume a session that was running before a reload.
  useEffect(() => {
    try {
      const raw = localStorage.getItem(LS_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw) as { startedAt: number; target: TimerTarget };
      if (typeof saved.startedAt === 'number' && saved.target) {
        startedAtRef.current = saved.startedAt;
        setStartedAt(saved.startedAt);
        setTarget(saved.target);
        setElapsedSec(Math.floor((Date.now() - saved.startedAt) / 1000));
        setRunning(true);
      }
    } catch {
      /* corrupt state — ignore */
    }
  }, []);

  useEffect(() => {
    if (!running) return;
    const id = window.setInterval(() => {
      if (startedAtRef.current != null) {
        setElapsedSec(Math.floor((Date.now() - startedAtRef.current) / 1000));
      }
    }, 500);
    return () => window.clearInterval(id);
  }, [running]);

  const start = useCallback((t: TimerTarget) => {
    const now = Date.now();
    startedAtRef.current = now;
    setStartedAt(now);
    setTarget(t);
    setElapsedSec(0);
    setError(null);
    setLastLoggedMinutes(null);
    setRunning(true);
    try {
      localStorage.setItem(LS_KEY, JSON.stringify({ startedAt: now, target: t }));
    } catch {
      /* storage unavailable */
    }
  }, []);

  const stop = useCallback(async () => {
    if (!running || startedAtRef.current == null || !target) return;
    const startMs = startedAtRef.current;
    const stopMs = Date.now();
    setRunning(false);
    localStorage.removeItem(LS_KEY);
    const minutes = Math.max(1, Math.round((stopMs - startMs) / 60000));
    try {
      await api.logTime({
        ref_type: target.ref_type,
        ref_label: target.ref_label,
        course: target.course,
        topic: target.topic,
        blockType: target.blockType,
        started_at: new Date(startMs).toISOString(),
        stopped_at: new Date(stopMs).toISOString(),
        minutes,
      });
      setLastLoggedMinutes(minutes);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'failed to log time');
    }
    startedAtRef.current = null;
    setStartedAt(null);
    setElapsedSec(0);
  }, [running, target]);

  const discard = useCallback(() => {
    localStorage.removeItem(LS_KEY);
    startedAtRef.current = null;
    setRunning(false);
    setStartedAt(null);
    setElapsedSec(0);
  }, []);

  const value = useMemo(
    () => ({ running, startedAt, target, elapsedSec, lastLoggedMinutes, error, start, stop, discard }),
    [running, startedAt, target, elapsedSec, lastLoggedMinutes, error, start, stop, discard],
  );

  return <TimerCtx.Provider value={value}>{children}</TimerCtx.Provider>;
}

export function useTimer(): TimerState {
  const ctx = useContext(TimerCtx);
  if (!ctx) throw new Error('useTimer outside TimerProvider');
  return ctx;
}
