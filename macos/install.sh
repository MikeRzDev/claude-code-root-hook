#!/usr/bin/env bash
set -euo pipefail

# Installer for the Claude Code root (sudo) hook — macOS.
# Copies the hook scripts into ~/.claude/hooks, registers a PreToolUse Bash
# hook in ~/.claude/settings.json, and installs a launchd reaper that deletes
# the cached Keychain password after the idle TTL. Safe to re-run (idempotent).

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hooks"
DEST_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD='$HOME/.claude/hooks/sudo-check.sh'   # literal; Claude Code expands $HOME

LABEL="com.claude.sudo-reaper"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/$LABEL.plist"
REAPER="$DEST_DIR/reaper.sh"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq)"; exit 1; }

echo "==> Installing hook scripts to $DEST_DIR"
mkdir -p "$DEST_DIR"
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

echo "==> Installing launchd reaper ($LABEL, runs every 5 min)"
mkdir -p "$AGENT_DIR"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$REAPER</string>
  </array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST

# (Re)load the agent. Prefer modern bootstrap/bootout; fall back to load/unload.
uid="$(id -u)"
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || true
fi
launchctl bootstrap "gui/$uid" "$PLIST" 2>/dev/null \
  || { launchctl unload "$PLIST" 2>/dev/null || true; launchctl load "$PLIST"; }

echo "==> Done."
echo
echo "Installed:"
echo "  $DEST_DIR/askpass.sh"
echo "  $DEST_DIR/sudo-check.sh"
echo "  $DEST_DIR/reaper.sh"
echo "  hook registered in $SETTINGS (backup: $SETTINGS.bak)"
echo "  reaper agent $PLIST (loaded)"
echo
echo "Storage: macOS login Keychain only — no password or timestamp ever touches"
echo "disk. Restart Claude Code so it reloads settings.json, then run a 'sudo'"
echo "command — you should get one native macOS password prompt."
