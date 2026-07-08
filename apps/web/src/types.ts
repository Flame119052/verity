export interface Block {
  course: string;
  topic: string | null;
  blockType: string;
  durationRange: string;
  source: string;
  action: string;
  output: string;
  benchmark: string;
}

export type SyllabusStatus = 'NS' | 'L' | 'P' | 'ER' | 'F';

export interface BreakdownRow extends Block {
  syllabusStatus: SyllabusStatus;
}

export interface HomeworkItem {
  id: string;
  subject: string;
  task: string;
  due_date: string;
  est_minutes: number;
  priority_tag: 'High' | 'Normal' | 'Low';
  status: 'open' | 'done';
  created_at: string;
  score?: number;
  scoreReason?: string;
}

export interface ScheduleSlot {
  start_time: string; // "HH:MM"
  duration_min: number;
  ref_type: 'course' | 'homework' | 'fixed';
  ref_label: string;
}

export interface TimeLogEntry {
  ref_type: 'course' | 'homework';
  ref_label: string;
  course: string | null;
  topic: string | null;
  blockType: string | null;
  started_at: string;
  stopped_at: string;
  minutes: number;
}

export interface RollupRow {
  course: string;
  topic: string | null;
  blockType: string | null;
  total_minutes: number;
}

export type AdherenceStatus = 'completed' | 'partial' | 'not_logged' | 'pending' | 'not_tracked';

export interface AdherenceRow extends ScheduleSlot {
  status: AdherenceStatus;
  logged_minutes: number;
}

export interface StatsCourseRow {
  course: string;
  total_minutes: number;
  completed_tasks: number;
  total_tasks: number;
  percent_complete: number;
}

export interface StatsHomework {
  total_minutes: number;
  completed_count: number;
  total_count: number;
  percent_complete: number;
}

export interface Proposal {
  file: string;
  newContent: string;
}

export interface Message {
  role: 'user' | 'assistant';
  text: string;
  proposals?: Proposal[];
  attachments?: string[];
  timestamp: string;
}

/** AI provider descriptor from GET /api/assistant/providers */
export interface ProviderInfo {
  id: 'claude' | 'codex';
  label: string;
  models: string[];
  supportsEffort: boolean;
  effortLevels?: string[];
}

/** GET /api/assistant/providers/:id/status */
export interface ProviderStatus {
  installed: boolean;
  authenticated: boolean | 'unknown';
}

export interface Session {
  id: string;
  mode: 'ask' | 'research';
  provider?: string;
  model: string;
  effort: string;
  courseName?: string;
  createdAt: string;
  updatedAt: string;
  messages: Message[];
}

/** Summary row returned by GET /api/assistant/sessions */
export interface SessionMeta {
  id: string;
  mode: 'ask' | 'research';
  provider?: string;
  model: string;
  courseName?: string;
  createdAt: string;
  updatedAt: string;
  lastMessagePreview?: string;
}

export type ViewId = 'courses' | 'schedule' | 'tracker' | 'homework' | 'stats' | 'assistant';
