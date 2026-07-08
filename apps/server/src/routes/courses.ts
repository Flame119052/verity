import { Router, Request, Response } from 'express';
import { Block } from '../types.js';
import { BlockLibraryParser } from '../parsers/blockLibrary.js';
import { SyllabusParser } from '../parsers/syllabus.js';
import { CourseCursorStore } from '../stores/courseCursor.js';
import { isOneOf } from '../utils/validate.js';

// Course names are "Boards-<Subject>" or, for split sub-subjects,
// "Boards-<Subject>-<SubSubject>" (e.g. "Boards-Science-Physics"). The syllabus
// checklist has no notion of sub-subjects — it's one flat section per real
// subject — so map the course's first segment after "Boards-" to the
// checklist's actual subject heading, ignoring any sub-subject suffix.
const COURSE_TO_SYLLABUS_SUBJECT: Record<string, string> = {
  Science: 'Science',
  SST: 'Social Science',
  English: 'English Language and Literature',
  Sanskrit: 'Sanskrit / Hindi',
  Mathematics: 'Mathematics',
  IT: 'Information Technology'
};

function syllabusSubjectFor(course: string): string | null {
  const rest = course.replace('Boards-', '');
  const firstSegment = rest.split('-')[0];
  return COURSE_TO_SYLLABUS_SUBJECT[firstSegment] ?? null;
}

// Some checklist chapter names carry qualifiers a plain topic name won't have
// (e.g. "The Making of a Global World: Subtopics 1 to 1.3 for board" vs the
// block library's plain "The Making of a Global World") — match on either
// string being a prefix of the other so close variants still resolve, rather
// than silently falling back to "not started" on a cosmetic mismatch.
function chapterMatches(a: string, b: string): boolean {
  const norm = (s: string) => s.trim().toLowerCase();
  const na = norm(a);
  const nb = norm(b);
  return na === nb || na.startsWith(nb) || nb.startsWith(na);
}

export function createCoursesRouter(
  blocks: Block[],
  syllabusItems: any[],
  cursorStore: CourseCursorStore,
  vaultPath: string
): Router {
  const router = Router();
  const syllabusParser = new SyllabusParser(vaultPath);

  // GET /api/courses - list of distinct courses
  router.get('/', (req: Request, res: Response) => {
    const courses = Array.from(new Set(blocks.map(b => b.course))).sort();
    res.json({ courses });
  });

  // GET /api/courses/:course/breakdown - full topic x block-type rows for that course
  router.get('/:course/breakdown', (req: Request, res: Response) => {
    const { course } = req.params;
    const courseBlocks = blocks.filter(b => b.course === course);

    // Merge with syllabus status if this is a Boards-* course
    const breakdown = courseBlocks.map(block => {
      let syllabusStatus = 'NS';

      if (block.course.startsWith('Boards-')) {
        const subject = syllabusSubjectFor(block.course);
        const match = subject
          ? syllabusItems.find(s => s.subject === subject && block.topic !== null && chapterMatches(s.chapter, block.topic))
          : undefined;
        if (match) {
          syllabusStatus = match.status;
        }
      }

      return {
        ...block,
        syllabusStatus
      };
    });

    res.json({ breakdown });
  });

  // GET /api/courses/:course/next - next item per the cursor
  router.get('/:course/next', (req: Request, res: Response) => {
    const { course } = req.params;
    const nextBlock = cursorStore.getNextItem(course, blocks);

    if (!nextBlock) {
      res.status(404).json({ error: 'No blocks found for this course' });
      return;
    }

    res.json({ next: nextBlock });
  });

  // POST /api/courses/:course/advance - advances cursor
  router.post('/:course/advance', (req: Request, res: Response) => {
    const { course } = req.params;
    const { topic, blockType } = req.body;

    if (!blockType) {
      res.status(400).json({ error: 'blockType is required (topic may be null for topic-less courses)' });
      return;
    }

    const result = cursorStore.advanceCursor(course, topic ?? null, blockType, blocks);
    if (!result.ok) {
      res.status(400).json({ error: result.error });
      return;
    }

    const nextBlock = cursorStore.getNextItem(course, blocks);
    res.json({ advanced: true, next: nextBlock || null });
  });

  // PATCH /api/courses/:course/syllabus - update syllabus status for a topic
  router.patch('/:course/syllabus', (req: Request, res: Response) => {
    const { course } = req.params;
    const { topic, status } = req.body;

    // Validate course is Boards-*
    if (!course.startsWith('Boards-')) {
      res.status(400).json({ error: 'Only Boards-* courses support syllabus status updates' });
      return;
    }

    // Validate status
    const validStatuses = ['NS', 'L', 'P', 'ER', 'F'] as const;
    if (!isOneOf(status, validStatuses)) {
      res.status(400).json({ error: 'status must be one of: NS, L, P, ER, F' });
      return;
    }

    if (!topic || typeof topic !== 'string') {
      res.status(400).json({ error: 'topic is required (string)' });
      return;
    }

    // Map the course's subject segment to the syllabus checklist's actual heading
    const subject = syllabusSubjectFor(course);
    if (!subject) {
      res.status(400).json({ error: `Unknown subject for course "${course}"` });
      return;
    }

    // Check if topic exists in syllabus
    const exists = syllabusItems.find(s => s.subject === subject && chapterMatches(s.chapter, topic));
    if (!exists) {
      res.status(404).json({ error: `Topic "${topic}" not found in ${subject} syllabus` });
      return;
    }

    // Update and persist
    const updated = syllabusParser.updateStatus(subject, topic, status);
    if (!updated) {
      res.status(500).json({ error: 'Failed to update syllabus' });
      return;
    }

    // syllabusItems is the in-memory array GET /:course/breakdown reads from,
    // captured once at server startup — mutate it too so the change is visible
    // immediately instead of only after a restart.
    exists.status = status;

    res.json({ updated });
  });

  return router;
}
