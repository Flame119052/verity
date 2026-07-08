import fs from 'fs';
import path from 'path';
import { Block, CourseCursor } from '../types.js';
import { parseMarkdownTable, sanitizeCell } from '../utils/markdown.js';
import { safeReadFileSync } from '../utils/safeFs.js';

const HEADER = '| course | last_completed_topic | last_completed_blockType | date |\n| --- | --- | --- | --- |';

export class CourseCursorStore {
  private vaultPath: string;
  private cursorPath: string;
  private cursors: Map<string, CourseCursor> = new Map();

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
    this.cursorPath = path.join(vaultPath, 'Progress', 'Course-Cursor.md');
    this.load();
  }

  private load(): void {
    if (!fs.existsSync(this.cursorPath)) {
      // Initialize with empty header
      this.initializeFile();
      return;
    }

    const content = safeReadFileSync(this.cursorPath);

    // Check if file has old prose format (does it not contain | characters in the body?)
    const lines = content.split('\n');
    const hasTableRows = lines.some(
      (line, idx) => idx > 0 && line.trim().startsWith('|') && !line.includes('---')
    );

    if (!hasTableRows) {
      // Old prose format - reinitialize as table
      this.initializeFile();
      return;
    }

    // Parse table
    const rows = parseMarkdownTable(content);
    for (const row of rows) {
      const course = row['course']?.trim();
      if (!course) continue;

      this.cursors.set(course, {
        course,
        lastTopic: row['last_completed_topic']?.trim() || null,
        lastBlockType: row['last_completed_blockType']?.trim() || null,
        date: row['date']?.trim() || new Date().toISOString().split('T')[0]
      });
    }
  }

  private initializeFile(): void {
    const header = '---\ntype: course_cursor\nstatus: Active\nmode: Course-first, no weekly schedule\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Course Cursor\n\nThis file tracks active course progress. Updated by the Study Command Center backend.\n\n' + HEADER;
    fs.writeFileSync(this.cursorPath, header);
    this.cursors.clear();
  }

  private persist(): void {
    const rows = Array.from(this.cursors.values()).map(cursor => {
      const topic = sanitizeCell(cursor.lastTopic || '');
      const blockType = sanitizeCell(cursor.lastBlockType || '');
      const date = cursor.date;
      return `| ${sanitizeCell(cursor.course)} | ${topic} | ${blockType} | ${date} |`;
    });

    const header = '---\ntype: course_cursor\nstatus: Active\nmode: Course-first, no weekly schedule\nlast_updated: ' + new Date().toISOString().split('T')[0] + '\n---\n\n# Course Cursor\n\nThis file tracks active course progress. Updated by the Study Command Center backend.\n\n' + HEADER;

    const content = header + '\n' + rows.join('\n');
    fs.writeFileSync(this.cursorPath, content);
  }

  getCursor(course: string): { lastTopic: string | null; lastBlockType: string | null; date: string } | null {
    const cursor = this.cursors.get(course);
    return cursor ? { ...cursor } : null;
  }

  /**
   * Advance the cursor for a course. Validates that (topic, blockType) actually
   * matches a real block for this course first — accepting arbitrary client input
   * here would silently desync the cursor (getNextItem falls back to block 0 on
   * any mismatch, which must never happen from bad input going unnoticed).
   */
  advanceCursor(course: string, topic: string | null, blockType: string, blocks: Block[]): { ok: true } | { ok: false; error: string } {
    const courseBlocks = blocks.filter(b => b.course === course);
    const matches = courseBlocks.some(b => b.topic === topic && b.blockType === blockType);

    if (!matches) {
      return { ok: false, error: `No block found for course="${course}" topic="${topic}" blockType="${blockType}"` };
    }

    this.cursors.set(course, {
      course,
      lastTopic: topic,
      lastBlockType: blockType,
      date: new Date().toISOString().split('T')[0]
    });
    this.persist();
    return { ok: true };
  }

  getNextItem(course: string, blocks: Block[]): Block | null {
    const cursor = this.cursors.get(course);
    const courseBlocks = blocks.filter(b => b.course === course);

    if (!cursor || !cursor.lastBlockType) {
      // No cursor exists yet for this course, return first block.
      // Note: lastTopic legitimately IS null for topic-less courses (e.g. IOQM) —
      // only the absence of a cursor or blockType means "start from the top".
      return courseBlocks.length > 0 ? courseBlocks[0] : null;
    }

    // Find the current cursor position
    const currentIdx = courseBlocks.findIndex(
      b => b.topic === cursor.lastTopic && b.blockType === cursor.lastBlockType
    );

    if (currentIdx === -1) {
      // Cursor position not found, return first block
      return courseBlocks.length > 0 ? courseBlocks[0] : null;
    }

    // Return next block, or null if at end
    return currentIdx + 1 < courseBlocks.length ? courseBlocks[currentIdx + 1] : null;
  }
}
