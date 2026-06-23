#!/usr/bin/env bash
set -euo pipefail

# Uninstaller (macOS): removes the PreToolUse hook registration, the installed
# scripts, and the launchd reaper, then clears any cached password from both
# the Keychain and the file cache.

DEST_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD='$HOME/.claude/hooks/sudo-check.sh'

LABEL="com.claude.sudo-reaper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVICE="claude-sudo"
ACCOUNT="$(id -un)"

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

echo "==> Unloading + removing reaper agent"
uid="$(id -u)"
launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "==> Removing scripts"
rm -f "$DEST_DIR/askpass.sh" "$DEST_DIR/sudo-check.sh" "$DEST_DIR/reaper.sh"

echo "==> Clearing cached password (Keychain + file + stamp)"
security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
RUNDIR="${TMPDIR:-/tmp}"; RUNDIR="${RUNDIR%/}"
rm -f "$RUNDIR/claude-sudo.cache" "$RUNDIR/claude-sudo.stamp"

echo "==> Done. Restart Claude Code to reload settings.json."
