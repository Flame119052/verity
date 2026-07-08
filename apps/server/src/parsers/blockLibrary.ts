import fs from 'fs';
import path from 'path';
import { Block } from '../types.js';
import { safeReadFileSync } from '../utils/safeFs.js';
import { parseMarkdownTable, extractSections, extractUniversalBlockTypes, parseEmbeddedFields } from '../utils/markdown.js';

export class BlockLibraryParser {
  private vaultPath: string;
  private blocks: Block[] = [];
  private universalBlockDurations: Record<string, string> = {};

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
  }

  /**
   * Parse both block library files and return flat array of blocks
   */
  parse(): Block[] {
    this.blocks = [];
    this.parseBoards();
    this.parseCompetition();
    this.parseIOQMTopics();
    this.parseZCOTopics();
    return this.blocks;
  }

  /**
   * Normalize a Board column name to a canonical block-type name that matches
   * the Universal Block Types table exactly ("First Pass", "Exercise Drill",
   * "Timed Mini-Test", etc.) regardless of which column-naming variant a
   * subject's table uses ("First Pass Block" vs "First Pass Output").
   */
  private normalizeBoardsBlockType(columnName: string): string {
    if (/First Pass/i.test(columnName)) return 'First Pass';
    if (/Drill/i.test(columnName)) return 'Exercise Drill';
    if (/Timed/i.test(columnName)) return 'Timed Mini-Test';
    return columnName.trim();
  }

  private parseBoards(): void {
    const boardsPath = path.join(this.vaultPath, 'Courses', 'Boards-Daily-Block-Library.md');
    const content = safeReadFileSync(boardsPath);

    // Extract universal block types first (keys: "First Pass", "Exercise Drill", etc.)
    this.universalBlockDurations = extractUniversalBlockTypes(content);

    const sections = extractSections(content);

    for (const section of sections) {
      const title = section.title.trim();
      if (!title.includes('Block Bank')) continue;

      // Extract subject from title by removing "Block Bank" suffix
      // e.g. "Science Physics Block Bank" -> "Science Physics"
      // "Science Block Bank" -> "Science"
      const subject = title.split('Block Bank')[0].trim();

      // Convert spaces to hyphens for course name
      // e.g. "Science Physics" -> "Boards-Science-Physics"
      // "Science" -> "Boards-Science"
      const courseName = `Boards-${subject.replace(/\s+/g, '-')}`;

      const rows = parseMarkdownTable(section.content);
      if (rows.length === 0) continue;

      const headers = Object.keys(rows[0]);
      // Topic column is "Chapter" for Math/Science, "Area" for Social Science/English/Hindi-Sanskrit/IT
      const topicCol = headers.includes('Chapter') ? 'Chapter' : (headers.includes('Area') ? 'Area' : headers[0]);
      const hasSingleBlockColumn = headers.includes('Block');

      for (const row of rows) {
        const topic = (row[topicCol] || '').trim();
        if (!topic) continue;

        if (hasSingleBlockColumn) {
          // English / Hindi-Sanskrit / IT shape: one block per row.
          // | Area | Block | Output | Benchmark |
          const action = (row['Block'] || '').trim();
          if (!action) continue;
          this.blocks.push({
            course: courseName,
            topic,
            blockType: 'Practice Block',
            durationRange: '',
            source: '',
            action,
            output: (row['Output'] || '').trim(),
            benchmark: (row['Benchmark'] || '').trim()
          });
          continue;
        }

        // Mathematics/Science/Social Science shape: multiple block-type columns per row.
        for (const columnName of headers) {
          if (columnName === topicCol) continue;
          const cell = (row[columnName] || '').trim();
          if (!cell) continue;

          const blockType = this.normalizeBoardsBlockType(columnName);
          const duration = this.universalBlockDurations[blockType] || '';

          if (columnName === 'Timed Benchmark') {
            // Always plain benchmark text, never embedded labels.
            this.blocks.push({
              course: courseName,
              topic,
              blockType,
              durationRange: duration,
              source: '',
              action: '',
              output: '',
              benchmark: cell
            });
          } else if (/Output$/.test(columnName)) {
            // Science/Social Science style: "First Pass Output", "Drill Output" —
            // the cell IS the output text directly, no embedded labels.
            this.blocks.push({
              course: courseName,
              topic,
              blockType,
              durationRange: duration,
              source: '',
              action: '',
              output: cell,
              benchmark: ''
            });
          } else {
            // Mathematics style: "First Pass Block", "Drill Block" — cell has
            // embedded "Source: ... Output: ... Benchmark: ..." labels.
            const fields = parseEmbeddedFields(cell);
            this.blocks.push({
              course: courseName,
              topic,
              blockType,
              durationRange: duration,
              source: fields.source,
              action: fields.action,
              output: fields.output,
              benchmark: fields.benchmark
            });
          }
        }
      }
    }
  }

  private parseCompetition(): void {
    const competitionPath = path.join(this.vaultPath, 'Courses', 'Competition-Daily-Block-Library.md');
    const content = safeReadFileSync(competitionPath);

    const sections = extractSections(content);

    for (const section of sections) {
      const title = section.title.trim();
      if (!title.includes('Block Bank')) continue;

      // "AP Block Bank (Grade 11)" -> "AP", "IOQM Block Bank" -> "IOQM"
      const courseName = title.split('Block Bank')[0].trim();

      // Skip IOQM and ZCO/ZIO here — they are processed separately in parseIOQMTopics/parseZCOTopics
      if (courseName === 'IOQM' || courseName === 'ZCO/ZIO') continue;

      const rows = parseMarkdownTable(section.content);
      if (rows.length === 0) continue;

      const headers = Object.keys(rows[0]);
      const hasDuration = headers.includes('Duration');

      if (hasDuration) {
        // Generic reusable block-type shape: Project Evidence.
        // Columns vary between "Block Type" and "Block", but Duration is always present.
        const blockTypeCol = headers.includes('Block Type') ? 'Block Type' : (headers.includes('Block') ? 'Block' : headers[0]);

        for (const row of rows) {
          const blockType = (row[blockTypeCol] || '').trim();
          if (!blockType) continue;

          this.blocks.push({
            course: courseName,
            topic: null,
            blockType,
            durationRange: (row['Duration'] || '').trim(),
            source: (row['Source'] || '').trim(),
            action: (row['Action'] || '').trim(),
            output: (row['Output'] || '').trim(),
            benchmark: (row['Benchmark'] || '').trim()
          });
        }
      } else {
        // Topic-based single-block-per-row shape: CS50AI ("Unit"/"Daily Block"),
        // INAIO ("Topic"), IRIS ("Stage"), AP ("Exam"/"Start State"), SAT ("Section").
        const topicCol = headers[0];
        const actionCol = headers.includes('Action')
          ? 'Action'
          : headers.includes('Daily Block')
            ? 'Daily Block'
            : headers.includes('Start State')
              ? 'Start State'
              : null;

        for (const row of rows) {
          const topic = (row[topicCol] || '').trim();
          if (!topic) continue;

          this.blocks.push({
            course: courseName,
            topic,
            blockType: 'Practice Block',
            durationRange: '',
            source: (row['Source'] || '').trim(),
            action: actionCol ? (row[actionCol] || '').trim() : '',
            output: (row['Output'] || '').trim(),
            benchmark: (row['Benchmark'] || '').trim()
          });
        }
      }
    }
  }

  private parseIOQMTopics(): void {
    // IOQM topics are read live from the "Topic order:" numbered list under the
    // "IOQM Block Bank" section of Competition-Daily-Block-Library.md — not
    // hardcoded, so this reflects whatever topics the vault's own file actually
    // lists (and produces zero IOQM blocks for a vault with no such section).
    const competitionPath = path.join(this.vaultPath, 'Courses', 'Competition-Daily-Block-Library.md');
    const content = safeReadFileSync(competitionPath);
    const sections = extractSections(content);

    const ioqmSection = sections.find((s) => s.title.trim() === 'IOQM Block Bank');
    if (!ioqmSection) return;

    const topicOrderMatch = ioqmSection.content.match(/Topic order:\s*\n((?:\d+\.\s*.+\n?)+)/);
    if (!topicOrderMatch) return;

    const ioqmTopics = topicOrderMatch[1]
      .split('\n')
      .map((line) => line.replace(/^\d+\.\s*/, '').replace(/\.\s*$/, '').trim())
      .filter(Boolean);

    if (ioqmTopics.length === 0) return;

    // IOQM block types from the table: Concept Primer, Warmup Set, Target Problem, Stretch Problem, Timed Mini-Set, Full Mock
    const blockTypeData: Record<string, Omit<Block, 'course' | 'topic' | 'blockType'>> = {
      'Concept Primer': {
        durationRange: '45-60m',
        source: 'handout/NCERT/RD as named in weekly plan',
        action: 'read only the needed section, then solve examples',
        output: '1-page method sheet',
        benchmark: 'can explain method without notes'
      },
      'Warmup Set': {
        durationRange: '45-60m',
        source: 'IOQM/AoPS/simple exercises',
        action: 'solve 4-8 basic problems',
        output: 'solved set + corrections',
        benchmark: '75%+ without hints'
      },
      'Target Problem': {
        durationRange: '60-90m',
        source: 'IOQM past/archive/AoPS',
        action: 'one medium problem, 45m before hint',
        output: 'full solution',
        benchmark: 'corrected solution in own words'
      },
      'Stretch Problem': {
        durationRange: '60-90m',
        source: 'hard IOQM/AoPS',
        action: 'one hard problem',
        output: 'attempt log + final solution',
        benchmark: 'meaningful progress or clean correction'
      },
      'Timed Mini-Set': {
        durationRange: '75-90m',
        source: 'mixed IOQM problems',
        action: '3-5 problems under time',
        output: 'score + error log',
        benchmark: '60-70% now, 80% before exam'
      },
      'Full Mock': {
        durationRange: '180m + review',
        source: 'official past paper',
        action: 'timed paper',
        output: 'score table',
        benchmark: '30+ by Week 9, 35+ final'
      }
    };

    for (const topic of ioqmTopics) {
      for (const [blockType, fields] of Object.entries(blockTypeData)) {
        this.blocks.push({
          course: 'IOQM',
          topic,
          blockType,
          ...fields
        });
      }
    }
  }

  private parseZCOTopics(): void {
    // Read CPP-for-ZCO.md to extract week topics from Phase 1 and Phase 2.
    // Optional file — a vault with no ZCO prep track simply produces zero
    // ZCO blocks, rather than crashing the whole parse (and the server)
    // before it ever binds a port.
    const zcoPath = path.join(this.vaultPath, 'Courses', 'CPP-for-ZCO.md');
    if (!fs.existsSync(zcoPath)) return;
    const content = safeReadFileSync(zcoPath);

    // Extract Week N: Title headings from the file
    const weekRegex = /^### Week (\d+): (.+)$/gm;
    const zcoTopics: string[] = [];

    let match;
    while ((match = weekRegex.exec(content)) !== null) {
      const weekNum = parseInt(match[1], 10);
      const weekTitle = match[2].trim();
      // Week numbers 1-10 should appear in order
      if (weekNum >= 1 && weekNum <= 10) {
        zcoTopics[weekNum - 1] = weekTitle;
      }
    }

    // Filter to only weeks 1-10
    const weeks1To10 = zcoTopics.slice(0, 10).filter(Boolean);

    // ZCO/ZIO block types from Competition-Daily-Block-Library.md
    const blockTypeData: Record<string, Omit<Block, 'course' | 'topic' | 'blockType'>> = {
      'C++ Syntax Drill': {
        durationRange: '30-45m',
        source: 'CPH + local compiler',
        action: 'write tiny program',
        output: '.cpp file',
        benchmark: 'compiles and output predicted'
      },
      'CSES Beginner': {
        durationRange: '45-75m',
        source: 'CSES Intro/Sorting/etc.',
        action: 'solve the named task from [[Competitions/ZCO-Problem-Queue]]',
        output: 'accepted/local-correct code',
        benchmark: 'passes samples and self-test'
      },
      'Algorithm Concept': {
        durationRange: '45-60m',
        source: 'CPH/cp-algorithms',
        action: 'learn pattern, write template',
        output: 'template + explanation',
        benchmark: 'explain invariant/complexity'
      },
      'ZCO Archive Attempt': {
        durationRange: '90-180m',
        source: 'IARCS archive/CodeDrills',
        action: 'timed old problem',
        output: 'attempt + editorial correction',
        benchmark: 'understands intended solution'
      },
      'ZIO Written Reasoning': {
        durationRange: '45-60m',
        source: 'IARCS/ZIO archive',
        action: 'solve without code',
        output: 'written reasoning',
        benchmark: 'no handwave; cases covered'
      },
      'Contest Practice': {
        durationRange: '90-150m',
        source: 'Codeforces Div 3/CSES',
        action: 'timed set',
        output: 'solved count + error log',
        benchmark: 'no repeated implementation error'
      }
    };

    for (const topic of weeks1To10) {
      for (const [blockType, fields] of Object.entries(blockTypeData)) {
        this.blocks.push({
          course: 'ZCO/ZIO',
          topic,
          blockType,
          ...fields
        });
      }
    }
  }
}
