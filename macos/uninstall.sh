#!/usr/bin/env bash
set -euo pipefail

# Uninstaller (macOS): removes the PreToolUse hook registration and the
# installed scripts, and clears any cached password.

DEST_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD='$HOME/.claude/hooks/sudo-check.sh'

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  echo "==> Removing hook from $SETTINGS"
  tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    if .hooks.PreToolUse then
      .hooks.PreToolUse |= ( map( .hooks |= map(select(.command != $cmd)) )
                             | map(select((.hooks // []) | length > 0)) )
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

echo "==> Removing scripts"
rm -f "$DEST_DIR/askpass.sh" "$DEST_DIR/sudo-check.sh"

echo "==> Clearing cached password (if any)"
RUNDIR="${TMPDIR:-/tmp}"; RUNDIR="${RUNDIR%/}"
rm -f "$RUNDIR/claude-sudo.cache"

echo "==> Done. Restart Claude Code to reload settings.json."
