import express from 'express';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';
import { BlockLibraryParser } from './parsers/blockLibrary.js';
import { SyllabusParser } from './parsers/syllabus.js';
import { CourseCursorStore } from './stores/courseCursor.js';
import { HomeworkStore } from './stores/homework.js';
import { TimeLogStore } from './stores/timeLog.js';
import { ScheduleStore } from './stores/schedule.js';
import { SessionStore } from './stores/sessions.js';
import { createCoursesRouter } from './routes/courses.js';
import { createHomeworkRouter } from './routes/homework.js';
import { createTimeLogRouter } from './routes/timeLog.js';
import { createScheduleRouter } from './routes/schedule.js';
import { createStatsRouter } from './routes/stats.js';
import { createAssistantRouter } from './routes/assistant.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration loading with fallback chain
interface Config {
  vaultPath: string | null;
  port: number;
}

// Falls back to 4477 for anything that isn't a real, valid TCP port number —
// an unvalidated NaN or out-of-range value passed straight to app.listen()
// binds to an unpredictable/invalid port with no visible error.
function validPort(value: unknown): number {
  const n = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(n) || !Number.isInteger(n) || n < 1 || n > 65535) {
    return 4477;
  }
  return n;
}

function loadConfig(): Config {
  // Step 1: Try reading from hidden config file
  const hiddenConfigDir = path.join(os.homedir(), 'Library', 'Application Support', 'VERITY');
  const hiddenConfigPath = path.join(hiddenConfigDir, 'config.json');

  if (fs.existsSync(hiddenConfigPath)) {
    try {
      const configData = fs.readFileSync(hiddenConfigPath, 'utf-8');
      const config = JSON.parse(configData);
      if (config.vaultPath && typeof config.vaultPath === 'string') {
        return {
          vaultPath: config.vaultPath,
          port: validPort(config.port)
        };
      }
    } catch (error) {
      console.warn(`Warning: Could not parse ${hiddenConfigPath}`, error);
    }
  }

  // Step 2: Fall back to environment variables
  dotenv.config();
  if (process.env.VAULT_PATH) {
    return {
      vaultPath: process.env.VAULT_PATH,
      port: validPort(process.env.PORT)
    };
  }

  // Step 3: Return empty config (setup mode)
  return {
    vaultPath: null,
    port: validPort(process.env.PORT)
  };
}

const config = loadConfig();
const app = express();
const PORT = config.port;

// Middleware
app.use(express.json({ limit: '25mb' }));

// Setup page HTML
const setupPageHTML = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VERITY Setup</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .setup-container {
      background: white;
      border-radius: 12px;
      box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
      padding: 40px;
      max-width: 500px;
      width: 100%;
    }
    h1 {
      color: #333;
      margin-bottom: 10px;
      font-size: 28px;
    }
    .subtitle {
      color: #666;
      margin-bottom: 30px;
      font-size: 14px;
    }
    .form-group {
      margin-bottom: 20px;
    }
    label {
      display: block;
      color: #333;
      margin-bottom: 8px;
      font-weight: 500;
      font-size: 14px;
    }
    input {
      width: 100%;
      padding: 12px;
      border: 1px solid #ddd;
      border-radius: 6px;
      font-size: 14px;
      font-family: inherit;
      transition: border-color 0.2s;
    }
    input:focus {
      outline: none;
      border-color: #667eea;
      box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
    }
    button {
      width: 100%;
      padding: 12px;
      background: #667eea;
      color: white;
      border: none;
      border-radius: 6px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.2s;
    }
    button:hover {
      background: #5568d3;
    }
    button:disabled {
      background: #ccc;
      cursor: not-allowed;
    }
    .message {
      margin-top: 20px;
      padding: 12px;
      border-radius: 6px;
      font-size: 14px;
      display: none;
    }
    .message.success {
      background: #d4edda;
      color: #155724;
      border: 1px solid #c3e6cb;
      display: block;
    }
    .message.error {
      background: #f8d7da;
      color: #721c24;
      border: 1px solid #f5c6cb;
      display: block;
    }
  </style>
</head>
<body>
  <div class="setup-container">
    <h1>VERITY Setup</h1>
    <p class="subtitle">Configure your Obsidian Vault path to get started</p>

    <form id="setupForm">
      <div class="form-group">
        <label for="vaultPath">Vault Path</label>
        <input
          type="text"
          id="vaultPath"
          name="vaultPath"
          placeholder="/Users/username/Projects/Obsidian Vault"
          required
        />
      </div>
      <button type="submit" id="submitBtn">Save & Continue</button>
    </form>

    <div id="message" class="message"></div>
  </div>

  <script>
    document.getElementById('setupForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const vaultPath = document.getElementById('vaultPath').value.trim();
      const messageEl = document.getElementById('message');
      const submitBtn = document.getElementById('submitBtn');

      if (!vaultPath) {
        messageEl.className = 'message error';
        messageEl.textContent = 'Please enter a vault path';
        return;
      }

      submitBtn.disabled = true;
      submitBtn.textContent = 'Saving...';

      try {
        const response = await fetch('/api/setup', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ vaultPath })
        });

        const data = await response.json();

        if (!response.ok) {
          messageEl.className = 'message error';
          messageEl.textContent = data.error || 'Setup failed. Please check the path and try again.';
          submitBtn.disabled = false;
          submitBtn.textContent = 'Save & Continue';
          return;
        }

        messageEl.className = 'message success';
        messageEl.textContent = data.message || 'Setup complete! Please restart VERITY.';
        submitBtn.disabled = true;
        submitBtn.textContent = 'Setup Complete';
      } catch (error) {
        messageEl.className = 'message error';
        messageEl.textContent = 'Network error. Please try again.';
        submitBtn.disabled = false;
        submitBtn.textContent = 'Save & Continue';
      }
    });
  </script>
</body>
</html>
`;

// If VAULT_PATH is not configured, run in setup mode
if (!config.vaultPath) {
  console.log('No vault path configured. Running in setup mode.');

  // Serve the real dual-mode setup page (apps/web/public/setup.html, built into
  // apps/web/dist/setup.html) — NOT the inline setupPageHTML template above,
  // which only has the "existing vault" path field and no "create new vault"
  // option. Fall back to the inline template only if the built file is somehow
  // missing (e.g. a dev environment where the web workspace hasn't been built).
  const setupHtmlPath = path.resolve(__dirname, '../../web/dist/setup.html');
  const serveSetupPage = (req: express.Request, res: express.Response) => {
    if (fs.existsSync(setupHtmlPath)) {
      res.setHeader('Content-Type', 'text/html');
      // sendFile's error callback matters here: the file can vanish between
      // the existsSync check above and this call (e.g. a build re-running
      // concurrently) — without a callback, Express's default HTML error
      // page would be sent instead of falling back gracefully.
      res.sendFile(setupHtmlPath, (err) => {
        if (err && !res.headersSent) {
          res.setHeader('Content-Type', 'text/html');
          res.send(setupPageHTML);
        }
      });
    } else {
      res.setHeader('Content-Type', 'text/html');
      res.send(setupPageHTML);
    }
  };

  // Setup page endpoints
  app.get('/', serveSetupPage);
  app.get('/setup', serveSetupPage);

  app.post('/api/setup', (req, res) => {
    const { vaultPath, createNew } = req.body;

    // Branch 1: Create a new empty vault
    if (createNew === true) {
      try {
        const newVaultPath = path.join(os.homedir(), 'VERITY', 'Vault');

        // Refuse to scaffold on top of an existing vault at the fixed default
        // path — this would silently overwrite real files (Homework, Course
        // Cursor, syllabus, block libraries) in place with empty templates.
        // If it's already there, it's either a real vault worth keeping or a
        // vault the app should just be pointed at, not re-created.
        if (fs.existsSync(newVaultPath)) {
          res.status(409).json({
            error: `A vault already exists at ${newVaultPath}. Point the app at it directly instead of creating a new one, or remove that folder first if you really want a fresh start.`
          });
          return;
        }

        // Create directory structure
        fs.mkdirSync(path.join(newVaultPath, 'Progress'), { recursive: true });
        fs.mkdirSync(path.join(newVaultPath, 'Boards'), { recursive: true });
        fs.mkdirSync(path.join(newVaultPath, 'Courses'), { recursive: true });

        // Helper to get today's date in YYYY-MM-DD format
        const getTodayDate = () => {
          const now = new Date();
          const year = now.getFullYear();
          const month = String(now.getMonth() + 1).padStart(2, '0');
          const day = String(now.getDate()).padStart(2, '0');
          return `${year}-${month}-${day}`;
        };
        const today = getTodayDate();

        // 1. Create Progress/Homework.md
        const homeworkMd = `---
type: homework_tracker
status: Active
last_updated: ${today}
---

# Homework Tracker

Track daily homework and tasks.

| id | subject | task | due_date | est_minutes | priority_tag | status | created_at |
| --- | --- | --- | --- | --- | --- | --- | --- |`;
        fs.writeFileSync(path.join(newVaultPath, 'Progress', 'Homework.md'), homeworkMd);

        // 2. Create Progress/Course-Cursor.md
        const courseCursorMd = `---
type: course_cursor
status: Active
mode: Course-first, no weekly schedule
last_updated: ${today}
---

# Course Cursor

This file tracks active course progress. Updated by the Study Command Center backend.

| course | last_completed_topic | last_completed_blockType | date |
| --- | --- | --- | --- |`;
        fs.writeFileSync(path.join(newVaultPath, 'Progress', 'Course-Cursor.md'), courseCursorMd);

        // 3. Create Progress/Time-Log.md
        const timeLogMd = `---
type: time_log
status: Active
last_updated: ${today}
---

# Time Log

Append-only log of study and homework time.

| date | ref_type | ref_label | course | topic | blockType | started_at | stopped_at | minutes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |`;
        fs.writeFileSync(path.join(newVaultPath, 'Progress', 'Time-Log.md'), timeLogMd);

        // 4. Create Boards/Syllabus-Checklist.md
        const syllabusMd = `---
type: syllabus_checklist
source: "fill in your board/curriculum's official syllabus"
last_updated: ${today}
status: Active
---

# Syllabus Checklist

## Mathematics

| Unit | Chapter | Marks Weight | Status | Evidence |
| --- | --- | --- | --- | --- |

## Science

| Unit | Chapter / Topic | Marks Weight | Status | Evidence |
| --- | --- | --- | --- | --- |

## Social Science

| Area | Chapter | Marks Weight | Status | Evidence |
| --- | --- | --- | --- | --- |

## English Language and Literature

| Area | Item | Marks Weight | Status | Evidence |
| --- | --- | --- | --- | --- |

## Sanskrit / Hindi

| Language | Area | Marks Weight | Status | Evidence |
| --- | --- | --- | --- | --- |`;
        fs.writeFileSync(path.join(newVaultPath, 'Boards', 'Syllabus-Checklist.md'), syllabusMd);

        // 5. Create Courses/Boards-Daily-Block-Library.md
        const boardsBlockLibraryMd = `---
name: "Boards Daily Block Library"
type: "Board Prep"
status: Active
start: ${today}
target_finish: ""
progress_pct: 0
source: "fill in your board/curriculum's official syllabus"
notes: "Reusable exact daily blocks for board and school-exam planning."
---

# Boards Daily Block Library

This is the block bank for course planning.

## Universal Block Types

| Block | Duration | Use When | Output | Benchmark |
|---|---:|---|---|---|
| First Pass | 45-75m | new chapter or forgotten chapter | one-page concept sheet | can explain chapter scope without book |
| Exercise Drill | 60-90m | after first pass | solved exercise set | 80-85% correct |
| Error Repair | 30-60m | after test or failed benchmark | error log + redo set | no repeated error |
| Timed Mini-Test | 60-90m | 2-7 days before paper | scored paper | 80-90% depending phase |
| Final Review | 30-60m | day before paper | formula/definition/map/format sheet | recall without notes |
| Post-Paper Log | 20-30m | day of paper | weak areas and paper pattern | 3 concrete repair tasks |

## Mathematics Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## Science Physics Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## Science Chemistry Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## Science Biology Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## SST History Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## SST Geography Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## SST Economics Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## SST Political Science Block Bank

| Chapter | First Pass Block | Drill Block | Timed Benchmark |
| --- | --- | --- | --- |

## English Block Bank

| Area | Block | Output | Benchmark |
| --- | --- | --- | --- |

## Hindi Block Bank

| Area | Block | Output | Benchmark |
| --- | --- | --- | --- |`;
        fs.writeFileSync(path.join(newVaultPath, 'Courses', 'Boards-Daily-Block-Library.md'), boardsBlockLibraryMd);

        // 6. Create Courses/Competition-Daily-Block-Library.md — an empty shell,
        // no specific tracks pre-assumed; the AI Researcher adds whichever
        // competitions/exams the user actually cares about, each as its own
        // "<Name> Block Bank" section (any name works, the parser is generic).
        const competitionBlockLibraryMd = `---
name: "Competition Daily Block Library"
type: "Exam Prep"
status: Active
start: ${today}
target_finish: ""
progress_pct: 0
source: "fill in as you add tracks"
notes: "Reusable exact daily blocks for olympiads, competitions, or other non-board tracks."
---

# Competition Daily Block Library

Use this file to generate exact daily blocks for non-board tracks. Add a "## <Name> Block Bank" section per track — ask the AI Researcher to help build one out.
`;
        fs.writeFileSync(path.join(newVaultPath, 'Courses', 'Competition-Daily-Block-Library.md'), competitionBlockLibraryMd);

        // Write config file
        const hiddenConfigDir = path.join(os.homedir(), 'Library', 'Application Support', 'VERITY');
        fs.mkdirSync(hiddenConfigDir, { recursive: true });

        const configPath = path.join(hiddenConfigDir, 'config.json');
        const configData = {
          vaultPath: newVaultPath,
          port: PORT
        };

        fs.writeFileSync(configPath, JSON.stringify(configData, null, 2));

        res.json({
          ok: true,
          created: true,
          vaultPath: newVaultPath,
          message: 'New vault created successfully. Please restart VERITY.'
        });
      } catch (error) {
        console.error('Error creating new vault:', error);
        // Clean up any partially-written directory so a retry isn't blocked
        // forever by the existsSync guard above (disk-full or a permission
        // error mid-write would otherwise leave the user permanently locked
        // out of "create new vault").
        try {
          const partialPath = path.join(os.homedir(), 'VERITY', 'Vault');
          if (fs.existsSync(partialPath)) {
            fs.rmSync(partialPath, { recursive: true, force: true });
          }
        } catch (cleanupError) {
          console.error('Failed to clean up partial vault after error:', cleanupError);
        }
        res.status(500).json({
          error: 'Failed to create new vault. Please try again.'
        });
      }
      return;
    }

    // Branch 2: Use existing vault path (original behavior)
    // Validate input
    if (!vaultPath || typeof vaultPath !== 'string' || vaultPath.trim() === '') {
      res.status(400).json({
        error: 'Invalid request: vaultPath must be a non-empty string'
      });
      return;
    }

    const trimmedPath = vaultPath.trim();

    // Single stat call (not existsSync + a separate statSync) to avoid a
    // TOCTOU window where the path could be replaced between the two checks.
    try {
      const stats = fs.statSync(trimmedPath);
      if (!stats.isDirectory()) {
        res.status(400).json({
          error: `Path is not a directory: ${trimmedPath}`
        });
        return;
      }
    } catch (error) {
      res.status(400).json({
        error: `Directory does not exist or cannot be accessed: ${trimmedPath}`
      });
      return;
    }

    // Write config file
    try {
      const hiddenConfigDir = path.join(os.homedir(), 'Library', 'Application Support', 'VERITY');
      fs.mkdirSync(hiddenConfigDir, { recursive: true });

      const configPath = path.join(hiddenConfigDir, 'config.json');
      const configData = {
        vaultPath: trimmedPath,
        port: PORT
      };

      fs.writeFileSync(configPath, JSON.stringify(configData, null, 2));

      res.json({
        ok: true,
        message: 'Setup complete. Please restart VERITY.'
      });
    } catch (error) {
      console.error('Error writing config:', error);
      res.status(500).json({
        error: 'Failed to save configuration. Please try again.'
      });
    }
  });

  // Start server in setup mode (no health check or other routes).
  // Bind to loopback only — this is a single-user personal desktop app with
  // no authentication on any route, so it must never be reachable from the
  // LAN or any other network interface.
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`VERITY setup page listening on port ${PORT}`);
    console.log(`Open http://localhost:${PORT}/ in your browser to configure.`);
  }).on('error', (err: NodeJS.ErrnoException) => {
    // Without this handler, a port conflict (EADDRINUSE) is an unhandled
    // exception that crashes the process — under launchd/Electron that's an
    // invisible crash loop with no indication of why.
    console.error(`Failed to start server on port ${PORT}:`, err.message);
    process.exit(1);
  });
} else {
  // Normal mode: Initialize parsers and stores
  console.log(`Loading from VAULT_PATH: ${config.vaultPath}`);

  const blockParser = new BlockLibraryParser(config.vaultPath);
  const syllabusParser = new SyllabusParser(config.vaultPath);

  // A corrupted/unreadable vault file (bad permissions, malformed markdown,
  // mid-write from another process) must not crash the whole server at
  // startup — under launchd's KeepAlive that becomes an infinite crash loop
  // the user can't escape without manually editing files outside the app.
  // Degrade to empty data instead so the app stays reachable.
  let blocks: ReturnType<typeof blockParser.parse> = [];
  try {
    blocks = blockParser.parse();
  } catch (error) {
    console.error('Failed to parse block libraries — continuing with zero blocks:', error);
  }

  let syllabusItems: ReturnType<typeof syllabusParser.parse> = [];
  try {
    syllabusItems = syllabusParser.parse();
  } catch (error) {
    console.error('Failed to parse syllabus checklist — continuing with zero syllabus items:', error);
  }

  console.log(`Loaded ${blocks.length} blocks from block libraries`);
  console.log(`Loaded ${syllabusItems.length} syllabus items`);

  const cursorStore = new CourseCursorStore(config.vaultPath);
  const homeworkStore = new HomeworkStore(config.vaultPath);
  const timeLogStore = new TimeLogStore(config.vaultPath);
  const scheduleStore = new ScheduleStore(config.vaultPath);
  const sessionStore = new SessionStore(config.vaultPath);

  // Routes
  app.use('/api/courses', createCoursesRouter(blocks, syllabusItems, cursorStore, config.vaultPath));
  app.use('/api/homework', createHomeworkRouter(homeworkStore));
  app.use('/api/timelog', createTimeLogRouter(timeLogStore));
  app.use('/api/schedule', createScheduleRouter(scheduleStore, timeLogStore));
  app.use('/api/stats', createStatsRouter(blocks, timeLogStore, homeworkStore, cursorStore));
  app.use('/api/assistant', createAssistantRouter(config.vaultPath, sessionStore));

  // Health check
  app.get('/api/health', (req, res) => {
    res.json({
      status: 'ok',
      blocks_loaded: blocks.length,
      syllabus_items_loaded: syllabusItems.length
    });
  });

  // Serve static files from web/dist if it exists (SPA fallback)
  const distPath = path.resolve(__dirname, '../../web/dist');
  const webDistExists = fs.existsSync(distPath);

  if (webDistExists) {
    app.use(express.static(distPath));
    // SPA fallback: non-API routes go to index.html
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  } else {
    app.get('/', (req, res) => {
      res.json({
        message: 'Study Command Center API',
        status: 'ready',
        note: 'Web frontend not built yet. See /api/health for API status.'
      });
    });
  }

  // JSON error-handling middleware — express.json() throws a raw error on malformed
  // bodies that would otherwise fall through to Express's default HTML error page.
  app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (err.type === 'entity.parse.failed') {
      res.status(400).json({ error: 'Malformed JSON in request body' });
      return;
    }
    next(err);
  });

  // Start server. Bind to loopback only — this is a single-user personal
  // desktop app with no authentication on any route, so it must never be
  // reachable from the LAN or any other network interface.
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`Study Command Center listening on port ${PORT}`);
    console.log(`API ready at http://localhost:${PORT}/api`);
  }).on('error', (err: NodeJS.ErrnoException) => {
    console.error(`Failed to start server on port ${PORT}:`, err.message);
    process.exit(1);
  });
}
