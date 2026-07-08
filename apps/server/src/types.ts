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

export interface SyllabusItem {
  subject: string;
  unit: string;
  chapter: string;
  marksWeight: string | number;
  status: 'NS' | 'L' | 'P' | 'ER' | 'F';
  evidence: string;
}

export interface CourseCursor {
  course: string;
  lastTopic: string | null;
  lastBlockType: string | null;
  date: string;
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

export interface TimeLogEntry {
  date: string;
  ref_type: 'course' | 'homework';
  ref_label: string; // human-readable display label, e.g. "IOQM: Concept Primer" or a homework task name
  course: string | null; // course name for ref_type=course, null for homework
  topic: string | null;
  blockType: string | null;
  started_at: string;
  stopped_at: string;
  minutes: number;
}

export interface TimeLogRollup {
  course: string; // course name, or "Homework" for ref_type=homework entries
  topic: string | null;
  blockType: string | null;
  total_minutes: number;
}

export interface ScheduleSlot {
  start_time: string;
  duration_min: number;
  ref_type: 'course' | 'homework' | 'fixed';
  ref_label: string;
}

export interface Message {
  role: 'user' | 'assistant';
  text: string;
  proposals?: Array<{ file: string; newContent: string }>;
  attachments?: string[]; // vault-relative paths
  timestamp: string; // ISO
}

export interface Session {
  id: string; // uuid
  provider: 'claude' | 'codex' | 'antigravity';
  mode: 'ask' | 'research';
  model: string;
  effort: string;
  courseName?: string;
  claudeSessionId?: string;
  codexSessionId?: string;
  createdAt: string; // ISO
  updatedAt: string; // ISO
  messages: Message[];
}
