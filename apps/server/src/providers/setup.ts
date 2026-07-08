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
    case 'gemini':
      return 'gemini';
    default:
      throw new Error(`Unknown provider: ${providerId}`);
  }
}

/**
 * Map providerId to npm package name for global install
 */
function getPackageName(providerId: ProviderType): string {
  switch (providerId) {
    case 'claude':
      return '@anthropic-ai/claude-code';
    case 'codex':
      return '@openai/codex';
    case 'gemini':
      return '@google/gemini-cli';
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

      case 'gemini': {
        // Check for ~/.gemini/oauth_creds.json (strong indicator per prior research)
        const geminiCredsPath = path.join(homeDir, '.gemini', 'oauth_creds.json');
        if (fs.existsSync(geminiCredsPath)) {
          return true;
        }

        return false;
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
 * Install a provider CLI globally via npm
 */
export async function installProvider(providerId: ProviderType): Promise<{
  ok: boolean;
  message: string;
}> {
  try {
    const packageName = getPackageName(providerId);
    const binaryName = getBinaryName(providerId);

    // If already installed, skip
    if (isInstalled(providerId)) {
      return {
        ok: true,
        message: `${binaryName} is already installed.`
      };
    }

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
      case 'gemini':
        // Gemini triggers OAuth automatically on bare invocation
        loginCommand = 'gemini';
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
