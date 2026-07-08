import fs from 'fs';
import path from 'path';
import { randomUUID } from 'crypto';
import { HomeworkItem } from '../types.js';
import { parseMarkdownTable, sanitizeCell } from '../utils/markdown.js';
import { safeReadFileSync } from '../utils/safeFs.js';

const HEADER = '| id | subject | task | due_date | est_minutes | priority_tag | status | created_at |\n| --- | --- | --- | --- | --- | --- | --- | --- |';

export class HomeworkStore {
  private vaultPath: string;
  private homeworkPath: string;
  private items: Map<string, HomeworkItem> = new Map();

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
    this.homeworkPath = path.join(vaultPath, 'Progress', 'Homework.md');
    this.load();
  }

  private load(): void {
    if (!fs.existsSync(this.homeworkPath)) {
      this.initializeFile();
      return;
    }

    const content = safeReadFileSync(this.homeworkPath);
    const rows = parseMarkdownTable(content);

    for (const row of rows) {
      const id = row['id']?.trim();
      if (!id) continue;

      const item: HomeworkItem = {
        id,
        subject: row['subject']?.trim() || '',
        task: row['task']?.trim() || '',
        due_date: row['due_date']?.trim() || '',
        est_minutes: parseInt(row['est_minutes'] || '0', 10),
        priority_tag: (row['priority_tag']?.trim() || 'Normal') as 'High' | 'Normal' | 'Low',
        status: (row['status']?.trim() || 'open') as 'open' | 'done',
        created_at: row['created_at']?.trim() || new Date().toISOString()
      };

      this.items.set(id, item);
    }
  }

  private initializeFile(): void {
    const header = '---\ntype: homework_tracker\nstatus: Active\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Homework Tracker\n\nTrack daily homework and tasks.\n\n' + HEADER;
    fs.writeFileSync(this.homeworkPath, header);
    this.items.clear();
  }

  private persist(): void {
    const rows = Array.from(this.items.values()).map(item => {
      return `| ${item.id} | ${sanitizeCell(item.subject)} | ${sanitizeCell(item.task)} | ${item.due_date} | ${item.est_minutes} | ${item.priority_tag} | ${item.status} | ${item.created_at} |`;
    });

    const header = '---\ntype: homework_tracker\nstatus: Active\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Homework Tracker\n\nTrack daily homework and tasks.\n\n' + HEADER;

    const content = header + '\n' + rows.join('\n');
    fs.writeFileSync(this.homeworkPath, content);
  }

  listHomework(): HomeworkItem[] {
    return Array.from(this.items.values());
  }

  addHomework(input: {
    subject: string;
    task: string;
    due_date: string;
    est_minutes: number;
    priority_tag?: 'High' | 'Normal' | 'Low';
  }): HomeworkItem {
    const id = randomUUID().substring(0, 8);
    const now = new Date().toISOString();

    const item: HomeworkItem = {
      id,
      subject: input.subject,
      task: input.task,
      due_date: input.due_date,
      est_minutes: input.est_minutes,
      priority_tag: input.priority_tag || 'Normal',
      status: 'open',
      created_at: now
    };

    this.items.set(id, item);
    this.persist();
    return item;
  }

  markDone(id: string): HomeworkItem | null {
    const item = this.items.get(id);
    if (!item) return null;

    item.status = 'done';
    this.items.set(id, item);
    this.persist();
    return item;
  }

  deleteHomework(id: string): boolean {
    const existed = this.items.delete(id);
    if (existed) this.persist();
    return existed;
  }

  editHomework(id: string, patch: Partial<Pick<HomeworkItem, 'subject' | 'task' | 'due_date' | 'est_minutes' | 'priority_tag'>>): HomeworkItem | null {
    const item = this.items.get(id);
    if (!item) return null;
    Object.assign(item, patch);
    this.items.set(id, item);
    this.persist();
    return item;
  }

  getScored(): (HomeworkItem & { score: number; scoreReason: string })[] {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const scored = Array.from(this.items.values())
      .filter(item => item.status === 'open')
      .map(item => {
        const dueDate = new Date(item.due_date);
        dueDate.setHours(0, 0, 0, 0);
        const daysUntilDue = Math.floor((dueDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));

        let score = 0;
        let scoreReason = '';

        // Overdue items score highest
        if (daysUntilDue < 0) {
          score = 1000 + Math.abs(daysUntilDue);
          scoreReason = `overdue by ${Math.abs(daysUntilDue)} days`;
        } else {
          // Not yet overdue; lower score is better
          score = daysUntilDue;
          scoreReason = `due in ${daysUntilDue} days`;
        }

        // Priority tiebreaker
        const priorityMultiplier: Record<string, number> = { High: 100, Normal: 50, Low: 10 };
        score += priorityMultiplier[item.priority_tag] || 50;

        return {
          ...item,
          score,
          scoreReason
        };
      })
      .sort((a, b) => {
        // Overdue items first
        const aOverdue = a.score >= 1000 ? 1 : 0;
        const bOverdue = b.score >= 1000 ? 1 : 0;
        if (aOverdue !== bOverdue) return bOverdue - aOverdue;

        // Then by score
        return a.score - b.score;
      });

    return scored;
  }
}
