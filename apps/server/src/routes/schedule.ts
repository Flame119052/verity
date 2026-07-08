import { Router, Request, Response } from 'express';
import { ScheduleStore } from '../stores/schedule.js';
import { TimeLogStore } from '../stores/timeLog.js';
import { isValidDate, isValidTime, isPositiveNumber, isOneOf } from '../utils/validate.js';

const SLOT_REF_TYPES = ['course', 'homework', 'fixed'] as const;

export function createScheduleRouter(scheduleStore: ScheduleStore, timeLogStore?: TimeLogStore): Router {
  const router = Router();

  // GET /api/schedule/:date
  router.get('/:date', (req: Request, res: Response) => {
    const { date } = req.params;

    // Validate date format (YYYY-MM-DD)
    if (!isValidDate(date)) {
      res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
      return;
    }

    const schedule = scheduleStore.getDaySchedule(date);
    res.json({ schedule });
  });

  // POST /api/schedule/:date/slot - add or update slot
  router.post('/:date/slot', (req: Request, res: Response) => {
    const { date } = req.params;
    const { start_time, duration_min, ref_type, ref_label } = req.body;

    // Validate date format (YYYY-MM-DD)
    if (!isValidDate(date)) {
      res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
      return;
    }

    if (!start_time || duration_min === undefined || !ref_type || !ref_label) {
      res.status(400).json({
        error: 'start_time, duration_min, ref_type, and ref_label are required'
      });
      return;
    }
    if (!isValidTime(start_time)) {
      res.status(400).json({ error: 'start_time must be in HH:MM 24-hour format' });
      return;
    }
    if (!isPositiveNumber(duration_min) || duration_min <= 0) {
      res.status(400).json({ error: 'duration_min must be a positive number' });
      return;
    }
    if (!isOneOf(ref_type, SLOT_REF_TYPES)) {
      res.status(400).json({ error: 'ref_type must be one of course, homework, fixed' });
      return;
    }
    if (typeof ref_label !== 'string') {
      res.status(400).json({ error: 'ref_label must be a string' });
      return;
    }

    scheduleStore.setSlot(date, {
      start_time,
      duration_min,
      ref_type: ref_type as 'course' | 'homework' | 'fixed',
      ref_label
    });

    const schedule = scheduleStore.getDaySchedule(date);
    res.json({ schedule });
  });

  // DELETE /api/schedule/:date/slot/:start_time - remove a slot
  router.delete('/:date/slot/:start_time', (req: Request, res: Response) => {
    const { date, start_time } = req.params;

    // Validate date format (YYYY-MM-DD)
    if (!isValidDate(date)) {
      res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
      return;
    }

    // Decode start_time from URL encoding (e.g., 09%3A00 -> 09:00)
    const decodedStartTime = decodeURIComponent(start_time);

    const deleted = scheduleStore.deleteSlot(date, decodedStartTime);
    if (!deleted) {
      res.status(404).json({ error: 'Slot not found' });
      return;
    }

    const schedule = scheduleStore.getDaySchedule(date);
    res.json({ schedule });
  });

  // GET /api/schedule/:date/adherence - check slot adherence against time log
  router.get('/:date/adherence', (req: Request, res: Response) => {
    const { date } = req.params;

    // Validate date format (YYYY-MM-DD)
    if (!isValidDate(date)) {
      res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
      return;
    }

    if (!timeLogStore) {
      res.status(501).json({ error: 'Time log store not available' });
      return;
    }

    const slots = scheduleStore.getDaySchedule(date);
    const today = new Date().toISOString().split('T')[0];
    const isToday = date === today;

    const adherence = slots.map(slot => {
      if (slot.ref_type === 'fixed') {
        return {
          ...slot,
          status: 'not_tracked',
          logged_minutes: 0
        };
      }

      // Check if slot is in the future (only if today)
      if (isToday) {
        const [hours, minutes] = slot.start_time.split(':').map(Number);
        const slotTime = new Date();
        slotTime.setHours(hours, minutes, 0, 0);
        if (slotTime > new Date()) {
          return {
            ...slot,
            status: 'pending',
            logged_minutes: 0
          };
        }
      }

      // Get matching time log entries
      const timeLogEntries = timeLogStore.getEntriesForDate(date);
      let logged_minutes = 0;

      if (slot.ref_type === 'homework') {
        // For homework slots, match any homework entry
        logged_minutes = timeLogEntries
          .filter(entry => entry.ref_type === 'homework')
          .reduce((sum, entry) => sum + entry.minutes, 0);
      } else {
        // For course slots, match the course from ref_label
        const courseMatch = slot.ref_label.split(' · ')[0];
        logged_minutes = timeLogEntries
          .filter(entry => entry.ref_type === 'course' && entry.course === courseMatch)
          .reduce((sum, entry) => sum + entry.minutes, 0);
      }

      let status: string;
      if (logged_minutes >= slot.duration_min * 0.9) {
        status = 'completed';
      } else if (logged_minutes > 0) {
        status = 'partial';
      } else {
        status = 'not_logged';
      }

      return {
        ...slot,
        status,
        logged_minutes
      };
    });

    res.json({ adherence });
  });

  return router;
}
