#!/bin/bash
set -u

APP_NAME="VERITY"
PORT="4477"
HOME_DIR="$HOME"
APP_SUPPORT_DIR="$HOME_DIR/Library/Application Support/VERITY"
CONFIG_PATH="$APP_SUPPORT_DIR/config.json"
RESUME_HINT_PATH="$APP_SUPPORT_DIR/resume-vault.json"
USER_DATA_DIR="$HOME_DIR/Library/Application Support/verity-desktop"

choose_mode() {
  /usr/bin/osascript <<'APPLESCRIPT'
set userChoice to button returned of (display dialog "How do you want to uninstall VERITY?" buttons {"Cancel", "Delete Everything", "Keep Study Data"} default button "Keep Study Data" cancel button "Cancel" with icon caution)
return userChoice
APPLESCRIPT
}

confirm_delete_everything() {
  local vault_path="$1"
  local detail="This permanently deletes VERITY's app files and app settings."
  if [ -n "$vault_path" ]; then
    detail="$detail\n\nIt will also delete this study vault:\n$vault_path"
  fi

  /usr/bin/osascript - "$detail" <<'APPLESCRIPT'
on run argv
set detail to item 1 of argv
set userChoice to button returned of (display dialog detail & return & return & "This cannot be undone." buttons {"Cancel", "Delete Everything"} default button "Cancel" cancel button "Cancel" with icon stop)
return userChoice
end run
APPLESCRIPT
}

notify_done() {
  local message="$1"
  /usr/bin/osascript - "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
set message to item 1 of argv
display dialog message buttons {"OK"} default button "OK" with icon note
end run
APPLESCRIPT
}

read_vault_path() {
  if [ ! -f "$CONFIG_PATH" ]; then
    return 0
  fi
  /usr/bin/perl -0ne 'if (/"vaultPath"\s*:\s*"((?:\\.|[^"])*)"/) { $v=$1; $v =~ s#\\/#/#g; $v =~ s#\\"#"#g; $v =~ s#\\\\#\\#g; print $v; }' "$CONFIG_PATH" 2>/dev/null || true
}

json_escape() {
  /usr/bin/perl -0777 -pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

write_resume_hint() {
  local vault_path="$1"
  if [ -z "$vault_path" ]; then
    return 0
  fi
  /bin/mkdir -p "$APP_SUPPORT_DIR"
  local escaped_vault
  escaped_vault="$(printf '%s' "$vault_path" | json_escape)"
  /bin/cat > "$RESUME_HINT_PATH" <<JSON
{
  "vaultPath": "$escaped_vault",
  "savedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON
}

remove_path() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    /bin/rm -rf "$target" 2>/dev/null || true
  fi
}

remove_app_bundle() {
  local target="$1"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  /bin/rm -rf "$target" 2>/dev/null && return 0

  local quoted_target
  quoted_target="$(printf '%q' "$target")"
  /usr/bin/osascript -e "do shell script \"rm -rf $quoted_target\" with administrator privileges" >/dev/null 2>&1 || true
}

kill_verity_processes() {
  /usr/bin/pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  /bin/sleep 0.8

  local port_pids
  port_pids="$(/usr/sbin/lsof -nP -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "$port_pids" ]; then
    /bin/kill -TERM $port_pids >/dev/null 2>&1 || true
    /bin/sleep 0.4
    /bin/kill -KILL $port_pids >/dev/null 2>&1 || true
  fi
}

remove_login_and_launch_agents() {
  local uid
  uid="$(/usr/bin/id -u)"
  local plist
  for plist in \
    "$HOME_DIR/Library/LaunchAgents/com.krish.study-command-center.plist" \
    "$HOME_DIR/Library/LaunchAgents/com.krish.verity.plist"
  do
    if [ -f "$plist" ]; then
      /bin/launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || true
      /bin/rm -f "$plist" >/dev/null 2>&1 || true
    fi
  done
}

remove_app_state() {
  remove_path "$APP_SUPPORT_DIR"
  remove_path "$USER_DATA_DIR"
  remove_path "$HOME_DIR/Library/Caches/verity-desktop"
  remove_path "$HOME_DIR/Library/Caches/verity-desktop-updater"
  remove_path "$HOME_DIR/Library/Logs/verity-desktop"
  remove_path "$HOME_DIR/Library/Saved Application State/com.krish.verity.savedState"
  remove_path "$HOME_DIR/Library/Saved Application State/com.electron.verity.savedState"
  remove_path "$HOME_DIR/Library/Preferences/com.krish.verity.plist"
  remove_path "$HOME_DIR/Library/Preferences/com.electron.verity.plist"
}

remove_app_bundles() {
  remove_app_bundle "/Applications/VERITY.app"
  remove_app_bundle "$HOME_DIR/Applications/VERITY.app"
}

main() {
  local mode
  mode="$(choose_mode)" || exit 0

  local vault_path
  vault_path="$(read_vault_path)"

  if [ "$mode" = "Delete Everything" ]; then
    local confirmed
    confirmed="$(confirm_delete_everything "$vault_path")" || exit 0
    if [ "$confirmed" != "Delete Everything" ]; then
      exit 0
    fi
  fi

  kill_verity_processes
  remove_login_and_launch_agents

  if [ "$mode" = "Delete Everything" ] && [ -n "$vault_path" ]; then
    remove_path "$vault_path"
  fi

  remove_app_state
  if [ "$mode" = "Keep Study Data" ]; then
    write_resume_hint "$vault_path"
  fi
  remove_app_bundles

  if [ "$mode" = "Keep Study Data" ]; then
    notify_done "VERITY was removed from this Mac. Your study vault was kept. Reinstalling VERITY will open onboarding and offer to resume from the saved vault when available."
  else
    notify_done "VERITY, its app settings, and the configured study vault were removed from this Mac."
  fi
}

main "$@"
