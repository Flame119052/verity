// PENDING — the homework queue: strips ordered by the server's priority
// score, which is printed plainly on each strip's tail. Marking done
// strikes the strip through before it leaves the rack.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../api';
import type { HomeworkItem } from '../types';
import { parseHomework, todayISO, trackColor, isValidCalendarDate } from '../lib';
import { Fault, inField, Loading, Strip } from '../board';

export function PendingView() {
  const [items, setItems] = useState<HomeworkItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sel, setSel] = useState(0);
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [struck, setStruck] = useState<string | null>(null);
  const [justAdded, setJustAdded] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [edit, setEdit] = useState({
    subject: '',
    task: '',
    due_date: '',
    est_minutes: '',
    priority_tag: 'Normal' as HomeworkItem['priority_tag'],
  });
  const [editErr, setEditErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [confirmDel, setConfirmDel] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const load = useCallback(() => {
    setError(null);
    api
      .homework()
      .then((r) => setItems(r.homework))
      .catch((e) => {
        setError(e instanceof Error ? e.message : 'load failed');
        setItems(null);
      });
  }, []);

  useEffect(load, [load]);

  const open = useMemo(() => (items ?? []).filter((i) => i.status === 'open'), [items]);

  const parsed = useMemo(() => parseHomework(draft), [draft]);

  const add = useCallback(async () => {
    if (!parsed || adding) return;
    setAdding(true);
    try {
      const r = await api.addHomework(parsed);
      setDraft('');
      setJustAdded(r.item.id);
      window.setTimeout(() => setJustAdded(null), 500);
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'add failed');
    }
    setAdding(false);
  }, [parsed, adding, load]);

  const markDone = useCallback(
    async (item: HomeworkItem) => {
      setStruck(item.id);
      try {
        await api.homeworkDone(item.id);
        window.setTimeout(() => {
          setStruck(null);
          load();
          setSel((s) => Math.max(0, s - 1));
        }, 480);
      } catch (e) {
        setStruck(null);
        setError(e instanceof Error ? e.message : 'mark done failed');
      }
    },
    [load],
  );

  const startEdit = useCallback((item: HomeworkItem) => {
    setEditingId(item.id);
    setEditErr(null);
    setConfirmDel(null);
    setEdit({
      subject: item.subject,
      task: item.task,
      due_date: item.due_date,
      est_minutes: String(item.est_minutes),
      priority_tag: item.priority_tag,
    });
  }, []);

  const saveEdit = useCallback(async () => {
    if (!editingId || saving) return;
    const est = parseInt(edit.est_minutes, 10);
    if (!edit.subject.trim()) return setEditErr('subject required');
    if (!edit.task.trim()) return setEditErr('task required');
    if (!isValidCalendarDate(edit.due_date)) return setEditErr('due date must be a valid YYYY-MM-DD date');
    if (!Number.isFinite(est) || est < 0) return setEditErr('bad est minutes');
    setSaving(true);
    setEditErr(null);
    try {
      await api.editHomework(editingId, {
        subject: edit.subject.trim(),
        task: edit.task.trim(),
        due_date: edit.due_date,
        est_minutes: est,
        priority_tag: edit.priority_tag,
      });
      setEditingId(null);
      load();
    } catch (e) {
      setEditErr(e instanceof Error ? e.message : 'save failed');
    }
    setSaving(false);
  }, [editingId, edit, saving, load]);

  // delete is permanent (unlike mark-done, which keeps the item on record)
  const doDelete = useCallback(
    async (item: HomeworkItem) => {
      try {
        await api.deleteHomework(item.id);
        setConfirmDel(null);
        load();
        setSel((s) => Math.max(0, s - 1));
      } catch (e) {
        setConfirmDel(null);
        setError(e instanceof Error ? e.message : 'delete failed');
      }
    },
    [load],
  );

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        inputRef.current?.blur();
        setEditingId(null);
        setConfirmDel(null);
        return;
      }
      if (inField(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (editingId) return; // edit form owns the keyboard
      switch (e.key) {
        case 'j':
        case 'ArrowDown':
          e.preventDefault();
          setSel((s) => Math.min(open.length - 1, s + 1));
          break;
        case 'k':
        case 'ArrowUp':
          e.preventDefault();
          setSel((s) => Math.max(0, s - 1));
          break;
        case 'x':
        case 'Enter':
          e.preventDefault();
          if (open[sel]) markDone(open[sel]);
          break;
        case 'n':
          e.preventDefault();
          inputRef.current?.focus();
          break;
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, sel, markDone, editingId]);

  const today = todayISO();

  return (
    <section>
      <div className="viewhead">
        <h2>PENDING</h2>
        <span className="sub">
          {items ? `${open.length} open · queue ordered by score · done items stay on file` : ''}
        </span>
      </div>

      {/* quick-add: one line, parsed as you type */}
      <div className="striprow" style={{ marginBottom: 14 }}>
        <div className="strip" style={{ marginLeft: 0, flexDirection: 'row' }}>
          <div className="cap" style={{ background: trackColor('Homework') }}>
            <span>NEW</span>
            <span className="sub">N</span>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <input
              ref={inputRef}
              className="quickline"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  add();
                }
              }}
              placeholder='Science: lab report due 12/07 45m high   —   type one line, ⏎ files it'
            />
            <div className="quickparse">
              {parsed ? (
                <>
                  FILES AS&nbsp; <b>{parsed.subject}</b> — {parsed.task} · due <b>{parsed.due_date}</b> · est{' '}
                  <b>{parsed.est_minutes}m</b> · <b>{parsed.priority_tag}</b>
                </>
              ) : (
                'subject: task · "due 12/07 | tom | fri | +3d" · "45m" · high/low'
              )}
            </div>
          </div>
        </div>
      </div>

      {error && <Fault msg={error} />}
      {!items && !error && <Loading label="READING QUEUE" />}
      {items && open.length === 0 && <div className="emptynote">QUEUE CLEAR — nothing pending</div>}

      {open.map((h, i) => {
        const overdue = h.due_date < today;
        const dueToday = h.due_date === today;
        if (editingId === h.id) {
          return (
            <div className="striprow" key={h.id}>
              <div
                className="strip sel"
                style={{ marginLeft: 0, flexDirection: 'row' }}
                onKeyDown={(e) => {
                  // Don't hijack Enter on a focused button (e.g. Cancel) —
                  // that should fire the button's own action, not force a
                  // save. See the identical fix in RackView's composer.
                  const target = e.target as HTMLElement;
                  if (e.key === 'Enter' && target.tagName !== 'BUTTON') {
                    e.preventDefault();
                    saveEdit();
                  }
                }}
              >
                <div className="cap" style={{ background: trackColor('Homework') }}>
                  <span>EDIT</span>
                  <span className="sub">{h.id.slice(0, 6)}</span>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="fields">
                    <div className="fld">
                      <label>subject</label>
                      <input
                        autoFocus
                        value={edit.subject}
                        onChange={(e) => setEdit({ ...edit, subject: e.target.value })}
                      />
                    </div>
                    <div className="fld" style={{ flex: 1, minWidth: 160 }}>
                      <label>task</label>
                      <input value={edit.task} onChange={(e) => setEdit({ ...edit, task: e.target.value })} />
                    </div>
                    <div className="fld">
                      <label>due</label>
                      <input
                        className="w-time"
                        style={{ width: 96 }}
                        value={edit.due_date}
                        onChange={(e) => setEdit({ ...edit, due_date: e.target.value })}
                        placeholder="YYYY-MM-DD"
                      />
                    </div>
                    <div className="fld">
                      <label>est min</label>
                      <input
                        className="w-dur"
                        value={edit.est_minutes}
                        onChange={(e) => setEdit({ ...edit, est_minutes: e.target.value.replace(/\D/g, '') })}
                      />
                    </div>
                    <div className="fld">
                      <label>priority</label>
                      <div className="seg">
                        {(['High', 'Normal', 'Low'] as const).map((p) => (
                          <button
                            key={p}
                            type="button"
                            className={edit.priority_tag === p ? 'on' : ''}
                            onClick={() => setEdit({ ...edit, priority_tag: p })}
                          >
                            {p.toUpperCase()}
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>
                  <div className="actions">
                    <button className="inkbtn" onClick={saveEdit} disabled={saving}>
                      {saving ? 'FILING…' : '⏎ REFILE'}
                    </button>
                    <button className="inkbtn ghost" onClick={() => setEditingId(null)}>
                      ESC CANCEL
                    </button>
                    {editErr && <span className="ink-err">{editErr}</span>}
                  </div>
                </div>
              </div>
            </div>
          );
        }
        return (
          <div className="striprow" key={h.id}>
            <Strip
              capColor={trackColor('Homework')}
              capText={h.subject.slice(0, 8).toUpperCase()}
              capSub={h.priority_tag !== 'Normal' ? h.priority_tag.toUpperCase() : undefined}
              selected={i === sel}
              onClick={() => setSel(i)}
              className={
                (struck === h.id ? 'struck ' : '') + (justAdded === h.id ? 'slot-in' : '')
              }
              formNo={`SCC-4/${h.id.slice(0, 8)}`}
              tail={
                <>
                  <span className="big">{h.score ?? '—'}</span>
                  <span className="fine">{h.scoreReason ?? 'score'}</span>
                </>
              }
            >
              <span className="l1">{h.task}</span>
              <span className="l2">
                {overdue ? '⚠ OVERDUE · ' : dueToday ? 'DUE TODAY · ' : ''}
                due {h.due_date} · est {h.est_minutes}m
                <span className="rowacts" onClick={(e) => e.stopPropagation()}>
                  <button type="button" className="microbtn" onClick={() => startEdit(h)}>
                    EDIT
                  </button>
                  {confirmDel === h.id ? (
                    <>
                      <button type="button" className="microbtn danger" onClick={() => doDelete(h)}>
                        SURE? SHRED IT
                      </button>
                      <button type="button" className="microbtn" onClick={() => setConfirmDel(null)}>
                        KEEP
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      className="microbtn danger"
                      title="permanently removes this item — mark done (X) keeps it on record"
                      onClick={() => setConfirmDel(h.id)}
                    >
                      DEL
                    </button>
                  )}
                </span>
              </span>
            </Strip>
          </div>
        );
      })}

      {open.length > 0 && (
        <div className="emptynote" style={{ marginTop: 6 }}>
          X or ⏎ strikes the selected strip and files it as done (kept on record) · EDIT refiles in place · DEL shreds permanently
        </div>
      )}
    </section>
  );
}
