import fs from 'fs';
import path from 'path';
import { ScheduleSlot } from '../types.js';
import { parseMarkdownTable, sanitizeCell } from '../utils/markdown.js';
import { safeReadFileSync } from '../utils/safeFs.js';

const HEADER = '| start_time | duration_min | ref_type | ref_label |\n| --- | --- | --- | --- |';

export class ScheduleStore {
  private vaultPath: string;

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
  }

  private getSchedulePath(date: string): string {
    return path.join(this.vaultPath, 'Progress', `Schedule-${date}.md`);
  }

  private getScheduleContent(date: string): string {
    return (
      '---\ntype: schedule\ndate: ' +
      date +
      '\nstatus: Active\n---\n\n# Schedule for ' +
      date +
      '\n\n' +
      HEADER
    );
  }

  getSchedule(date: string): ScheduleSlot[] {
    const schedulePath = this.getSchedulePath(date);

    if (!fs.existsSync(schedulePath)) {
      return [];
    }

    const content = safeReadFileSync(schedulePath);
    const rows = parseMarkdownTable(content);

    return rows.map(row => ({
      start_time: row['start_time']?.trim() || '',
      duration_min: parseInt(row['duration_min'] || '0', 10),
      ref_type: (row['ref_type']?.trim() || 'fixed') as 'course' | 'homework' | 'fixed',
      ref_label: row['ref_label']?.trim() || ''
    }));
  }

  setSlot(date: string, slot: ScheduleSlot): void {
    const schedulePath = this.getSchedulePath(date);

    let slots = this.getSchedule(date);

    // Check if slot already exists and update it
    const existingIdx = slots.findIndex(s => s.start_time === slot.start_time);
    if (existingIdx >= 0) {
      slots[existingIdx] = slot;
    } else {
      slots.push(slot);
    }

    // Sort by start_time for consistency
    slots = slots.sort((a, b) => a.start_time.localeCompare(b.start_time));

    // Write back
    const rows = slots.map(s => {
      return `| ${s.start_time} | ${s.duration_min} | ${s.ref_type} | ${sanitizeCell(s.ref_label)} |`;
    });

    const content = this.getScheduleContent(date) + '\n' + rows.join('\n');
    fs.writeFileSync(schedulePath, content);
  }

  getDaySchedule(date: string): ScheduleSlot[] {
    return this.getSchedule(date);
  }

  deleteSlot(date: string, start_time: string): boolean {
    const schedulePath = this.getSchedulePath(date);

    if (!fs.existsSync(schedulePath)) {
      return false;
    }

    let slots = this.getSchedule(date);
    const originalLength = slots.length;

    // Remove slot with matching start_time
    slots = slots.filter(s => s.start_time !== start_time);

    // If nothing was deleted, return false
    if (slots.length === originalLength) {
      return false;
    }

    // Write back
    const rows = slots.map(s => {
      return `| ${s.start_time} | ${s.duration_min} | ${s.ref_type} | ${sanitizeCell(s.ref_label)} |`;
    });

    const content = this.getScheduleContent(date) + (rows.length > 0 ? '\n' + rows.join('\n') : '');
    fs.writeFileSync(schedulePath, content);

    return true;
  }
}
