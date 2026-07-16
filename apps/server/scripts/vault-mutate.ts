import { resolve } from 'node:path';
import { HomeworkStore } from '../src/stores/homework.js';
import { ScheduleStore } from '../src/stores/schedule.js';
import { SyllabusParser } from '../src/parsers/syllabus.js';
import { TimeLogStore } from '../src/stores/timeLog.js';

const root = resolve(process.argv[2] || '');
if (!process.argv[2]) throw new Error('Usage: vault-mutate.ts <vault>');

new HomeworkStore(root).markDone('hw-1');
new ScheduleStore(root).setSlot('2026-07-16', {
  start_time: '10:00', duration_min: 30, ref_type: 'homework', ref_label: 'HW · Mathematics — Corrections',
});
new SyllabusParser(root).updateStatus('Mathematics', 'Algebra', 'P');
new TimeLogStore(root).appendLog({
  date: '2026-07-16', ref_type: 'homework', ref_label: 'HW · Mathematics — Corrections',
  course: null, topic: null, blockType: null,
  started_at: '2026-07-16T10:00:00Z', stopped_at: '2026-07-16T10:30:00Z', minutes: 30,
});
