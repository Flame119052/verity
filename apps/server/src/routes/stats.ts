import { Router, Request, Response } from 'express';
import { Block } from '../types.js';
import { TimeLogStore } from '../stores/timeLog.js';
import { HomeworkStore } from '../stores/homework.js';
import { CourseCursorStore } from '../stores/courseCursor.js';

export function createStatsRouter(
  blocks: Block[],
  timeLogStore: TimeLogStore,
  homeworkStore: HomeworkStore,
  cursorStore: CourseCursorStore
): Router {
  const router = Router();

  // GET /api/stats?from=YYYY-MM-DD&to=YYYY-MM-DD
  router.get('/', (req: Request, res: Response) => {
    const { from, to } = req.query;

    if (!from || !to || typeof from !== 'string' || typeof to !== 'string') {
      res.status(400).json({ error: 'from and to query parameters are required (YYYY-MM-DD format)' });
      return;
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
      res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
      return;
    }

    // Get all distinct courses
    const courseSet = new Set(blocks.map(b => b.course));
    const courses = Array.from(courseSet).sort();

    // Get time log rollup
    const rollup = timeLogStore.getRollup(from, to);

    // Build stats for each course
    const courseStats = courses.map(course => {
      const courseBlocks = blocks.filter(b => b.course === course);
      const totalTasks = courseBlocks.length;

      // Get cursor to find completed_tasks (position in ordered list)
      const cursor = cursorStore.getCursor(course);
      let completedTasks = 0;
      if (cursor && cursor.lastBlockType) {
        const currentIdx = courseBlocks.findIndex(
          b => b.topic === cursor.lastTopic && b.blockType === cursor.lastBlockType
        );
        if (currentIdx >= 0) {
          completedTasks = currentIdx + 1;
        }
      }

      // Sum total_minutes for this course from rollup
      const totalMinutes = rollup
        .filter(r => r.course === course)
        .reduce((sum, r) => sum + r.total_minutes, 0);

      const percentComplete = totalTasks > 0 ? Math.round((completedTasks / totalTasks) * 100) : 0;

      return {
        course,
        total_minutes: totalMinutes,
        completed_tasks: completedTasks,
        total_tasks: totalTasks,
        percent_complete: percentComplete
      };
    });

    // Build stats for homework
    const homeworkItems = homeworkStore.listHomework();
    const completedCount = homeworkItems.filter(item => item.status === 'done').length;
    const totalCount = homeworkItems.length;
    const homeworkPercent = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

    // Sum homework minutes from time log (all homework entries, regardless of date range)
    const homeworkMinutes = rollup
      .filter(r => r.course === 'Homework')
      .reduce((sum, r) => sum + r.total_minutes, 0);

    const homeworkStats = {
      total_minutes: homeworkMinutes,
      completed_count: completedCount,
      total_count: totalCount,
      percent_complete: homeworkPercent
    };

    res.json({
      courses: courseStats,
      homework: homeworkStats
    });
  });

  return router;
}
