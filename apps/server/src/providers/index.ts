import { execFile } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { promisify } from 'util';
import fs from 'fs';

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export type ProviderType = 'claude' | 'codex' | 'antigravity';

export interface ProviderInfo {
  id: ProviderType;
  label: string;
  models: string[];
  supportsEffort: boolean;
  effortLevels?: string[];
}

export const PROVIDERS: ProviderInfo[] = [
  {
    id: 'claude',
    label: 'Claude',
    models: ['sonnet', 'opus', 'haiku', 'fable'],
    supportsEffort: true,
    effortLevels: ['low', 'medium', 'high', 'xhigh', 'max']
  },
  {
    id: 'codex',
    label: 'Codex',
    models: ['gpt-5.5'],
    supportsEffort: true,
    effortLevels: ['minimal', 'low', 'medium', 'high']
  },
  {
    id: 'antigravity',
    label: 'Antigravity',
    // Exact strings from `agy models` on this machine — effort/thinking level
    // is baked into the model name itself, there's no separate effort flag.
    models: [
      'Gemini 3.5 Flash (Medium)',
      'Gemini 3.5 Flash (High)',
      'Gemini 3.5 Flash (Low)',
      'Gemini 3.1 Pro (Low)',
      'Gemini 3.1 Pro (High)',
      'Claude Sonnet 4.6 (Thinking)',
      'Claude Opus 4.6 (Thinking)',
      'GPT-OSS 120B (Medium)'
    ],
    supportsEffort: false
  }
];
// Gemini (the old standalone `gemini` CLI) was removed as a provider: Google
// discontinued the free-tier CLI client this app relied on. Replaced by
// Antigravity above, whose CLI (`agy`) is now installed and confirmed
// working on this machine.

export function getProviderInfo(id: ProviderType): ProviderInfo | undefined {
  return PROVIDERS.find((p) => p.id === id);
}

/**
 * CLI invocation builder and output parser for each provider.
 * Each provider returns { command, args } for execFile,
 * and an output parser function { resultText, newSessionId }.
 */

export interface ProviderInvocation {
  command: string;
  args: string[];
}

export interface ProviderOutput {
  resultText: string;
  newSessionId: string | null;
}

/**
 * Build Claude CLI arguments
 */
export function buildClaudeInvocation(options: {
  prompt: string;
  model: string;
  effort: string;
  resumeSessionId?: string;
  systemPrompt?: string;
  allowWebTools: boolean;
}): ProviderInvocation {
  const args: string[] = ['-p', options.prompt, '--model', options.model, '--effort', options.effort];

  if (options.systemPrompt) {
    args.push('--append-system-prompt', options.systemPrompt);
  }

  if (options.resumeSessionId) {
    args.push('--resume', options.resumeSessionId);
  }

  // Add MCP config for web tools
  if (options.allowWebTools) {
    // This module is esbuild-bundled into a single dist/index.js, so at
    // runtime __dirname is always the bundle's own directory (dist/), never
    // this source file's original providers/ folder — regardless of which
    // module the code originally lived in, import.meta.url collapses to the
    // bundle's URL post-bundling. tsc (run before esbuild) does still copy
    // mcp-config.json is copied by tsc to dist/providers/mcp-config.json, and
    // Electron packages that same nested path. A flat dist/mcp-config.json path
    // breaks Claude in both dev builds and the packaged app.
    const mcpConfigPath = path.resolve(__dirname, 'providers', 'mcp-config.json');
    args.push('--mcp-config', mcpConfigPath);
  }

  // Explicit tool allow/deny for safety: allow only research tools, deny file-mutating tools
  // CRITICAL: This prevents the CLI from writing vault files even if a tool malfunction occurs
  if (options.allowWebTools) {
    args.push('--allowedTools', 'WebSearch WebFetch Read mcp__playwright__*');
    args.push('--disallowedTools', 'Write Edit Bash NotebookEdit');
  } else {
    // Even without web tools, disable dangerous tools
    args.push('--disallowedTools', 'Write Edit Bash NotebookEdit');
  }

  args.push('--output-format', 'json');

  return { command: 'claude', args };
}

/**
 * Parse Claude JSON envelope output
 */
export function parseClaudeOutput(stdout: string): ProviderOutput {
  try {
    const parsed = JSON.parse(stdout);
    if (!parsed.result) {
      throw new Error('Missing result field in Claude response');
    }

    return {
      resultText: parsed.result,
      newSessionId: parsed.session_id || null
    };
  } catch (error) {
    throw new Error(`Failed to parse Claude output: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Build Codex CLI arguments
 */
export function buildCodexInvocation(options: {
  prompt: string;
  model: string;
  effort: string;
  resumeSessionId?: string;
  systemPrompt?: string;
  allowWebTools: boolean;
}): ProviderInvocation {
  // For Codex, prepend system prompt to the prompt text
  let finalPrompt = options.prompt;
  if (options.systemPrompt) {
    finalPrompt = `${options.systemPrompt}\n\n${options.prompt}`;
  }

  const args: string[] = [];

  // First turn: 'codex exec <prompt>'
  // Later turns: 'codex exec resume <sessionId> <prompt>'
  if (options.resumeSessionId) {
    args.push('exec', 'resume', options.resumeSessionId, finalPrompt);
  } else {
    args.push('exec', finalPrompt);
  }

  // Add model
  if (options.model) {
    args.push('-m', options.model);
  }

  // Add effort via generic config override
  if (options.effort) {
    args.push('-c', `model_reasoning_effort=${options.effort}`);
  }

  // Note: Codex doesn't have a --search flag; web search is available via MCP servers
  // (Codex can use registered MCP servers like playwright for web browsing)

  // Sandbox and approval settings for safety
  // read-only sandbox prevents any file writes at OS level
  args.push('--sandbox', 'read-only');

  // The vault is a plain Obsidian folder, not a git repo — Codex refuses to
  // run in an untrusted (non-git) directory by default. Safe to skip here:
  // the read-only sandbox above is what actually prevents writes, not git-ness.
  args.push('--skip-git-repo-check');

  // JSON output
  args.push('--json');

  return { command: 'codex', args };
}

/**
 * Parse Codex JSONL output.
 * Codex outputs JSONL (one JSON object per line).
 * We look for the final agent message response.
 */
export function parseCodexOutput(stdout: string): ProviderOutput {
  try {
    const lines = stdout.trim().split('\n');
    let resultText = '';
    let sessionId: string | null = null;
    let turnErrorMessage: string | null = null;

    // Real JSONL shapes confirmed live against the installed `codex` CLI —
    // this does NOT match what earlier code assumed:
    //   {"type":"thread.started","thread_id":"<uuid>"}                          <- session id lives here, NOT "session_id"
    //   {"type":"item.completed","item":{"type":"agent_message","text":"..."}}  <- the actual reply, NESTED, field is "text" not "message"
    //   {"type":"item.completed","item":{"type":"error","message":"..."}}       <- non-fatal warning, nested under item — ignore
    //   {"type":"error","message":"..."}                                        <- a genuine top-level turn failure (usage limits, auth)
    //   {"type":"turn.failed","error":{"message":"..."}}                        <- ditto, alternate shape
    for (const line of lines) {
      if (!line.trim()) continue;

      try {
        const obj = JSON.parse(line);

        if (obj.type === 'thread.started' && obj.thread_id) {
          sessionId = obj.thread_id;
        }

        if (obj.type === 'item.completed' && obj.item?.type === 'agent_message' && obj.item.text) {
          resultText = obj.item.text;
        }

        // Only a TOP-LEVEL "error"/"turn.failed" is a real failure — the same
        // "error" type nested inside "item.completed" is just a non-fatal
        // warning (e.g. "Code Mode not supported"), not the turn's outcome.
        if ((obj.type === 'error' || obj.type === 'turn.failed') && !turnErrorMessage) {
          turnErrorMessage = obj.message || obj.error?.message || null;
        }
      } catch {
        // Skip unparseable lines
      }
    }

    if (!resultText) {
      throw new Error(turnErrorMessage || 'No agent message found in Codex response');
    }

    return {
      resultText,
      newSessionId: sessionId
    };
  } catch (error) {
    throw new Error(`Failed to parse Codex output: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Build Antigravity CLI (`agy`) arguments.
 *
 * Confirmed live on this machine (agy 1.1.0):
 * - `-p`/`--print` runs one non-interactive prompt and prints the plain-text
 *   reply to stdout — there is no JSON envelope or structured output flag.
 * - `--model "<exact string>"` accepts the display names from `agy models`
 *   verbatim (e.g. "Gemini 3.5 Flash (Low)") — effort/thinking level is baked
 *   into the model name itself, there's no separate effort flag.
 * - `--continue`/`--conversation <id>` do NOT reliably resume context across
 *   separate cold invocations in this version (tested live: a second call
 *   with the same --conversation id had no memory of the first) — so this
 *   provider is treated as stateless per-call; the caller (routes/assistant.ts)
 *   is responsible for prepending prior turns into `options.prompt` itself.
 * - CRITICAL safety finding (tested live, twice): agy has no real access to
 *   the invoking process's cwd at all by default — even when explicitly told
 *   "this directory is your working directory" and asked to write a file, it
 *   wrote into its own internal sandboxed workspace
 *   (~/.gemini/antigravity-cli/brain/<uuid>/...), never touching the real
 *   directory. `--mode plan` did NOT prevent the write (it just redirected it
 *   to the sandbox) — so the actual safety guarantee here is structural, not
 *   flag-based: NEVER pass `--add-dir <vaultPath>` (the only documented way
 *   to grant real filesystem access), and the vault stays completely
 *   unreachable regardless of what the model tries to do.
 */
export function buildAntigravityInvocation(options: {
  prompt: string;
  model: string;
  effort: string;
  resumeSessionId?: string;
  systemPrompt?: string;
  allowWebTools: boolean;
}): ProviderInvocation {
  let finalPrompt = options.prompt;
  if (options.systemPrompt) {
    finalPrompt = `${options.systemPrompt}\n\n${options.prompt}`;
  }

  const args: string[] = ['--print', finalPrompt];
  if (options.model) {
    args.push('--model', options.model);
  }
  // Defense-in-depth on top of the structural sandboxing above — never
  // combine with --dangerously-skip-permissions or --mode accept-edits,
  // and never pass --add-dir.
  args.push('--mode', 'plan');

  return { command: 'agy', args };
}

/**
 * Parse Antigravity output — plain text, no envelope, no session id.
 */
export function parseAntigravityOutput(stdout: string): ProviderOutput {
  const cleaned = stdout
    .split('\n')
    .map((line) => line.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '').trimEnd())
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed && !/^Thinking\.?$/i.test(trimmed) && !/^Done\.?$/i.test(trimmed);
    })
    .join('\n')
    .trim();
  const resultText = cleaned;
  if (!resultText) {
    throw new Error('Antigravity returned an empty response. Open Antigravity, confirm it is signed in, then try again.');
  }
  return { resultText, newSessionId: null };
}

/**
 * Dispatch to the correct provider's invocation builder
 */
export function buildProviderInvocation(
  provider: ProviderType,
  options: {
    prompt: string;
    model: string;
    effort: string;
    resumeSessionId?: string;
    systemPrompt?: string;
    allowWebTools: boolean;
  }
): ProviderInvocation {
  switch (provider) {
    case 'claude':
      return buildClaudeInvocation(options);
    case 'codex':
      return buildCodexInvocation(options);
    case 'antigravity':
      return buildAntigravityInvocation(options);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}

/**
 * Dispatch to the correct provider's output parser
 */
export function parseProviderOutput(provider: ProviderType, stdout: string): ProviderOutput {
  switch (provider) {
    case 'claude':
      return parseClaudeOutput(stdout);
    case 'codex':
      return parseCodexOutput(stdout);
    case 'antigravity':
      return parseAntigravityOutput(stdout);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}

/**
 * Ensure MCP servers are registered (only for codex; Claude uses per-invocation config)
 * This is called once at server startup to prepare MCP availability.
 */
export async function ensureMcpRegistered(provider: ProviderType): Promise<void> {
  if (provider === 'claude') {
    // Claude uses per-invocation --mcp-config, no pre-registration needed
    return;
  }

  try {
    // Check if playwright MCP is already registered
    const { stdout: listOutput } = await execFileAsync(provider, ['mcp', 'list']);

    if (listOutput.includes('playwright')) {
      // Already registered
      return;
    }

    // Register playwright MCP
    console.log(`Registering playwright MCP for ${provider}...`);
    await execFileAsync(provider, ['mcp', 'add', 'playwright', '--', 'npx', '-y', '@playwright/mcp@latest']);
    console.log(`Playwright MCP registered for ${provider}`);
  } catch (error) {
    // If registration fails, log but don't crash — the CLI may not be available yet
    console.warn(`Warning: Could not register MCP for ${provider}:`, error instanceof Error ? error.message : String(error));
  }
}

/**
 * Initialize MCP servers at startup (async, runs in background)
 */
export function initializeMcpServers(): void {
  // Lazily register MCP for codex at startup so it's available when sessions are created
  ensureMcpRegistered('codex').catch((err) => {
    console.warn('MCP initialization errors (non-fatal):', err);
  });
}
