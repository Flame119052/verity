import { execFile } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { promisify } from 'util';
import fs from 'fs';

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export type ProviderType = 'claude' | 'codex' | 'gemini';

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
    id: 'gemini',
    label: 'Gemini',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
    supportsEffort: false
  }
];

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
    const mcpConfigPath = path.resolve(__dirname, 'mcp-config.json');
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

    // Parse JSONL: find the final agent message and any session_id
    for (const line of lines) {
      if (!line.trim()) continue;

      try {
        const obj = JSON.parse(line);

        // Look for agent message
        if (obj.type === 'agent_message' && obj.message) {
          resultText = obj.message;
        }

        // Look for session ID
        if (obj.session_id) {
          sessionId = obj.session_id;
        }
      } catch {
        // Skip unparseable lines
      }
    }

    if (!resultText) {
      throw new Error('No agent message found in Codex response');
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
 * Build Gemini CLI arguments
 */
export function buildGeminiInvocation(options: {
  prompt: string;
  model: string;
  effort: string;
  resumeSessionId?: string;
  systemPrompt?: string;
  allowWebTools: boolean;
}): ProviderInvocation {
  // For Gemini, prepend system prompt to the prompt text
  let finalPrompt = options.prompt;
  if (options.systemPrompt) {
    finalPrompt = `${options.systemPrompt}\n\n${options.prompt}`;
  }

  const args: string[] = ['-p', finalPrompt];

  // Model
  if (options.model) {
    args.push('-m', options.model);
  }

  // Resume
  if (options.resumeSessionId) {
    args.push('-r', options.resumeSessionId);
  }

  // Note: Gemini does NOT support effort levels, so we omit that

  // For web tools via MCP, restrict to just playwright server if registered
  // (Gemini can also use built-in search but we'll rely on MCP for consistency)
  // Approval mode: use 'plan' to allow tool use but prevent execution of writes
  // (If 'plan' mode exists and prevents execution, this adds safety)
  if (options.allowWebTools) {
    args.push('--allowed-mcp-server-names', 'playwright');
    args.push('--approval-mode', 'plan');
  } else {
    // Even without web tools, use a safe approval mode
    args.push('--approval-mode', 'plan');
  }

  // JSON output
  args.push('-o', 'json');

  return { command: 'gemini', args };
}

/**
 * Parse Gemini JSON output
 */
export function parseGeminiOutput(stdout: string): ProviderOutput {
  try {
    const parsed = JSON.parse(stdout);

    // Gemini's JSON envelope may vary; look for common response patterns
    const resultText = parsed.result || parsed.message || parsed.content || '';

    if (!resultText) {
      throw new Error('No message content found in Gemini response');
    }

    return {
      resultText,
      newSessionId: parsed.session_id || parsed.sessionId || null
    };
  } catch (error) {
    throw new Error(`Failed to parse Gemini output: ${error instanceof Error ? error.message : String(error)}`);
  }
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
    case 'gemini':
      return buildGeminiInvocation(options);
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
    case 'gemini':
      return parseGeminiOutput(stdout);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}

/**
 * Ensure MCP servers are registered (only for codex/gemini; Claude uses per-invocation config)
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
  // Lazily register MCP for codex and gemini at startup
  // This ensures they're available when sessions are created
  Promise.all([ensureMcpRegistered('codex'), ensureMcpRegistered('gemini')]).catch((err) => {
    console.warn('MCP initialization errors (non-fatal):', err);
  });
}
