import type {
  AdherenceRow,
  Block,
  BreakdownRow,
  HomeworkItem,
  Message,
  Proposal,
  ProviderInfo,
  ProviderStatus,
  RollupRow,
  ScheduleSlot,
  Session,
  SessionMeta,
  StatsCourseRow,
  StatsHomework,
  SyllabusStatus,
  TimeLogEntry,
} from './types';

const BASE = '/api';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(BASE + path, {
      headers: { 'Content-Type': 'application/json' },
      ...init,
    });
  } catch {
    throw new Error('server unreachable — is the backend running on :4477?');
  }
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const body = await res.json();
      if (body && typeof body.error === 'string') msg = body.error;
    } catch {
      /* keep status message */
    }
    throw new Error(msg);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export const api = {
  courses: () => request<{ courses: string[] }>('/courses'),

  breakdown: (course: string) =>
    request<{ breakdown: BreakdownRow[] }>(
      `/courses/${encodeURIComponent(course)}/breakdown`,
    ),

  next: (course: string) =>
    request<{ next: Block }>(`/courses/${encodeURIComponent(course)}/next`),

  advance: (course: string, topic: string | null, blockType: string) =>
    request<{ advanced: boolean; next: Block | null }>(
      `/courses/${encodeURIComponent(course)}/advance`,
      { method: 'POST', body: JSON.stringify({ topic, blockType }) },
    ),

  schedule: (date: string) =>
    request<{ schedule: ScheduleSlot[] }>(`/schedule/${date}`),

  setSlot: (date: string, slot: ScheduleSlot) =>
    request<{ schedule: ScheduleSlot[] }>(`/schedule/${date}/slot`, {
      method: 'POST',
      body: JSON.stringify(slot),
    }),

  deleteSlot: (date: string, startTime: string) =>
    request<{ schedule: ScheduleSlot[] }>(
      `/schedule/${date}/slot/${encodeURIComponent(startTime)}`,
      { method: 'DELETE' },
    ),

  adherence: (date: string) =>
    request<{ adherence: AdherenceRow[] }>(`/schedule/${date}/adherence`),

  stats: (from: string, to: string) =>
    request<{ courses: StatsCourseRow[]; homework: StatsHomework }>(
      `/stats?from=${from}&to=${to}`,
    ),

  homework: () => request<{ homework: HomeworkItem[] }>('/homework'),

  addHomework: (item: {
    subject: string;
    task: string;
    due_date: string;
    est_minutes: number;
    priority_tag: 'High' | 'Normal' | 'Low';
  }) =>
    request<{ item: HomeworkItem }>('/homework', {
      method: 'POST',
      body: JSON.stringify(item),
    }),

  homeworkDone: (id: string) =>
    request<{ item: HomeworkItem }>(`/homework/${id}/done`, { method: 'POST' }),

  editHomework: (
    id: string,
    patch: Partial<Pick<HomeworkItem, 'subject' | 'task' | 'due_date' | 'est_minutes' | 'priority_tag'>>,
  ) =>
    request<{ item: HomeworkItem }>(`/homework/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(patch),
    }),

  deleteHomework: (id: string) =>
    request<void>(`/homework/${id}`, { method: 'DELETE' }),

  setSyllabus: (course: string, topic: string, status: SyllabusStatus) =>
    request<{ updated: boolean }>(`/courses/${encodeURIComponent(course)}/syllabus`, {
      method: 'PATCH',
      body: JSON.stringify({ topic, status }),
    }),

  listProviders: () => request<{ providers: ProviderInfo[] }>('/assistant/providers'),

  providerStatus: (id: string) =>
    request<ProviderStatus>(`/assistant/providers/${encodeURIComponent(id)}/status`),

  providerInstall: (id: string) =>
    request<{ ok: boolean; message: string }>(
      `/assistant/providers/${encodeURIComponent(id)}/install`,
      { method: 'POST' },
    ),

  providerLogin: (id: string) =>
    request<{ ok: boolean; message: string }>(
      `/assistant/providers/${encodeURIComponent(id)}/login`,
      { method: 'POST' },
    ),

  listSessions: () => request<{ sessions: SessionMeta[] }>('/assistant/sessions'),

  getSession: (id: string) =>
    request<{ session: Session }>(`/assistant/sessions/${encodeURIComponent(id)}`),

  createSession: (body: {
    mode: 'ask' | 'research';
    provider?: string;
    model: string;
    effort: string;
    courseName?: string;
  }) =>
    request<{ session: Session }>('/assistant/sessions', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  deleteSession: (id: string) =>
    request<{ deleted: boolean }>(`/assistant/sessions/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    }),

  sendMessage: (
    id: string,
    body: { text: string; attachments?: { filename: string; contentBase64: string }[] },
  ) =>
    request<{ userMessage: Message; assistantMessage: Message; session: Session }>(
      `/assistant/sessions/${encodeURIComponent(id)}/message`,
      { method: 'POST', body: JSON.stringify(body) },
    ),

  assistantApply: (files: Proposal[]) =>
    request<{ applied: string[] }>('/assistant/apply', {
      method: 'POST',
      body: JSON.stringify({ files }),
    }),

  logTime: (entry: TimeLogEntry) =>
    request<{ entry: TimeLogEntry }>('/timelog', {
      method: 'POST',
      body: JSON.stringify(entry),
    }),

  rollup: (from: string, to: string) =>
    request<{ rollup: RollupRow[] }>(`/timelog/rollup?from=${from}&to=${to}`),
};
