import { Router, Request, Response } from 'express';
import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import { SessionStore } from '../stores/sessions.js';
import { Message, Session } from '../types.js';
import {
  PROVIDERS,
  buildProviderInvocation,
  parseProviderOutput,
  initializeMcpServers,
  type ProviderType
} from '../providers/index.js';
import { checkProviderStatus, installProvider, launchLoginFlow } from '../providers/setup.js';

/**
 * System prompts for each mode
 */
const SYSTEM_PROMPTS = {
  ask: `You are VERITY's in-vault assistant, embedded in a personal study-tracking Obsidian vault app for a student. You have read access to the vault's files and, when useful, web search and browsing tools — use them to look things up, verify facts, or research topics the student asks about. Have a normal, helpful conversation. If — and only if — the student's request clearly implies a concrete change to vault files (course content, syllabus status, homework, etc.), you may propose the change by including a fenced code block labeled json containing a JSON array of objects shaped {"file": "relative/path.md", "newContent": "full new file content"}, using paths relative to the vault root. Most turns will NOT need this — only include it when there's a real, concrete file edit to propose. You cannot write files yourself; any proposal requires the student's explicit approval in the app before anything is saved. Never fabricate facts — if you're not sure, say so or look it up.`,

  research: `You are VERITY's course-research assistant. Your job is to help build out real, exam-relevant study content for a specific course, matching the existing three-stage block format (First Pass / Drill / Timed Benchmark) already used in this vault's Courses/Boards-Daily-Block-Library.md and Courses/Competition-Daily-Block-Library.md files — match that table format and column structure exactly, don't invent new columns. Use any material the student pasted or attached as your primary source, but you also have web search and browsing tools — use them to verify the official syllabus scope, cross-check chapter names and ordering against authoritative sources, and deepen or extend the material meaningfully beyond just what was handed to you, when that adds real value. Briefly mention what sources you used in your reply text (not inside the file content). When you have concrete file changes to propose, include them as a fenced code block labeled json containing a JSON array of {"file": "relative/path.md", "newContent": "full new file content"} objects, paths relative to the vault root. Never fabricate facts not backed by the provided material or something you actually looked up.`
};

/**
 * Both Antigravity's CLI (`agy`) and Codex's CLI block indefinitely waiting
 * on stdin when spawned as a plain child process — confirmed live for each,
 * independently: `execFile`'s default stdio (a pipe that's never closed or
 * written to) causes every single call to hang until the timeout kills it,
 * even though the exact same command completes in under a second when run
 * interactively (where the shell provides a closed/EOF'd stdin implicitly).
 * `execFile`'s own `stdio` option isn't honored the same way `spawn`'s is on
 * this Node version, so a dedicated spawn-based invocation is used for
 * every provider — including Claude, which hasn't shown this symptom, but
 * there's no downside to closing its stdin too, and it protects against a
 * future CLI update silently introducing the same hang.
 */
function runWithClosedStdin(
  command: string,
  args: string[],
  options: { cwd: string; timeout: number; maxBuffer: number },
  callback: (error: Error | null, stdout: string, stderr: string) => void
): void {
  const child = spawn(command, args, { cwd: options.cwd, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let settled = false;
  let killReason: string | null = null;
  const timer = setTimeout(() => {
    if (settled) return;
    settled = true;
    killReason = `timed out after ${options.timeout}ms`;
    child.kill('SIGTERM');
    callback(new Error(`Command ${killReason}`), stdout, stderr);
  }, options.timeout);

  child.stdout.on('data', (d) => {
    stdout += d;
    if (stdout.length > options.maxBuffer && !killReason) {
      killReason = `exceeded max buffer size of ${options.maxBuffer} bytes`;
      child.kill('SIGTERM');
    }
  });
  child.stderr.on('data', (d) => {
    stderr += d;
  });
  child.on('error', (err) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    callback(err, stdout, stderr);
  });
  child.on('close', (code) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    if (killReason) {
      callback(new Error(`Command ${killReason}`), stdout, stderr);
    } else if (code !== 0) {
      callback(new Error(`Command failed with exit code ${code}: ${stderr || stdout}`), stdout, stderr);
    } else {
      callback(null, stdout, stderr);
    }
  });
}

/**
 * On a non-zero exit, the raw error.message (which falls back to stderr,
 * often just a generic "reading additional input from stdin"-style line) is
 * frequently far less useful than the real reason already sitting in stdout
 * — e.g. Codex's `--json` mode emits well-formed JSONL events, including a
 * `{"type":"error","message":"..."}` line with the ACTUAL cause (usage
 * limits, auth failures) even when the process exits non-zero. Prefer that
 * over the generic exit-code message whenever it's present.
 */
function extractCliErrorMessage(provider: string, stdout: string, fallback: string): string {
  if (provider === 'codex' && stdout) {
    const lines = stdout.trim().split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        if ((obj.type === 'error' || obj.type === 'turn.failed') && obj.message) {
          return obj.message;
        }
        if (obj.type === 'turn.failed' && obj.error?.message) {
          return obj.error.message;
        }
      } catch {
        // not a JSON line, skip
      }
    }
  }
  return fallback;
}

export function createAssistantRouter(
  vaultPath: string,
  sessionStore: SessionStore
): Router {
  const router = Router();

  // Initialize MCP servers at startup (async, runs in background)
  initializeMcpServers();

  // GET /api/assistant/providers - Get available providers and models
  router.get('/providers', (req: Request, res: Response) => {
    res.json({ providers: PROVIDERS });
  });

  // GET /api/assistant/providers/:id/status - Check if provider is installed and authenticated
  router.get('/providers/:id/status', async (req: Request, res: Response) => {
    const { id } = req.params;
    const validProviders: ProviderType[] = ['claude', 'codex', 'antigravity'];

    if (!validProviders.includes(id as ProviderType)) {
      res.status(400).json({
        error: `Invalid provider id. Must be one of: ${validProviders.join(', ')}`
      });
      return;
    }

    try {
      const status = await checkProviderStatus(id as ProviderType);
      res.json(status);
    } catch (error) {
      res.status(500).json({
        error: `Failed to check provider status: ${error instanceof Error ? error.message : String(error)}`
      });
    }
  });

  // POST /api/assistant/providers/:id/install - Install a provider CLI globally
  router.post('/providers/:id/install', async (req: Request, res: Response) => {
    const { id } = req.params;
    const validProviders: ProviderType[] = ['claude', 'codex', 'antigravity'];

    if (!validProviders.includes(id as ProviderType)) {
      res.status(400).json({
        error: `Invalid provider id. Must be one of: ${validProviders.join(', ')}`
      });
      return;
    }

    try {
      const result = await installProvider(id as ProviderType);
      res.json(result);
    } catch (error) {
      res.status(500).json({
        error: `Failed to install provider: ${error instanceof Error ? error.message : String(error)}`
      });
    }
  });

  // POST /api/assistant/providers/:id/login - Launch login flow in Terminal
  router.post('/providers/:id/login', async (req: Request, res: Response) => {
    const { id } = req.params;
    const validProviders: ProviderType[] = ['claude', 'codex', 'antigravity'];

    if (!validProviders.includes(id as ProviderType)) {
      res.status(400).json({
        error: `Invalid provider id. Must be one of: ${validProviders.join(', ')}`
      });
      return;
    }

    try {
      const result = await launchLoginFlow(id as ProviderType);
      res.json(result);
    } catch (error) {
      res.status(500).json({
        error: `Failed to launch login flow: ${error instanceof Error ? error.message : String(error)}`
      });
    }
  });

  // POST /api/assistant/sessions - Create a new session
  router.post('/sessions', (req: Request, res: Response) => {
    const { provider = 'claude', mode, model, effort, courseName } = req.body;

    // Validate input
    if (!mode || !model || !effort) {
      res.status(400).json({
        error: 'Body must contain "mode" (ask|research), "model", and "effort"'
      });
      return;
    }

    if (mode !== 'ask' && mode !== 'research') {
      res.status(400).json({
        error: 'mode must be "ask" or "research"'
      });
      return;
    }

    const validProviders: ProviderType[] = ['claude', 'codex', 'antigravity'];
    if (!validProviders.includes(provider)) {
      res.status(400).json({
        error: 'provider must be "claude", "codex", or "antigravity"'
      });
      return;
    }

    if (mode === 'research' && !courseName) {
      res.status(400).json({
        error: 'Research mode requires "courseName"'
      });
      return;
    }

    const session = sessionStore.create(mode, provider, model, effort, courseName);
    res.status(201).json({ session });
  });

  // GET /api/assistant/sessions - List all sessions
  router.get('/sessions', (req: Request, res: Response) => {
    const sessions = sessionStore.list();
    res.json({ sessions });
  });

  // GET /api/assistant/sessions/:id - Get a specific session
  router.get('/sessions/:id', (req: Request, res: Response) => {
    const { id } = req.params;
    const session = sessionStore.get(id);

    if (!session) {
      res.status(404).json({ error: 'Session not found' });
      return;
    }

    res.json({ session });
  });

  // DELETE /api/assistant/sessions/:id - Delete a session
  router.delete('/sessions/:id', (req: Request, res: Response) => {
    const { id } = req.params;
    sessionStore.delete(id);
    res.json({ deleted: true });
  });

  // POST /api/assistant/sessions/:id/message - Send a message and get a reply
  router.post('/sessions/:id/message', (req: Request, res: Response) => {
    const { id } = req.params;
    const { text, attachments } = req.body;

    if (!text || typeof text !== 'string') {
      res.status(400).json({
        error: 'Body must contain "text" (string)'
      });
      return;
    }

    // A huge prompt can blow past a provider CLI's own argument-length limit
    // (crashing the subprocess with an unhelpful OS-level error) or exhaust
    // memory building the antigravity conversation-history transcript.
    const MAX_TEXT_LENGTH = 100_000;
    if (text.length > MAX_TEXT_LENGTH) {
      res.status(400).json({
        error: `"text" is too long (${text.length} chars, max ${MAX_TEXT_LENGTH})`
      });
      return;
    }

    // Load session
    const session = sessionStore.get(id);
    if (!session) {
      res.status(404).json({ error: 'Session not found' });
      return;
    }

    // Process attachments if present
    let attachmentPaths: string[] = [];
    // Antigravity has no real filesystem access at all (confirmed: it cannot
    // see the invoking cwd even when explicitly told to, since we never pass
    // --add-dir) — a vault-relative path is meaningless to it, so its
    // attachments are inlined as text directly into the prompt instead.
    const inlineAttachments: Array<{ filename: string; text: string }> = [];
    if (attachments && Array.isArray(attachments)) {
      const attachmentsDir = path.join(vaultPath, 'Progress', 'Sessions', id, 'attachments');

      // Create attachments directory if needed
      if (!fs.existsSync(attachmentsDir)) {
        fs.mkdirSync(attachmentsDir, { recursive: true });
      }

      for (const att of attachments) {
        if (!att.filename || !att.contentBase64 || att.filename.includes('\0')) {
          continue;
        }

        try {
          // path.basename strips any directory components (including "../"
          // traversal segments) so the file can only ever land directly
          // inside attachmentsDir, never escape it via a crafted filename.
          // (Null bytes are rejected above — Node/the OS would otherwise
          // truncate the filename at the null byte, silently writing to a
          // different, shorter name than what was validated.)
          const safeFilename = path.basename(att.filename);
          if (!safeFilename || safeFilename === '.' || safeFilename === '..') {
            continue;
          }
          const buffer = Buffer.from(att.contentBase64, 'base64');
          const filePath = path.join(attachmentsDir, safeFilename);
          fs.writeFileSync(filePath, buffer);

          // Store vault-relative path
          const relPath = path.join('Progress', 'Sessions', id, 'attachments', safeFilename);
          attachmentPaths.push(relPath);

          if (session.provider === 'antigravity') {
            // Only inline plausibly-textual, reasonably small attachments —
            // skip binary/huge files rather than dumping garbage into the prompt.
            const MAX_INLINE_BYTES = 200 * 1024;
            if (buffer.length <= MAX_INLINE_BYTES) {
              const text = buffer.toString('utf-8');
              // A crude binary-content check: reject if it contains the NUL
              // byte, which real UTF-8 text never does.
              if (!text.includes(' ')) {
                inlineAttachments.push({ filename: safeFilename, text });
              }
            }
          }
        } catch (error) {
          // Skip malformed attachments
        }
      }
    }

    // Build the attachment note — Claude/Codex have real vault filesystem
    // access (cwd = vaultPath) so a relative path is enough; Antigravity has
    // none at all, so its attachments are inlined as text instead.
    let attachmentNote = '';
    if (session.provider === 'antigravity') {
      if (inlineAttachments.length > 0) {
        attachmentNote = '\n\nAttached file(s):\n';
        for (const a of inlineAttachments) {
          attachmentNote += `\n--- ${a.filename} ---\n${a.text}\n`;
        }
      } else if (attachmentPaths.length > 0) {
        attachmentNote =
          '\n\n(Note: file(s) were attached but could not be included as text — this provider cannot read files directly.)';
      }
    } else if (attachmentPaths.length > 0) {
      attachmentNote = '\n\nAttached file(s) (read them from the vault):\n' + attachmentPaths.join('\n');
    }

    // Build the prompt
    let finalPrompt: string;

    if (session.mode === 'research' && session.messages.length === 0) {
      // First message of a research session: include research template in prompt
      finalPrompt = `Using the following research material, propose additions or corrections to the course "${session.courseName}" in this Obsidian vault, following the existing table format in Courses/Boards-Daily-Block-Library.md or Courses/Competition-Daily-Block-Library.md exactly (don't invent new column headers). If you have concrete file changes to propose, include them as a fenced code block labeled json containing a JSON array of {"file": "relative/path.md", "newContent": "full new file content"} objects. Do not fabricate facts not in the material below.

MATERIAL:
${text}`;

      finalPrompt += attachmentNote;
    } else {
      // Ask mode or later turns in research mode
      finalPrompt = text;

      finalPrompt += attachmentNote;

      finalPrompt +=
        '\n\n(If you have concrete vault file changes to propose, include them as a fenced code block labeled json containing a JSON array of {"file": ..., "newContent": ...} objects. Otherwise just reply normally — most turns won\'t need this.)';
    }

    // Antigravity's --continue/--conversation flags don't reliably resume
    // context across separate cold invocations (confirmed live), so prior
    // turns are prepended into the prompt directly instead, up to the last
    // 10 messages to keep the prompt a reasonable size.
    if (session.provider === 'antigravity' && session.messages.length > 0) {
      const priorTurns = session.messages.slice(-10);
      const transcript = priorTurns
        .map((m) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.text}`)
        .join('\n\n');
      finalPrompt = `Previous conversation:\n${transcript}\n\nNew message:\n${finalPrompt}`;
    }

    // Get the system prompt for this mode
    const systemPrompt = SYSTEM_PROMPTS[session.mode];

    // Get the correct session ID field for this provider
    let resumeSessionId: string | undefined;
    if (session.provider === 'claude') {
      resumeSessionId = session.claudeSessionId;
    } else if (session.provider === 'codex') {
      resumeSessionId = session.codexSessionId;
    }

    // Build the provider-specific invocation
    let invocation;
    try {
      invocation = buildProviderInvocation(session.provider, {
        prompt: finalPrompt,
        model: session.model,
        effort: session.effort,
        resumeSessionId,
        systemPrompt,
        allowWebTools: true
      });
    } catch (error) {
      res.status(500).json({
        error: `Failed to build provider invocation: ${error instanceof Error ? error.message : String(error)}`
      });
      return;
    }

    // Invoke the provider's CLI with stdin explicitly closed. Confirmed live
    // that BOTH Antigravity (agy) and Codex hang indefinitely under Node's
    // default execFile stdio (an open, never-written pipe) until the 5-minute
    // timeout kills them — each was independently traced to "reading from
    // stdin" behavior that only reproduces via a real child_process spawn,
    // never in an interactive shell test. Applying this universally (not
    // just to the provider(s) known to need it) is the safer default: a
    // future CLI update or provider swap could introduce the same hang
    // silently, and there is no downside to closing stdin for a provider
    // that doesn't need it.
    runWithClosedStdin(
      invocation.command,
      invocation.args,
      {
        cwd: vaultPath,
        timeout: 5 * 60 * 1000, // 5 minutes
        maxBuffer: 20 * 1024 * 1024 // 20MB
      },
      (error, stdout, stderr) => {
        if (error) {
          res.status(500).json({
            error: `AI CLI execution failed: ${extractCliErrorMessage(session.provider, stdout, error.message)}`
          });
          return;
        }

        // Parse the provider's output
        let parsedOutput;
        try {
          parsedOutput = parseProviderOutput(session.provider, stdout);
        } catch (parseError) {
          res.status(500).json({
            error: `Failed to parse provider output: ${parseError instanceof Error ? parseError.message : String(parseError)}`
          });
          return;
        }

        // Extract optional proposals from result
        let proposals: Array<{ file: string; newContent: string }> = [];
        let displayText = parsedOutput.resultText;
        const proposalMatch = parsedOutput.resultText.match(/```json\s*([\s\S]*?)```/);

        if (proposalMatch) {
          try {
            const extracted = JSON.parse(proposalMatch[1]);
            if (
              Array.isArray(extracted) &&
              extracted.every((p) => typeof p.file === 'string' && typeof p.newContent === 'string')
            ) {
              proposals = extracted;
              // Strip the raw fence from the displayed chat text once its
              // contents are successfully parsed into structured proposals —
              // the DRAFT/APPLY cards render the same info, no need to also
              // show the raw JSON block in the bubble.
              displayText = parsedOutput.resultText.replace(proposalMatch[0], '').trim();
            }
          } catch {
            // If extraction fails, just leave proposals as empty array
          }
        }

        // Build messages
        const userMessage: Message = {
          role: 'user',
          text,
          attachments: attachmentPaths.length > 0 ? attachmentPaths : undefined,
          timestamp: new Date().toISOString()
        };

        const assistantMessage: Message = {
          role: 'assistant',
          text: displayText,
          proposals: proposals.length > 0 ? proposals : undefined,
          timestamp: new Date().toISOString()
        };

        // Store the provider's session ID
        if (parsedOutput.newSessionId) {
          if (session.provider === 'claude') {
            sessionStore.setClaudeSessionId(id, parsedOutput.newSessionId);
          } else if (session.provider === 'codex') {
            sessionStore.setCodexSessionId(id, parsedOutput.newSessionId);
          }
        }

        // Append messages to session
        sessionStore.appendMessage(id, userMessage);
        sessionStore.appendMessage(id, assistantMessage);

        // Get the updated session
        const updatedSession = sessionStore.get(id);

        res.json({
          userMessage,
          assistantMessage,
          session: updatedSession
        });
      }
    );
  });

  // POST /api/assistant/apply - Write proposed files to vault (unchanged from original)
  router.post('/apply', (req: Request, res: Response) => {
    const { files } = req.body;

    if (!Array.isArray(files)) {
      res.status(400).json({
        error: 'Body must contain "files" array with entries: {file: string, newContent: string}'
      });
      return;
    }

    const applied: string[] = [];

    for (const entry of files) {
      const { file, newContent } = entry;

      if (typeof file !== 'string' || typeof newContent !== 'string') {
        res.status(400).json({
          error: 'Each file entry must have "file" (string) and "newContent" (string)'
        });
        return;
      }

      // Resolve file path relative to vault
      const resolvedPath = path.resolve(vaultPath, file);

      // Reject if path escapes vault directory. A plain `startsWith(vaultPath)`
      // check is insufficient — it would wrongly accept a sibling directory
      // that merely shares the same string prefix (e.g. vault
      // "/a/b" + file "../b-evil/x.md" resolves to "/a/b-evil/x.md", which
      // starts with "/a/b" as a string but is NOT inside the vault). Compare
      // against vaultPath + separator instead so only true descendants pass.
      const vaultWithSep = vaultPath.endsWith(path.sep) ? vaultPath : vaultPath + path.sep;
      if (resolvedPath !== vaultPath && !resolvedPath.startsWith(vaultWithSep)) {
        res.status(400).json({
          error: `File path "${file}" escapes vault directory`
        });
        return;
      }

      // Ensure directory exists
      const dir = path.dirname(resolvedPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      // Write file
      fs.writeFileSync(resolvedPath, newContent);
      applied.push(file);
    }

    res.json({ applied });
  });

  return router;
}
