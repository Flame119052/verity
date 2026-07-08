#!/bin/bash
set -e

# Get the repo root directory
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Get vault path from environment or prompt
if [ -z "$VAULT_PATH" ]; then
  echo "VAULT_PATH not set. Enter the path to your Obsidian Vault:"
  read -r VAULT_PATH
fi

if [ ! -d "$VAULT_PATH" ]; then
  echo "Error: Vault path does not exist: $VAULT_PATH"
  exit 1
fi

# Get node binary path
NODE_BIN=$(which node)
if [ -z "$NODE_BIN" ]; then
  echo "Error: node not found in PATH"
  exit 1
fi

# launchd jobs get a minimal default PATH that excludes user-installed CLI
# locations (e.g. ~/.local/bin, where `claude`/`codex`/`gemini` often live) —
# pass through the PATH this installer script itself sees, so the AI assistant
# feature can find those CLIs at runtime.
RUNTIME_PATH="${PATH}"

# Substitute placeholders in template
sed_cmd="s|__VAULT_PATH__|${VAULT_PATH}|g; s|__APP_DIR__|${REPO_ROOT}|g; s|__NODE_BIN__|${NODE_BIN}|g; s|__PATH__|${RUNTIME_PATH}|g"

# Create the plist file in ~/Library/LaunchAgents/
mkdir -p ~/Library/LaunchAgents
sed "$sed_cmd" "$REPO_ROOT/launchd/com.study-command-center.plist.template" > ~/Library/LaunchAgents/com.krish.study-command-center.plist

echo "Installed launchd plist to ~/Library/LaunchAgents/com.krish.study-command-center.plist"
echo "Loading service with launchctl..."

launchctl load ~/Library/LaunchAgents/com.krish.study-command-center.plist

echo "Service installed and loaded successfully!"
echo "Check status with: launchctl list | grep study-command-center"
