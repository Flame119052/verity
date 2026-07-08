import fs from 'fs';
import path from 'path';
import { SyllabusItem } from '../types.js';
import { safeReadFileSync } from '../utils/safeFs.js';
import { parseMarkdownTable, extractSections, sanitizeCell } from '../utils/markdown.js';

// Some checklist chapter names carry qualifiers a plain topic name won't have
// (e.g. "The Making of a Global World: Subtopics 1 to 1.3 for board"). Match on
// either string prefixing the other, same tolerance as routes/courses.ts uses.
function chapterMatches(a: string, b: string): boolean {
  const norm = (s: string) => s.trim().toLowerCase();
  const na = norm(a);
  const nb = norm(b);
  return na === nb || na.startsWith(nb) || nb.startsWith(na);
}

export class SyllabusParser {
  private vaultPath: string;

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
  }

  parse(): SyllabusItem[] {
    const syllabusPath = path.join(this.vaultPath, 'Boards', 'Syllabus-Checklist.md');
    const content = safeReadFileSync(syllabusPath);

    const items: SyllabusItem[] = [];
    const sections = extractSections(content);

    for (const section of sections) {
      const title = section.title.trim();

      // Skip non-subject sections
      if (title === 'Planning Rule' || title === 'How To Use') continue;

      // Parse table in this section
      const rows = parseMarkdownTable(section.content);

      for (const row of rows) {
        // Different sections have different column names
        const unit = row['Unit'] || row['Area'] || row['Language'] || '';
        const chapter = row['Chapter'] || row['Chapter / Topic'] || row['Item'] || '';
        const marksWeight = row['Marks Weight'] || '';
        const status = (row['Status'] || 'NS') as 'NS' | 'L' | 'P' | 'ER' | 'F';
        const evidence = row['Evidence'] || '';

        if (!chapter && !unit) continue;

        const item: SyllabusItem = {
          subject: title,
          unit: unit.trim(),
          chapter: chapter.trim(),
          marksWeight: marksWeight.trim(),
          status,
          evidence: evidence.trim()
        };

        items.push(item);
      }
    }

    return items;
  }

  /**
   * Update a syllabus item's status and persist the entire file back to disk.
   * Returns the updated item, or null if the item was not found.
   */
  updateStatus(subject: string, chapter: string, newStatus: 'NS' | 'L' | 'P' | 'ER' | 'F'): SyllabusItem | null {
    const syllabusPath = path.join(this.vaultPath, 'Boards', 'Syllabus-Checklist.md');
    const content = safeReadFileSync(syllabusPath);
    const sections = extractSections(content);

    // First pass: find exactly which row to touch. Prefer an exact chapter
    // match; if none, fall back to a fuzzy match only when it's unambiguous
    // (e.g. two checklist rows can share a prefix like "The Making of a Global
    // World: ..." for different sub-scopes — updating both would be wrong, so
    // multiple fuzzy candidates with no exact match means "don't guess").
    let target: { sectionIdx: number; rowIdx: number } | null = null;
    let fuzzyCandidates: { sectionIdx: number; rowIdx: number }[] = [];
    sections.forEach((section, sectionIdx) => {
      const title = section.title.trim();
      if (title !== subject) return;
      const rows = parseMarkdownTable(section.content);
      rows.forEach((row, rowIdx) => {
        const rowChapter = (row['Chapter'] || row['Chapter / Topic'] || row['Item'] || '').trim();
        if (rowChapter.toLowerCase() === chapter.trim().toLowerCase()) {
          target = { sectionIdx, rowIdx };
        } else if (chapterMatches(rowChapter, chapter)) {
          fuzzyCandidates.push({ sectionIdx, rowIdx });
        }
      });
    });
    if (!target && fuzzyCandidates.length === 1) {
      target = fuzzyCandidates[0];
    }

    let found = false;
    const updatedSections = sections.map((section, sectionIdx) => {
      const title = section.title.trim();
      if (title === 'Planning Rule' || title === 'How To Use') return section;

      // Parse existing table rows
      const rows = parseMarkdownTable(section.content);
      const updatedRows = rows.map((row, rowIdx) => {
        const rowUnit = row['Unit'] || row['Area'] || row['Language'] || '';
        const rowChapter = row['Chapter'] || row['Chapter / Topic'] || row['Item'] || '';
        const rowMarksWeight = row['Marks Weight'] || '';
        const rowStatus = (row['Status'] || 'NS') as 'NS' | 'L' | 'P' | 'ER' | 'F';
        const rowEvidence = row['Evidence'] || '';

        // Only touch the single row identified in the first pass.
        if (target && target.sectionIdx === sectionIdx && target.rowIdx === rowIdx) {
          found = true;
          row['Status'] = newStatus;
        }
        return row;
      });

      // Reconstruct the section content (table)
      if (rows.length === 0) return section;

      // Get headers from first row
      const headers = Object.keys(rows[0]);
      const headerLine = '| ' + headers.join(' | ') + ' |';
      const separatorLine = '| ' + headers.map(() => '---').join(' | ') + ' |';

      const dataLines = updatedRows.map(row => {
        const cells = headers.map(h => sanitizeCell(row[h] || ''));
        return '| ' + cells.join(' | ') + ' |';
      });

      const newContent = headerLine + '\n' + separatorLine + '\n' + dataLines.join('\n');

      return {
        title: section.title,
        content: newContent
      };
    });

    if (!found) return null;

    // Reconstruct the full file
    const sections_with_content: Array<{ title: string; content: string }> = [];
    let frontmatterLines: string[] = [];
    let inFrontmatter = false;
    let frontmatterEnded = false;

    // Extract frontmatter from original content
    const contentLines = content.split('\n');
    for (const line of contentLines) {
      if (!frontmatterEnded && line.startsWith('---')) {
        if (!inFrontmatter) {
          inFrontmatter = true;
          frontmatterLines.push(line);
        } else {
          frontmatterLines.push(line);
          frontmatterEnded = true;
          break;
        }
      } else if (inFrontmatter) {
        frontmatterLines.push(line);
      }
    }

    const frontmatter = frontmatterEnded ? frontmatterLines.join('\n') : '';

    // Preserve any heading/prose between the frontmatter and the first "## "
    // section (e.g. "# Syllabus Checklist") — extractSections() (used above to
    // find which row to update) silently drops this leading content, so it
    // must be recovered directly from the raw file here or it's lost on every
    // rewrite.
    const afterFrontmatterIdx = frontmatterEnded ? frontmatterLines.length : 0;
    const firstSectionIdx = contentLines.findIndex(
      (line, idx) => idx >= afterFrontmatterIdx && line.startsWith('## ')
    );
    const preambleLines =
      firstSectionIdx === -1
        ? contentLines.slice(afterFrontmatterIdx)
        : contentLines.slice(afterFrontmatterIdx, firstSectionIdx);
    const preamble = preambleLines.join('\n').replace(/^\n+/, '').trimEnd();

    let result = frontmatter ? frontmatter + '\n\n' : '';
    if (preamble) result += preamble + '\n\n';

    for (const section of updatedSections) {
      result += '## ' + section.title + '\n\n' + section.content + '\n\n';
    }

    fs.writeFileSync(syllabusPath, result);

    // Return the updated item
    return {
      subject,
      unit: '',
      chapter,
      marksWeight: '',
      status: newStatus,
      evidence: ''
    };
  }
}
