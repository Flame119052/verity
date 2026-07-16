import { resolve } from 'node:path';
import { BlockLibraryParser } from '../src/parsers/blockLibrary.js';
import { SyllabusParser } from '../src/parsers/syllabus.js';
import { CourseCursorStore } from '../src/stores/courseCursor.js';
import { HomeworkStore } from '../src/stores/homework.js';
import { ScheduleStore } from '../src/stores/schedule.js';
import { TimeLogStore } from '../src/stores/timeLog.js';

const root = resolve(process.argv[2] || '');
if (!process.argv[2]) throw new Error('Usage: vault-snapshot.ts <vault>');

const blocks = new BlockLibraryParser(root).parse().sort((a, b) =>
  [a.course, a.topic || '', a.blockType].join('\u001f').localeCompare([b.course, b.topic || '', b.blockType].join('\u001f'))
);
const snapshot = {
  blocks,
  cursors: ['Boards-Mathematics'].map(course => {
    const cursor = new CourseCursorStore(root).getCursor(course);
    return cursor ? { course, ...cursor } : null;
  }).filter(Boolean),
  homework: new HomeworkStore(root).listHomework(),
  logs: new TimeLogStore(root).getEntriesForDate('2026-07-16'),
  schedule: new ScheduleStore(root).getSchedule('2026-07-16'),
  syllabus: new SyllabusParser(root).parse(),
};
process.stdout.write(JSON.stringify(snapshot, null, 2) + '\n');
