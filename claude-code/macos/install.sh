#!/usr/bin/env bash
set -euo pipefail

# Installer for the Claude Code root (sudo) hook — macOS.
# Copies the hook scripts into ~/.claude/hooks, registers a PreToolUse Bash
# hook in ~/.claude/settings.json, and installs a launchd reaper that deletes
# the cached Keychain password after the configured fixed TTL. Safe to re-run (idempotent).

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hooks"
DEST_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD='$HOME/.claude/hooks/sudo-check.sh'   # literal; Claude Code expands $HOME

LABEL="com.claude.sudo-reaper"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/$LABEL.plist"
REAPER="$DEST_DIR/reaper.sh"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq)"; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "error: Python 3.9+ is required"; exit 1; }
CACHE_HELPER="$SRC_DIR/../../../harness_cache.py"
python3 "$CACHE_HELPER" --harness claude-code check
python3 "$CACHE_HELPER" --harness claude-code init-config

echo "==> Installing hook scripts to $DEST_DIR"
mkdir -p "$DEST_DIR"
install -m 0755 "$CACHE_HELPER" "$DEST_DIR/harness_cache.py"
install -m 0755 "$SRC_DIR/askpass.sh"    "$DEST_DIR/askpass.sh"
install -m 0755 "$SRC_DIR/sudo-check.sh" "$DEST_DIR/sudo-check.sh"
install -m 0755 "$SRC_DIR/reaper.sh"     "$DEST_DIR/reaper.sh"

echo "==> Registering PreToolUse hook in $SETTINGS"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Back up once, then merge the hook in if not already present.
cp -n "$SETTINGS" "$SETTINGS.bak" 2>/dev/null || true
tmp="$(mktemp)"
jq --arg cmd "$HOOK_CMD" '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  if any(.hooks.PreToolUse[]?; (.hooks // [])[]?.command == $cmd)
  then .
  else .hooks.PreToolUse += [{matcher:"Bash", hooks:[{type:"command", command:$cmd}]}]
  end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# Remove the old sliding-cache reaper and cache during migration.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
security delete-generic-password -s claude-sudo -a "$(id -un)" >/dev/null 2>&1 || true
python3 "$DEST_DIR/harness_cache.py" --harness claude-code install-reaper

echo "==> Done."
echo
echo "Installed:"
echo "  $DEST_DIR/askpass.sh"
echo "  $DEST_DIR/sudo-check.sh"
echo "  $DEST_DIR/reaper.sh"
echo "  hook registered in $SETTINGS (backup: $SETTINGS.bak)"
echo "  fixed-expiry Keychain reaper installed"
echo
echo "Storage: macOS Keychain. Default password cache: two hours from authentication."
echo "Restart Claude Code so it reloads settings.json, then run a 'sudo'"
echo "command — you should get one native macOS password prompt."
