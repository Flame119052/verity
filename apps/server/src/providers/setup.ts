import { execFile, execSync } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import os from 'os';
import path from 'path';
import type { ProviderType } from './index.js';

const execFileAsync = promisify(execFile);

/**
 * Map providerId to CLI binary name
 */
function getBinaryName(providerId: ProviderType): string {
  switch (providerId) {
    case 'claude':
      return 'claude';
    case 'codex':
      return 'codex';
    case 'antigravity':
      return 'agy';
    default:
      throw new Error(`Unknown provider: ${providerId}`);
  }
}

/**
 * Map providerId to npm package name for global install.
 * Antigravity (`agy`) is NOT an npm package — it ships via its own installer
 * script — so this only covers the two npm-based providers; installProvider()
 * branches separately for antigravity.
 */
function getPackageName(providerId: 'claude' | 'codex'): string {
  switch (providerId) {
    case 'claude':
      return '@anthropic-ai/claude-code';
    case 'codex':
      return '@openai/codex';
    default:
      throw new Error(`Unknown provider: ${providerId}`);
  }
}

/**
 * Check if a provider CLI is installed by testing `which <binary>`
 */
function isInstalled(providerId: ProviderType): boolean {
  try {
    const binaryName = getBinaryName(providerId);
    // Synchronous check: try to find the binary in PATH
    execSync(`which ${binaryName}`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

/**
 * Check if a provider CLI has valid authentication credentials
 * Returns 'true' if credentials exist, 'false' if definitely not authenticated, 'unknown' if indeterminate
 */
function checkAuthenticated(providerId: ProviderType): boolean | 'unknown' {
  const homeDir = os.homedir();

  try {
    switch (providerId) {
      case 'claude': {
        // Check for ~/.claude.json (most reliable indicator)
        const claudeJsonPath = path.join(homeDir, '.claude.json');
        if (fs.existsSync(claudeJsonPath)) {
          return true;
        }

        // Check for ~/.claude/ directory with any auth-related files
        const claudeDirPath = path.join(homeDir, '.claude');
        if (fs.existsSync(claudeDirPath)) {
          // If directory exists but we can't read .claude.json, it might use system keychain
          // This is the case for Claude Code on modern systems
          return 'unknown';
        }

        return false;
      }

      case 'codex': {
        // Check for ~/.codex/auth.json
        const codexAuthPath = path.join(homeDir, '.codex', 'auth.json');
        if (fs.existsSync(codexAuthPath)) {
          return true;
        }

        // Check if ~/.codex directory exists with state
        const codexDirPath = path.join(homeDir, '.codex');
        if (fs.existsSync(codexDirPath)) {
          // If the directory exists, it might have been initialized
          return 'unknown';
        }

        return false;
      }

      case 'antigravity': {
        // No confirmed file-based auth indicator was found for agy (likely
        // stored in the macOS Keychain, similar to Claude's modern auth) —
        // observed live that it still runs against at least one local/open
        // model even when its own logs say "not logged into Antigravity", so
        // treat this as indeterminate rather than guessing true/false.
        return 'unknown';
      }

      default:
        return 'unknown';
    }
  } catch {
    // If we can't determine due to filesystem errors, return unknown
    return 'unknown';
  }
}

/**
 * Check the status of a provider (installed and authenticated)
 */
export async function checkProviderStatus(
  providerId: ProviderType
): Promise<{
  installed: boolean;
  authenticated: boolean | 'unknown';
}> {
  return {
    installed: isInstalled(providerId),
    authenticated: checkAuthenticated(providerId)
  };
}

/**
 * Install a provider CLI. Claude/Codex ship as npm packages; Antigravity
 * (`agy`) ships via its own installer script instead, so it's a separate
 * path. Both paths are only ever invoked from the explicit "Install it"
 * confirmation click in the onboarding UI — never automatically/silently on
 * provider selection — since the Antigravity path runs a network-fetched
 * install script (curl | bash) and that must always be a reviewed, one-click
 * user action, not something the app decides to do on its own.
 */
export async function installProvider(providerId: ProviderType): Promise<{
  ok: boolean;
  message: string;
}> {
  const binaryName = getBinaryName(providerId);

  // If already installed, skip
  if (isInstalled(providerId)) {
    return {
      ok: true,
      message: `${binaryName} is already installed.`
    };
  }

  if (providerId === 'antigravity') {
    try {
      // Google's official installer, fixed URL, no user input involved.
      await execFileAsync('bash', ['-c', 'curl -fsSL https://antigravity.google/cli/install.sh | bash'], {
        timeout: 3 * 60 * 1000
      });
      if (isInstalled(providerId)) {
        return { ok: true, message: `${binaryName} installed successfully. You may need to log in.` };
      }
      return {
        ok: false,
        message: `Antigravity CLI installer ran but ${binaryName} was not found in PATH afterward.`
      };
    } catch (error) {
      if (isInstalled(providerId)) {
        return { ok: true, message: `${binaryName} installed successfully (with warnings).` };
      }
      const message = error instanceof Error ? error.message : String(error);
      return { ok: false, message: `Failed to install Antigravity CLI: ${message}` };
    }
  }

  // Claude/Codex ship as npm packages, which requires Node.js/npm to already
  // be present — unlike Antigravity's self-contained installer script, this
  // genuinely cannot bootstrap itself on a machine with no Node.js at all.
  // Give a clear, actionable message instead of a cryptic ENOENT/"npm not
  // found" failure.
  try {
    execSync('which npm', { stdio: 'pipe' });
  } catch {
    return {
      ok: false,
      message: `Installing ${binaryName} requires Node.js. Install it from https://nodejs.org, then try again.`
    };
  }

  try {
    const packageName = getPackageName(providerId);

    // Install via npm with 2-minute timeout
    const timeoutMs = 2 * 60 * 1000;

    try {
      await execFileAsync('npm', ['install', '-g', packageName], {
        timeout: timeoutMs
      });
    } catch (error) {
      // Check if it was installed despite the error
      if (isInstalled(providerId)) {
        return {
          ok: true,
          message: `${binaryName} installed successfully (with warnings).`
        };
      }

      throw error;
    }

    // Verify installation
    if (isInstalled(providerId)) {
      return {
        ok: true,
        message: `${binaryName} installed successfully. You may need to authenticate.`
      };
    }

    return {
      ok: false,
      message: `Installation of ${packageName} completed but ${binaryName} not found in PATH`
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      ok: false,
      message: `Failed to install provider: ${message}`
    };
  }
}

/**
 * Launch the login flow for a provider by opening Terminal with the login command
 */
export async function launchLoginFlow(providerId: ProviderType): Promise<{
  ok: boolean;
  message: string;
}> {
  try {
    const binaryName = getBinaryName(providerId);

    if (providerId === 'antigravity') {
      // No confirmed CLI-level login subcommand exists for agy — its
      // authentication appears to be established through the Antigravity
      // GUI app itself (shared credential storage), not a terminal OAuth
      // flow like the other two providers. Open the app instead of a
      // terminal script.
      try {
        await execFileAsync('open', ['-a', 'Antigravity'], { timeout: 5000 });
        return {
          ok: true,
          message: 'Opened the Antigravity app — sign in there, then click Continue.'
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return { ok: false, message: `Failed to open Antigravity app: ${message}` };
      }
    }

    // Determine the login command for each provider
    let loginCommand: string;
    switch (providerId) {
      case 'claude':
        // Claude triggers interactive setup/login on bare invocation
        loginCommand = 'claude';
        break;
      case 'codex':
        loginCommand = 'codex login';
        break;
      default:
        return {
          ok: false,
          message: `Unknown provider: ${providerId}`
        };
    }

    // Create a temporary shell script in os.tmpdir()
    const tmpDir = os.tmpdir();
    const scriptPath = path.join(tmpDir, `login-${providerId}-${Date.now()}.sh`);

    const scriptContent = `#!/bin/bash
${loginCommand}
echo "Done. You can close this window."
`;

    // Write script
    fs.writeFileSync(scriptPath, scriptContent);
    fs.chmodSync(scriptPath, 0o755);

    // Open Terminal with the script
    // Using 'open -a Terminal <path>' launches Terminal and executes the script
    await execFileAsync('open', ['-a', 'Terminal', scriptPath], {
      timeout: 5000 // Just need to launch, not wait for login
    });

    return {
      ok: true,
      message: `Login flow opened in Terminal for ${binaryName}. Complete the authentication there, then click Continue.`
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      ok: false,
      message: `Failed to launch login flow: ${message}`
    };
  }
}
