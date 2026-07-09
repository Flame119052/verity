import fs from 'fs';
import path from 'path';
import { TimeLogEntry, TimeLogRollup } from '../types.js';
import { parseMarkdownTable, sanitizeCell } from '../utils/markdown.js';
import { safeReadFileSync } from '../utils/safeFs.js';

const HEADER = '| date | ref_type | ref_label | course | topic | blockType | started_at | stopped_at | minutes |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |';

function cell(value: string | null): string {
  return value === null || value === '' ? '-' : sanitizeCell(value);
}

function uncell(value: string | undefined): string | null {
  const v = value?.trim() ?? '';
  return v === '' || v === '-' ? null : v;
}

export class TimeLogStore {
  private vaultPath: string;
  private timeLogPath: string;
  private entries: TimeLogEntry[] = [];

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
    this.timeLogPath = path.join(vaultPath, 'Progress', 'Time-Log.md');
    this.load();
  }

  private load(): void {
    if (!fs.existsSync(this.timeLogPath)) {
      this.initializeFile();
      return;
    }

    const content = safeReadFileSync(this.timeLogPath);
    const rows = parseMarkdownTable(content);

    this.entries = rows.map(row => ({
      date: row['date']?.trim() || '',
      ref_type: (row['ref_type']?.trim() || 'course') as 'course' | 'homework',
      ref_label: row['ref_label']?.trim() || '',
      course: uncell(row['course']),
      topic: uncell(row['topic']),
      blockType: uncell(row['blockType']),
      started_at: row['started_at']?.trim() || '',
      stopped_at: row['stopped_at']?.trim() || '',
      minutes: parseInt(row['minutes'] || '0', 10)
    }));
  }

  private initializeFile(): void {
    const header = '---\ntype: time_log\nstatus: Active\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Time Log\n\nAppend-only log of study and homework time.\n\n' + HEADER;
    fs.mkdirSync(path.dirname(this.timeLogPath), { recursive: true });
    fs.writeFileSync(this.timeLogPath, header);
    this.entries = [];
  }

  private persist(): void {
    const rows = this.entries.map(entry => {
      return `| ${entry.date} | ${entry.ref_type} | ${sanitizeCell(entry.ref_label)} | ${cell(entry.course)} | ${cell(entry.topic)} | ${cell(entry.blockType)} | ${sanitizeCell(entry.started_at)} | ${sanitizeCell(entry.stopped_at)} | ${entry.minutes} |`;
    });

    const header = '---\ntype: time_log\nstatus: Active\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Time Log\n\nAppend-only log of study and homework time.\n\n' + HEADER;

    const content = header + '\n' + rows.join('\n');
    fs.writeFileSync(this.timeLogPath, content);
  }

  appendLog(entry: TimeLogEntry): void {
    this.entries.push(entry);
    this.persist();
  }

  getRollup(from: string, to: string): TimeLogRollup[] {
    const rollup: Map<string, TimeLogRollup> = new Map();

    for (const entry of this.entries) {
      if (entry.date < from || entry.date > to) continue;

      const course = entry.ref_type === 'homework' ? 'Homework' : (entry.course || entry.ref_label);
      const topic = entry.ref_type === 'homework' ? entry.ref_label : entry.topic;
      const blockType = entry.ref_type === 'homework' ? null : entry.blockType;
      const key = `${course} ${topic ?? ''} ${blockType ?? ''}`;

      const existing = rollup.get(key);
      if (existing) {
        existing.total_minutes += entry.minutes;
      } else {
        rollup.set(key, { course, topic, blockType, total_minutes: entry.minutes });
      }
    }

    return Array.from(rollup.values());
  }

  getEntriesForDate(date: string): TimeLogEntry[] {
    return this.entries.filter(entry => entry.date === date);
  }
}
