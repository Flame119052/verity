import fs from 'fs';

/**
 * Thin wrapper around fs.readFileSync. Historically this retried with backoff
 * and a `cat` fallback to survive iCloud Drive's transient lock/eviction errors
 * (the vault used to live there). The vault now lives at a genuinely local path
 * (~/Projects/Obsidian Vault, confirmed via `brctl status` as outside iCloud's
 * scope), so those failure modes no longer apply — kept as a named wrapper only
 * so call sites don't need to change if the vault ever moves back under a
 * cloud-synced folder.
 */
export function safeReadFileSync(filePath: string): string {
  return fs.readFileSync(filePath, 'utf-8');
}
