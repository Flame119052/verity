import { Router, Request, Response } from 'express';
import { TimeLogStore } from '../stores/timeLog.js';
import { isValidDate, isPositiveNumber, isOneOf } from '../utils/validate.js';

const REF_TYPES = ['course', 'homework'] as const;

export function createTimeLogRouter(timeLogStore: TimeLogStore): Router {
  const router = Router();

  // POST /api/timelog - append entry
  router.post('/', (req: Request, res: Response) => {
    const { ref_type, ref_label, course, topic, blockType, started_at, stopped_at, minutes } = req.body;

    if (!ref_type || !ref_label || !started_at || !stopped_at || minutes === undefined) {
      res.status(400).json({
        error: 'ref_type, ref_label, started_at, stopped_at, and minutes are required'
      });
      return;
    }
    if (!isOneOf(ref_type, REF_TYPES)) {
      res.status(400).json({ error: 'ref_type must be "course" or "homework"' });
      return;
    }
    if (typeof ref_label !== 'string') {
      res.status(400).json({ error: 'ref_label must be a string' });
      return;
    }
    if (!isPositiveNumber(minutes)) {
      res.status(400).json({ error: 'minutes must be a non-negative number' });
      return;
    }

    const today = new Date().toISOString().split('T')[0];

    const entry = {
      date: today,
      ref_type: ref_type as 'course' | 'homework',
      ref_label,
      course: ref_type === 'course' ? (course ?? ref_label) : null,
      topic: ref_type === 'course' ? (topic ?? null) : null,
      blockType: ref_type === 'course' ? (blockType ?? null) : null,
      started_at,
      stopped_at,
      minutes
    };

    timeLogStore.appendLog(entry);
    res.status(201).json({ entry });
  });

  // GET /api/timelog/rollup - rollup by date range
  router.get('/rollup', (req: Request, res: Response) => {
    const { from, to } = req.query;

    if (!isValidDate(from) || !isValidDate(to)) {
      res.status(400).json({ error: 'from and to query parameters are required (YYYY-MM-DD format)' });
      return;
    }

    const rollup = timeLogStore.getRollup(from, to);
    res.json({ rollup });
  });

  return router;
}
