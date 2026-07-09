// DISPATCH — the AI request desk, now a session log. The user opens (or
// starts) a dispatch session, exchanges messages with the AI, and any file
// amendments the AI proposes ride along inside the thread as DRAFT cards.
// Nothing touches paper until each proposal is stamped APPLIED.
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api';
import type { Message, Proposal, ProviderInfo, Session, SessionMeta } from '../types';
import { Fault, Loading, Stamp } from '../board';

type Mode = 'ask' | 'research';

// fallbacks used until (or if) GET /assistant/providers responds
const MODELS = ['sonnet', 'opus', 'haiku', 'fable'];
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

/** readiness of the selected provider's CLI — install/login smoothing, never a hard gate */
type ReadyPhase =
  | 'idle'
  | 'checking'
  | 'needs-install'
  | 'installing'
  | 'needs-login'
  | 'logging-in'
  | 'ready';

interface Readiness {
  phase: ReadyPhase;
  note: string | null; // e.g. backend's "login flow opened in Terminal…" message
  err: string | null;
}

const READY_IDLE: Readiness = { phase: 'idle', note: null, err: null };

const MODE_COLOR: Record<Mode, string> = {
  ask: 'var(--amber-ink)',
  research: '#2d6a8a',
};

function relDate(iso: string): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return '—';
  const mins = Math.round((Date.now() - then) / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.round(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
}

/** per-proposal-card UI state, keyed by `${messageIndex}::${file}` */
interface CardState {
  applied: boolean;
  applying: boolean;
  err: string | null;
  expanded: boolean;
}

interface PendingAtt {
  filename: string;
  contentBase64: string;
}

function fileToBase64(f: File): Promise<PendingAtt> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onerror = () => reject(new Error(`could not read ${f.name}`));
    r.onload = () => {
      const url = String(r.result ?? '');
      const comma = url.indexOf(',');
      resolve({ filename: f.name, contentBase64: comma === -1 ? url : url.slice(comma + 1) });
    };
    r.readAsDataURL(f);
  });
}

export function DispatchView({ autoOpenNewResearch = false }: { autoOpenNewResearch?: boolean }) {
  // ---- session list state ----
  const [sessions, setSessions] = useState<SessionMeta[] | null>(null);
  const [listErr, setListErr] = useState<string | null>(null);
  const [showNew, setShowNew] = useState(autoOpenNewResearch);
  const [newMode, setNewMode] = useState<Mode>(autoOpenNewResearch ? 'research' : 'ask');
  const [newCourse, setNewCourse] = useState('');
  const [newModel, setNewModel] = useState('sonnet');
  const [newEffort, setNewEffort] = useState('medium');
  const [creating, setCreating] = useState(false);
  // ---- provider selection + readiness (install/login smoothing) ----
  const [providers, setProviders] = useState<ProviderInfo[] | null>(null);
  const [newProvider, setNewProvider] = useState('claude');
  const [readiness, setReadiness] = useState<Readiness>(READY_IDLE);
  // latest selected provider id — guards async status results against stale updates
  const provRef = useRef('claude');
  // two-step delete: first × arms the row, second click actually deletes
  const [armedDelete, setArmedDelete] = useState<string | null>(null);

  // ---- open session state ----
  const [session, setSession] = useState<Session | null>(null);
  const sessionRef = useRef<Session | null>(null);
  sessionRef.current = session;
  const [opening, setOpening] = useState(false);
  const [sessErr, setSessErr] = useState<string | null>(null);
  const [cardState, setCardState] = useState<Record<string, CardState>>({});

  // ---- composer state ----
  const [text, setText] = useState('');
  const [atts, setAtts] = useState<PendingAtt[]>([]);
  const [sending, setSending] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const tickRef = useRef<number | null>(null);
  const fileRef = useRef<HTMLInputElement | null>(null);
  const endRef = useRef<HTMLDivElement | null>(null);

  const refreshList = useCallback(async () => {
    setListErr(null);
    try {
      const r = await api.listSessions();
      setSessions(
        [...r.sessions].sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1)),
      );
    } catch (e) {
      setListErr(e instanceof Error ? e.message : 'could not load sessions');
      setSessions([]);
    }
  }, []);

  useEffect(() => {
    if (!session) refreshList();
  }, [session, refreshList]);

  // fetch the provider catalogue once; on failure fall back to legacy claude-only UI
  useEffect(() => {
    let alive = true;
    api
      .listProviders()
      .then((r) => {
        if (!alive) return;
        setProviders(r.providers);
        const first = r.providers.find((p) => p.id === 'claude') ?? r.providers[0];
        if (first) {
          provRef.current = first.id;
          setNewProvider(first.id);
          setNewModel((m) => (first.models.includes(m) ? m : first.models[0] ?? m));
          const effs = first.supportsEffort
            ? first.effortLevels && first.effortLevels.length > 0
              ? first.effortLevels
              : EFFORTS
            : [];
          setNewEffort((e) => (effs.includes(e) ? e : effs[0] ?? e));
        }
      })
      .catch(() => {
        if (alive) setProviders([]); // endpoint unavailable — hide provider UI
      });
    return () => {
      alive = false;
    };
  }, []);

  const activeProvider =
    providers && providers.length > 0
      ? providers.find((p) => p.id === newProvider) ?? providers[0]
      : null;
  const modelOptions = activeProvider ? activeProvider.models : MODELS;
  const effortSupported = activeProvider ? activeProvider.supportsEffort : true;
  const effortOptions = activeProvider
    ? activeProvider.effortLevels && activeProvider.effortLevels.length > 0
      ? activeProvider.effortLevels
      : EFFORTS
    : EFFORTS;

  // best-effort readiness probe: never crashes the picker, never blocks forever
  const checkProvider = useCallback(async (id: string) => {
    setReadiness({ phase: 'checking', note: null, err: null });
    try {
      const s = await api.providerStatus(id);
      if (provRef.current !== id) return;
      if (!s.installed) setReadiness({ phase: 'needs-install', note: null, err: null });
      else if (s.authenticated === false) setReadiness({ phase: 'needs-login', note: null, err: null });
      // 'unknown' auth is treated as fine — proceed silently
      else setReadiness({ phase: 'ready', note: null, err: null });
    } catch {
      if (provRef.current === id) setReadiness({ phase: 'ready', note: null, err: null });
    }
  }, []);

  const selectProvider = useCallback(
    (id: string) => {
      provRef.current = id;
      setNewProvider(id);
      const p = providers?.find((x) => x.id === id);
      if (!p) return;
      setNewModel((m) => (p.models.includes(m) ? m : p.models[0] ?? m));
      const effs = p.supportsEffort
        ? p.effortLevels && p.effortLevels.length > 0
          ? p.effortLevels
          : EFFORTS
        : [];
      setNewEffort((e) => (effs.includes(e) ? e : effs[0] ?? e));
      checkProvider(id);
    },
    [providers, checkProvider],
  );

  // probe the default provider whenever the + NEW picker opens
  useEffect(() => {
    if (showNew && providers && providers.length > 0) checkProvider(provRef.current);
    if (!showNew) setReadiness(READY_IDLE);
  }, [showNew, providers, checkProvider]);

  const installProvider = useCallback(async () => {
    const id = provRef.current;
    setReadiness({ phase: 'installing', note: null, err: null });
    try {
      const r = await api.providerInstall(id);
      if (provRef.current !== id) return;
      if (!r.ok) {
        setReadiness({ phase: 'needs-install', note: null, err: r.message || 'install failed' });
        return;
      }
      await checkProvider(id); // re-probe: may now need login, or be fully ready
    } catch (e) {
      if (provRef.current === id)
        setReadiness({
          phase: 'needs-install',
          note: null,
          err: e instanceof Error ? e.message : 'install failed',
        });
    }
  }, [checkProvider]);

  const loginProvider = useCallback(async () => {
    const id = provRef.current;
    setReadiness((r) => ({ ...r, phase: 'logging-in', err: null }));
    try {
      const r = await api.providerLogin(id);
      if (provRef.current !== id) return;
      if (r.ok) setReadiness({ phase: 'needs-login', note: r.message || null, err: null });
      else setReadiness({ phase: 'needs-login', note: null, err: r.message || 'login failed' });
    } catch (e) {
      if (provRef.current === id)
        setReadiness({
          phase: 'needs-login',
          note: null,
          err: e instanceof Error ? e.message : 'login failed',
        });
    }
  }, []);

  // "Continue" after login: one best-effort re-check, then get out of the way
  const continueAfterLogin = useCallback(async () => {
    const id = provRef.current;
    setReadiness({ phase: 'checking', note: null, err: null });
    try {
      const s = await api.providerStatus(id);
      if (provRef.current !== id) return;
      setReadiness({
        phase: 'ready',
        note: s.authenticated === false ? 'login not detected yet — proceeding anyway' : null,
        err: null,
      });
    } catch {
      if (provRef.current === id) setReadiness({ phase: 'ready', note: null, err: null });
    }
  }, []);

  // elapsed-seconds ticker so a long AI call reads as "working", not "stuck"
  useEffect(() => {
    if (sending) {
      setElapsed(0);
      tickRef.current = window.setInterval(() => setElapsed((s) => s + 1), 1000);
    } else if (tickRef.current != null) {
      window.clearInterval(tickRef.current);
      tickRef.current = null;
    }
    return () => {
      if (tickRef.current != null) window.clearInterval(tickRef.current);
      tickRef.current = null;
    };
  }, [sending]);

  // keep the thread pinned to the latest exchange
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [session?.messages.length, sending]);

  const openSession = useCallback(async (id: string) => {
    setOpening(true);
    setSessErr(null);
    try {
      const r = await api.getSession(id);
      // proposals default to folded inside history; fresh ones unfold on arrival
      setCardState({});
      setSession(r.session);
      setText('');
      setAtts([]);
    } catch (e) {
      setListErr(e instanceof Error ? e.message : 'could not open session');
    }
    setOpening(false);
  }, []);

  const createSession = useCallback(async () => {
    if (creating || (newMode === 'research' && newCourse.trim().length === 0)) return;
    setCreating(true);
    setListErr(null);
    try {
      const r = await api.createSession({
        mode: newMode,
        ...(providers && providers.length > 0 ? { provider: newProvider } : {}),
        model: newModel,
        effort: newEffort,
        ...(newMode === 'research' ? { courseName: newCourse.trim() } : {}),
      });
      setCardState({});
      setSession(r.session);
      setShowNew(false);
      setNewCourse('');
      setText('');
      setAtts([]);
    } catch (e) {
      setListErr(e instanceof Error ? e.message : 'could not start session');
    }
    setCreating(false);
  }, [creating, newMode, newCourse, newModel, newEffort, newProvider, providers]);

  const deleteSession = useCallback(
    async (id: string) => {
      if (armedDelete !== id) {
        // first click arms; a second click on the same row confirms
        setArmedDelete(id);
        return;
      }
      setArmedDelete(null);
      try {
        await api.deleteSession(id);
      } catch (e) {
        setListErr(e instanceof Error ? e.message : 'delete failed');
      }
      refreshList();
    },
    [armedDelete, refreshList],
  );

  const pickFiles = useCallback(async (list: FileList | null) => {
    if (!list || list.length === 0) return;
    try {
      const read = await Promise.all(Array.from(list).map(fileToBase64));
      setAtts((prev) => [...prev, ...read.filter((r) => !prev.some((p) => p.filename === r.filename))]);
    } catch (e) {
      setSessErr(e instanceof Error ? e.message : 'could not read attachment');
    }
    if (fileRef.current) fileRef.current.value = '';
  }, []);

  const canSend = !sending && !!session && text.trim().length > 0;

  const send = useCallback(async () => {
    if (!canSend || !session) return;
    // Capture which session this send belongs to — if the user navigates to
    // a different session before the (potentially slow) AI reply arrives,
    // the response must not get applied to whatever session happens to be
    // open when it resolves.
    const sentToSessionId = session.id;
    const isStillCurrent = () => sessionRef.current?.id === sentToSessionId;
    setSending(true);
    setSessErr(null);
    try {
      const r = await api.sendMessage(session.id, {
        text: text.trim(),
        ...(atts.length > 0 ? { attachments: atts } : {}),
      });
      if (!isStillCurrent()) return;
      setSession((s) =>
        s && s.id === sentToSessionId
          ? { ...s, messages: [...s.messages, r.userMessage, r.assistantMessage] }
          : s,
      );
      // unfold any freshly proposed drafts on the incoming message
      const newIdx = (session.messages.length ?? 0) + 1;
      if (r.assistantMessage.proposals && r.assistantMessage.proposals.length > 0) {
        setCardState((cs) => {
          const next = { ...cs };
          for (const p of r.assistantMessage.proposals!) {
            next[`${newIdx}::${p.file}`] = { applied: false, applying: false, err: null, expanded: true };
          }
          return next;
        });
      }
      setText('');
      setAtts([]);
    } catch (e) {
      // sending must always clear once the request settles, whether or not
      // the user navigated away — it's this view's composer-busy flag, not
      // per-session state. Gating it on isStillCurrent() left the composer
      // permanently disabled after navigating away mid-send (the AI reply
      // can take minutes, and backing out is a natural thing to do while
      // waiting) since sending would then never be reset by any later action.
      if (isStillCurrent()) setSessErr(e instanceof Error ? e.message : 'send failed');
    }
    setSending(false);
  }, [canSend, session, text, atts]);

  const cardKey = (msgIdx: number, file: string) => `${msgIdx}::${file}`;
  const getCard = useCallback(
    (msgIdx: number, file: string): CardState =>
      cardState[cardKey(msgIdx, file)] ?? { applied: false, applying: false, err: null, expanded: false },
    [cardState],
  );
  const patchCard = useCallback((msgIdx: number, file: string, patch: Partial<CardState>) => {
    setCardState((cs) => {
      const k = cardKey(msgIdx, file);
      const cur = cs[k] ?? { applied: false, applying: false, err: null, expanded: false };
      return { ...cs, [k]: { ...cur, ...patch } };
    });
  }, []);

  const applyOne = useCallback(
    async (msgIdx: number, p: Proposal) => {
      // Guard against the apply call resolving after the user has switched to
      // a different session — cardState is reset per-session, so a stale
      // patch here would otherwise mislabel a different session's card.
      const sentToSessionId = sessionRef.current?.id;
      const isStillCurrent = () => sessionRef.current?.id === sentToSessionId;
      patchCard(msgIdx, p.file, { applying: true, err: null });
      try {
        await api.assistantApply([{ file: p.file, newContent: p.newContent }]);
        if (isStillCurrent()) patchCard(msgIdx, p.file, { applying: false, applied: true });
      } catch (e) {
        if (isStillCurrent()) {
          patchCard(msgIdx, p.file, {
            applying: false,
            err: e instanceof Error ? e.message : 'apply failed',
          });
        }
      }
    },
    [patchCard],
  );

  const applyAll = useCallback(
    async (msgIdx: number, proposals: Proposal[]) => {
      const sentToSessionId = sessionRef.current?.id;
      const isStillCurrent = () => sessionRef.current?.id === sentToSessionId;
      const pending = proposals.filter((p) => !getCard(msgIdx, p.file).applied);
      if (pending.length === 0) return;
      pending.forEach((p) => patchCard(msgIdx, p.file, { applying: true, err: null }));
      try {
        await api.assistantApply(pending.map(({ file, newContent }) => ({ file, newContent })));
        if (isStillCurrent()) {
          pending.forEach((p) => patchCard(msgIdx, p.file, { applying: false, applied: true }));
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'apply all failed';
        if (isStillCurrent()) {
          pending.forEach((p) => patchCard(msgIdx, p.file, { applying: false, err: msg }));
        }
      }
    },
    [getCard, patchCard],
  );

  // ============================== session list ==============================
  if (!session) {
    return (
      <section>
        <div className="viewhead">
          <h2>DISPATCH</h2>
          <span className="sub">
            session log · draft → review → apply · nothing is written without an explicit APPLY
          </span>
          <span className="spacer" />
          <button className="btn" onClick={() => setShowNew((v) => !v)}>
            {showNew ? '× CANCEL' : '+ NEW'}
          </button>
        </div>

        {showNew && (
          <div className="striprow composer">
            <div className="strip" style={{ marginLeft: 0 }}>
              <div className="cap">
                <span>NEW</span>
                <span className="sub">session</span>
              </div>
              <div className="strip-main">
                {autoOpenNewResearch && (
                  <div className="msg-meta" style={{ marginBottom: 8 }}>
                    First course? Name it below and RESEARCH will help you build it out from scratch.
                  </div>
                )}
                <div className="fields">
                  <div className="fld">
                    <label>mode</label>
                    <div className="seg">
                      <button
                        type="button"
                        className={newMode === 'ask' ? 'on' : ''}
                        onClick={() => setNewMode('ask')}
                      >
                        ASK
                      </button>
                      <button
                        type="button"
                        className={newMode === 'research' ? 'on' : ''}
                        onClick={() => setNewMode('research')}
                      >
                        RESEARCH
                      </button>
                    </div>
                  </div>
                  {newMode === 'research' && (
                    <div className="fld" style={{ minWidth: 200 }}>
                      <label>course name</label>
                      <input
                        value={newCourse}
                        onChange={(e) => setNewCourse(e.target.value)}
                        placeholder="e.g. INAIO"
                      />
                    </div>
                  )}
                  {providers && providers.length > 0 && (
                    <div className="fld">
                      <label>provider</label>
                      <select value={newProvider} onChange={(e) => selectProvider(e.target.value)}>
                        {providers.map((p) => (
                          <option key={p.id} value={p.id}>{p.label}</option>
                        ))}
                      </select>
                    </div>
                  )}
                  <div className="fld">
                    <label>model</label>
                    <select value={newModel} onChange={(e) => setNewModel(e.target.value)}>
                      {modelOptions.map((m) => (
                        <option key={m} value={m}>{m}</option>
                      ))}
                    </select>
                  </div>
                  {effortSupported && (
                    <div className="fld">
                      <label>effort</label>
                      <select value={newEffort} onChange={(e) => setNewEffort(e.target.value)}>
                        {effortOptions.map((m) => (
                          <option key={m} value={m}>{m}</option>
                        ))}
                      </select>
                    </div>
                  )}
                </div>
                {/* provider readiness — small inline smoothing panel, never a hard gate */}
                {(readiness.phase === 'needs-install' ||
                  readiness.phase === 'installing' ||
                  readiness.phase === 'needs-login' ||
                  readiness.phase === 'logging-in') && (
                  <div
                    style={{
                      margin: '10px 0 2px',
                      padding: '8px 10px',
                      border: '1px dashed var(--ink-mid)',
                      borderRadius: 2,
                      display: 'flex',
                      alignItems: 'center',
                      gap: 10,
                      flexWrap: 'wrap',
                      fontSize: 11,
                      color: 'var(--ink-mid)',
                    }}
                  >
                    {(readiness.phase === 'needs-install' || readiness.phase === 'installing') && (
                      <>
                        <span>
                          {activeProvider?.label ?? newProvider} isn't installed yet —
                        </span>
                        <button
                          type="button"
                          className="inkbtn ghost"
                          onClick={installProvider}
                          disabled={readiness.phase === 'installing'}
                        >
                          {readiness.phase === 'installing' ? 'INSTALLING…' : 'INSTALL IT'}
                        </button>
                      </>
                    )}
                    {(readiness.phase === 'needs-login' || readiness.phase === 'logging-in') && (
                      <>
                        <span>
                          {readiness.note ??
                            `You'll need to log in to ${activeProvider?.label ?? newProvider} —`}
                        </span>
                        <button
                          type="button"
                          className="inkbtn ghost"
                          onClick={loginProvider}
                          disabled={readiness.phase === 'logging-in'}
                        >
                          {readiness.phase === 'logging-in' ? 'OPENING…' : 'OPEN LOGIN'}
                        </button>
                        {readiness.note && (
                          <button type="button" className="inkbtn" onClick={continueAfterLogin}>
                            CONTINUE
                          </button>
                        )}
                      </>
                    )}
                    {readiness.err && <span className="ink-err">{readiness.err}</span>}
                  </div>
                )}
                {readiness.phase === 'checking' && (
                  <div style={{ margin: '8px 0 0', fontSize: 10, color: 'var(--ink-faint)' }}>
                    checking {activeProvider?.label ?? newProvider}…
                  </div>
                )}
                {readiness.phase === 'ready' && readiness.note && (
                  <div style={{ margin: '8px 0 0', fontSize: 10, color: 'var(--ink-faint)' }}>
                    {readiness.note}
                  </div>
                )}
                <div className="actions">
                  <button
                    className="inkbtn"
                    onClick={createSession}
                    disabled={creating || (newMode === 'research' && newCourse.trim().length === 0)}
                  >
                    {creating ? 'OPENING…' : 'START'}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {listErr && <Fault msg={listErr} />}
        {sessions === null && <Loading label="READING SESSION LOG" />}
        {opening && <Loading label="PULLING SESSION" />}
        {sessions !== null && sessions.length === 0 && !listErr && (
          <div className="emptynote">no dispatch sessions on file — start one with + NEW</div>
        )}

        {sessions !== null && sessions.length > 0 && (
          <>
            <div className="grouplab">SESSION LOG · {sessions.length} ON FILE</div>
            {sessions.map((s) => (
              <div className="striprow sess-row" key={s.id}>
                <div
                  className="strip clickable"
                  style={{ marginLeft: 0 }}
                  onClick={() => openSession(s.id)}
                >
                  <div className="cap" style={{ background: MODE_COLOR[s.mode], color: '#f3ecda' }}>
                    <span>{s.mode === 'ask' ? 'ASK' : 'RSRCH'}</span>
                    <span className="sub">{s.model}</span>
                  </div>
                  <div className="strip-body">
                    <span className="l1">
                      {s.courseName || s.lastMessagePreview || 'new session — no messages yet'}
                    </span>
                    {s.courseName && s.lastMessagePreview && (
                      <span className="l2">{s.lastMessagePreview}</span>
                    )}
                  </div>
                  <div className="strip-tail">
                    <span className="fine">{relDate(s.updatedAt)}</span>
                  </div>
                </div>
                <button
                  className="microbtn danger"
                  title={armedDelete === s.id ? 'click again to confirm delete' : 'delete session'}
                  style={
                    armedDelete === s.id
                      ? { borderColor: 'var(--led-red)', color: 'var(--led-red)' }
                      : { borderColor: 'var(--board-edge)', color: 'var(--etch-dim)' }
                  }
                  onClick={() => deleteSession(s.id)}
                  onBlur={() => setArmedDelete((a) => (a === s.id ? null : a))}
                >
                  {armedDelete === s.id ? 'SURE?' : '×'}
                </button>
              </div>
            ))}
          </>
        )}
      </section>
    );
  }

  // ============================== open session ==============================
  return (
    <section>
      <div className="viewhead">
        <button className="btn" onClick={() => setSession(null)}>← BACK</button>
        <h2>DISPATCH</h2>
        <Stamp tone={session.mode === 'ask' ? 'ink' : 'green'}>
          {session.mode === 'ask' ? 'ASK' : 'RESEARCH'}
        </Stamp>
        {session.courseName && (
          <span className="plate">
            COURSE <b>{session.courseName}</b>
          </span>
        )}
        <span className="spacer" />
        {/* provider/model/effort are fixed when the session is opened — shown, not editable */}
        {session.provider && (
          <span className="plate" title="set when the session was opened">
            PROVIDER <b>{session.provider}</b>
          </span>
        )}
        <span className="plate" title="set when the session was opened">
          MODEL <b>{session.model}</b>
        </span>
        <span className="plate" title="set when the session was opened">
          EFFORT <b>{session.effort}</b>
        </span>
      </div>

      <div className="chat-thread">
        {session.messages.length === 0 && (
          <div className="emptynote">blank log — write the first dispatch below</div>
        )}
        {session.messages.map((m: Message, i: number) => (
          <div className={`msg ${m.role}`} key={`${m.timestamp}-${i}`}>
            <span className="msg-meta">
              {m.role === 'user' ? 'YOU' : 'AI DESK'} ·{' '}
              {new Date(m.timestamp).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}
            </span>
            <div className={m.role === 'user' ? 'msg-plate' : 'msg-paper'}>{m.text}</div>
            {m.attachments && m.attachments.length > 0 && (
              <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
                {m.attachments.map((a) => (
                  <span className="att-chip" key={a}>📎 {a}</span>
                ))}
              </div>
            )}
            {m.role === 'assistant' && m.proposals && m.proposals.length > 0 && (
              <div className="msg-props">
                <div className="grouplab" style={{ margin: '2px 0 0', display: 'flex', gap: 10, alignItems: 'center' }}>
                  PROPOSED AMENDMENTS · {m.proposals.length} FILE{m.proposals.length === 1 ? '' : 'S'}
                  {m.proposals.filter((p) => !getCard(i, p.file).applied).length > 1 && (
                    <button
                      className="inkbtn"
                      style={{ background: 'var(--board-hi)', borderColor: 'var(--board-edge)', color: 'var(--etch)' }}
                      onClick={() => applyAll(i, m.proposals!)}
                      disabled={m.proposals.some((p) => getCard(i, p.file).applying)}
                    >
                      APPLY ALL ({m.proposals.filter((p) => !getCard(i, p.file).applied).length})
                    </button>
                  )}
                </div>
                {m.proposals.map((p) => {
                  const c = getCard(i, p.file);
                  return (
                    <div
                      className="strip"
                      style={{ flexDirection: 'column' }}
                      key={p.file}
                    >
                      <div className="proposal-head">
                        <div
                          className="cap"
                          style={{ background: c.applied ? 'var(--green-ink)' : 'var(--amber-ink)' }}
                        >
                          <span>{c.applied ? 'FILED' : 'DRAFT'}</span>
                        </div>
                        <span className="l1 proposal-file">{p.file}</span>
                        <span style={{ flex: 1 }} />
                        <button
                          type="button"
                          className="microbtn"
                          onClick={() => patchCard(i, p.file, { expanded: !c.expanded })}
                        >
                          {c.expanded ? 'FOLD' : 'UNFOLD'}
                        </button>
                        {c.applied ? (
                          <Stamp tone="green">APPLIED</Stamp>
                        ) : (
                          <button
                            className="inkbtn"
                            onClick={() => applyOne(i, p)}
                            disabled={c.applying}
                          >
                            {c.applying ? 'FILING…' : 'APPLY'}
                          </button>
                        )}
                      </div>
                      {c.err && <span className="ink-err" style={{ padding: '0 12px 6px' }}>{c.err}</span>}
                      {c.expanded && <pre className="proposal-body">{p.newContent}</pre>}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        ))}
        {sending && (
          <div className="msg assistant">
            <span className="msg-meta">AI DESK</span>
            <div className="loadingrow" style={{ padding: '4px 0' }}>
              WORKING · {elapsed}s — long dispatches can take a few minutes
            </div>
          </div>
        )}
        <div ref={endRef} />
      </div>

      {sessErr && <Fault msg={sessErr} />}

      <div className="striprow chat-composer">
        <div className="strip">
          {atts.length > 0 && (
            <div className="att-row">
              {atts.map((a) => (
                <span className="att-chip" key={a.filename}>
                  📎 {a.filename}
                  <button
                    type="button"
                    title="remove attachment"
                    onClick={() => setAtts((p) => p.filter((x) => x.filename !== a.filename))}
                  >
                    ×
                  </button>
                </span>
              ))}
            </div>
          )}
          <textarea
            className="dispatch-text"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                send();
              }
            }}
            placeholder={
              session.mode === 'ask'
                ? 'Write a dispatch — anything vault-related: amend course details, fix a table, retitle a note…'
                : 'Paste research material or ask a follow-up — the AI drafts course-table additions, nothing invented.'
            }
            rows={4}
            disabled={sending}
          />
          <div className="actions" style={{ paddingTop: 8 }}>
            <button className="inkbtn" onClick={send} disabled={!canSend}>
              {sending ? `SENDING… ${elapsed}s` : '⌘⏎ SEND'}
            </button>
            <button
              className="inkbtn ghost"
              type="button"
              title="attach files"
              onClick={() => fileRef.current?.click()}
              disabled={sending}
            >
              📎 ATTACH
            </button>
            <input
              ref={fileRef}
              type="file"
              multiple
              style={{ display: 'none' }}
              onChange={(e) => pickFiles(e.target.files)}
            />
          </div>
        </div>
      </div>
    </section>
  );
}
