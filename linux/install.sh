#!/usr/bin/env bash
set -euo pipefail

# Installer for the Claude Code root (sudo) hook.
# Copies the hook scripts into ~/.claude/hooks and registers a PreToolUse
# Bash hook in ~/.claude/settings.json. Safe to re-run (idempotent).

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hooks"
DEST_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD='$HOME/.claude/hooks/sudo-check.sh'   # literal; Claude Code expands $HOME

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (sudo apt install jq)"; exit 1; }

echo "==> Installing hook scripts to $DEST_DIR"
mkdir -p "$DEST_DIR"
install -m 0755 "$SRC_DIR/askpass.sh"    "$DEST_DIR/askpass.sh"
install -m 0755 "$SRC_DIR/sudo-check.sh" "$DEST_DIR/sudo-check.sh"

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

echo "==> Done."
echo
echo "Installed:"
echo "  $DEST_DIR/askpass.sh"
echo "  $DEST_DIR/sudo-check.sh"
echo "  hook registered in $SETTINGS (backup: $SETTINGS.bak)"
echo
echo "Restart Claude Code (or start a new session) so it reloads settings.json,"
echo "then run a 'sudo' command — you should get one graphical password prompt."
