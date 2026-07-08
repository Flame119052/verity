import { Router, Request, Response } from 'express';
import { HomeworkStore } from '../stores/homework.js';
import { isValidDate, isPositiveNumber, isOneOf } from '../utils/validate.js';

const PRIORITY_TAGS = ['High', 'Normal', 'Low'] as const;

export function createHomeworkRouter(homeworkStore: HomeworkStore): Router {
  const router = Router();

  // GET /api/homework - scored list
  router.get('/', (req: Request, res: Response) => {
    const scored = homeworkStore.getScored();
    res.json({ homework: scored });
  });

  // POST /api/homework - add item
  router.post('/', (req: Request, res: Response) => {
    const { subject, task, due_date, est_minutes, priority_tag } = req.body;

    if (!subject || !task || !due_date || est_minutes === undefined) {
      res.status(400).json({ error: 'subject, task, due_date, and est_minutes are required' });
      return;
    }
    if (typeof subject !== 'string' || typeof task !== 'string') {
      res.status(400).json({ error: 'subject and task must be strings' });
      return;
    }
    if (!isValidDate(due_date)) {
      res.status(400).json({ error: 'due_date must be in YYYY-MM-DD format' });
      return;
    }
    if (!isPositiveNumber(est_minutes)) {
      res.status(400).json({ error: 'est_minutes must be a non-negative number' });
      return;
    }
    if (priority_tag !== undefined && !isOneOf(priority_tag, PRIORITY_TAGS)) {
      res.status(400).json({ error: 'priority_tag must be one of High, Normal, Low' });
      return;
    }

    const item = homeworkStore.addHomework({
      subject,
      task,
      due_date,
      est_minutes,
      priority_tag
    });

    res.status(201).json({ item });
  });

  // POST /api/homework/:id/done - mark done
  router.post('/:id/done', (req: Request, res: Response) => {
    const { id } = req.params;
    const item = homeworkStore.markDone(id);

    if (!item) {
      res.status(404).json({ error: 'Homework item not found' });
      return;
    }

    res.json({ item });
  });

  // PATCH /api/homework/:id - edit fields
  router.patch('/:id', (req: Request, res: Response) => {
    const { id } = req.params;
    const { subject, task, due_date, est_minutes, priority_tag } = req.body;

    const patch: Record<string, unknown> = {};
    if (subject !== undefined) {
      if (typeof subject !== 'string') { res.status(400).json({ error: 'subject must be a string' }); return; }
      patch.subject = subject;
    }
    if (task !== undefined) {
      if (typeof task !== 'string') { res.status(400).json({ error: 'task must be a string' }); return; }
      patch.task = task;
    }
    if (due_date !== undefined) {
      if (!isValidDate(due_date)) { res.status(400).json({ error: 'due_date must be YYYY-MM-DD' }); return; }
      patch.due_date = due_date;
    }
    if (est_minutes !== undefined) {
      if (!isPositiveNumber(est_minutes)) { res.status(400).json({ error: 'est_minutes must be a non-negative number' }); return; }
      patch.est_minutes = est_minutes;
    }
    if (priority_tag !== undefined) {
      if (!isOneOf(priority_tag, PRIORITY_TAGS)) { res.status(400).json({ error: 'priority_tag must be one of High, Normal, Low' }); return; }
      patch.priority_tag = priority_tag;
    }

    const item = homeworkStore.editHomework(id, patch);
    if (!item) {
      res.status(404).json({ error: 'Homework item not found' });
      return;
    }
    res.json({ item });
  });

  // DELETE /api/homework/:id - permanently remove
  router.delete('/:id', (req: Request, res: Response) => {
    const { id } = req.params;
    const deleted = homeworkStore.deleteHomework(id);
    if (!deleted) {
      res.status(404).json({ error: 'Homework item not found' });
      return;
    }
    res.status(204).end();
  });

  return router;
}
