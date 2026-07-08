// ROSTER — the printed manifest sheet for each track. Every block of every
// topic is on the page; the cursor's next block is marked in red ink.
// Rows carry direct actions: ✓ DONE advances the cursor past that exact
// block, and the Syl cell cycles the syllabus status NS→L→P→ER→F→NS.
import { Fragment, useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api';
import type { Block, BreakdownRow, SyllabusStatus } from '../types';
import { trackColor } from '../lib';
import { Fault, inField, Loading, Stamp } from '../board';

const SYL_LABEL: Record<string, string> = {
  NS: 'not started',
  L: 'learning',
  P: 'practised',
  ER: 'exam ready',
  F: 'finished',
};

const SYL_CYCLE: SyllabusStatus[] = ['NS', 'L', 'P', 'ER', 'F'];

function nextSyl(s: SyllabusStatus): SyllabusStatus {
  return SYL_CYCLE[(SYL_CYCLE.indexOf(s) + 1) % SYL_CYCLE.length];
}

export function RosterView() {
  const [courses, setCourses] = useState<string[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selCourse, setSelCourse] = useState<string | null>(null);
  const [rows, setRows] = useState<BreakdownRow[] | null>(null);
  const [next, setNext] = useState<Block | null>(null);
  const [sheetErr, setSheetErr] = useState<string | null>(null);
  const [rowErr, setRowErr] = useState<{ idx: number; msg: string } | null>(null);
  const [marked, setMarked] = useState<number | null>(null);
  const cache = useRef(new Map<string, { rows: BreakdownRow[]; next: Block | null }>());

  useEffect(() => {
    api
      .courses()
      .then((r) => {
        setCourses(r.courses);
        if (r.courses.length > 0) setSelCourse((c) => c ?? r.courses[0]);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'load failed'));
  }, []);

  const loadSheet = useCallback(async (course: string) => {
    const hit = cache.current.get(course);
    if (hit) {
      setRows(hit.rows);
      setNext(hit.next);
      setSheetErr(null);
      return;
    }
    setRows(null);
    setNext(null);
    setSheetErr(null);
    try {
      const [b, n] = await Promise.all([
        api.breakdown(course),
        api.next(course).catch(() => null),
      ]);
      cache.current.set(course, { rows: b.breakdown, next: n?.next ?? null });
      setRows(b.breakdown);
      setNext(n?.next ?? null);
    } catch (e) {
      setSheetErr(e instanceof Error ? e.message : 'load failed');
    }
  }, []);

  useEffect(() => {
    if (selCourse) loadSheet(selCourse);
    setRowErr(null);
    setMarked(null);
  }, [selCourse, loadSheet]);

  // ✓ DONE — advance the cursor past this exact row (real progress, on purpose)
  const markDone = useCallback(
    async (row: BreakdownRow, idx: number) => {
      if (!selCourse) return;
      setRowErr(null);
      try {
        const r = await api.advance(selCourse, row.topic, row.blockType);
        cache.current.delete(selCourse);
        setNext(r.next);
        cache.current.set(selCourse, { rows: rows ?? [], next: r.next });
        setMarked(idx);
        window.setTimeout(() => setMarked(null), 1600);
      } catch (e) {
        setRowErr({ idx, msg: e instanceof Error ? e.message : 'advance failed' });
      }
    },
    [selCourse, rows],
  );

  // Syl cell — cycle NS→L→P→ER→F→NS, optimistically, revert on failure
  const cycleSyl = useCallback(
    async (row: BreakdownRow, idx: number) => {
      if (!selCourse || !row.topic) return;
      const from = row.syllabusStatus;
      const to = nextSyl(from);
      setRowErr(null);
      // optimistic: every row of the same topic shares the status
      const apply = (status: SyllabusStatus) => {
        setRows((cur) => {
          const upd = (cur ?? []).map((r) => (r.topic === row.topic ? { ...r, syllabusStatus: status } : r));
          const hit = cache.current.get(selCourse);
          if (hit) cache.current.set(selCourse, { ...hit, rows: upd });
          return upd;
        });
      };
      apply(to);
      try {
        await api.setSyllabus(selCourse, row.topic, to);
      } catch (e) {
        apply(from);
        setRowErr({ idx, msg: e instanceof Error ? e.message : 'syllabus update failed' });
      }
    },
    [selCourse],
  );

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey || !courses || !selCourse) return;
      const i = courses.indexOf(selCourse);
      if (e.key === 'j' || e.key === 'ArrowDown') {
        e.preventDefault();
        setSelCourse(courses[Math.min(courses.length - 1, i + 1)]);
      }
      if (e.key === 'k' || e.key === 'ArrowUp') {
        e.preventDefault();
        setSelCourse(courses[Math.max(0, i - 1)]);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [courses, selCourse]);

  const isBoards = selCourse?.startsWith('Boards-') ?? false;
  const isNextRow = (r: BreakdownRow) =>
    !!next && r.topic === next.topic && r.blockType === next.blockType;

  return (
    <section>
      <div className="viewhead">
        <h2>ROSTER</h2>
        <span className="sub">full course manifests · red row = cursor's next block · ✓ DONE advances · click Syl to cycle</span>
      </div>

      {error && <Fault msg={error} />}
      {!courses && !error && <Loading label="READING ROSTER" />}

      {courses && (
        <div className="roster-wrap">
          <div className="course-list">
            {courses.map((c) => (
              <button
                key={c}
                className={'course-item' + (c === selCourse ? ' on' : '')}
                style={{ borderLeftColor: trackColor(c) }}
                onClick={() => setSelCourse(c)}
              >
                {c}
              </button>
            ))}
          </div>

          <div className="sheet">
            {selCourse && (
              <div className="sheet-head">
                <h3 style={{ color: trackColor(selCourse) }}>{selCourse.toUpperCase()}</h3>
                <span className="meta">
                  {rows ? `${rows.length} BLOCKS ON MANIFEST` : ''}
                  {isBoards ? ' · SYLLABUS CODES NS/L/P/ER/F' : ''} · FORM SCC-1
                </span>
              </div>
            )}
            {sheetErr && <Fault msg={sheetErr} />}
            {!rows && !sheetErr && <Loading label="PRINTING MANIFEST" />}
            {rows && rows.length === 0 && <div className="emptynote">manifest empty</div>}
            {rows && rows.length > 0 && (
              <table className="manifest">
                <thead>
                  <tr>
                    <th />
                    <th>Topic</th>
                    <th>Block</th>
                    <th>Dur</th>
                    <th>Source</th>
                    <th>Action</th>
                    <th>Output</th>
                    <th>Benchmark</th>
                    {isBoards && <th>Syl</th>}
                    <th>Mark</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => (
                    <Fragment key={i}>
                      <tr className={isNextRow(r) ? 'next-row' : ''}>
                        <td>{isNextRow(r) ? <span className="nextmark">▶ NEXT</span> : ''}</td>
                        <td className="strong">{r.topic ?? '—'}</td>
                        <td className="strong">{r.blockType}</td>
                        <td style={{ whiteSpace: 'nowrap' }}>{r.durationRange}</td>
                        <td>{r.source}</td>
                        <td>{r.action}</td>
                        <td>{r.output}</td>
                        <td>{r.benchmark}</td>
                        {isBoards && (
                          <td>
                            <button
                              type="button"
                              className={`syl sylbtn ${r.syllabusStatus}`}
                              title={`${SYL_LABEL[r.syllabusStatus]} — click to set ${nextSyl(r.syllabusStatus)} (${SYL_LABEL[nextSyl(r.syllabusStatus)]})`}
                              onClick={() => cycleSyl(r, i)}
                            >
                              {r.syllabusStatus}
                            </button>
                          </td>
                        )}
                        <td style={{ whiteSpace: 'nowrap' }}>
                          {marked === i ? (
                            <Stamp tone="green" animate>✓ MARKED</Stamp>
                          ) : (
                            <button
                              type="button"
                              className="rowdone"
                              title="mark this block done — advances the course cursor past it"
                              onClick={() => markDone(r, i)}
                            >
                              ✓ DONE
                            </button>
                          )}
                        </td>
                      </tr>
                      {rowErr && rowErr.idx === i && (
                        <tr>
                          <td colSpan={isBoards ? 10 : 9}>
                            <span className="ink-err">{rowErr.msg}</span>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
