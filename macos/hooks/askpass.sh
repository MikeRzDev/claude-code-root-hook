#!/usr/bin/env sh

# Graphical SUDO_ASKPASS helper for Claude Code on macOS, with a time-limited cache.
#
# WHY THIS EXISTS
#   Claude Code runs Bash commands with NO controlling tty, so `sudo` cannot
#   prompt for a password the normal way. This helper lets `sudo -A` read the
#   password from a native macOS dialog (AppleScript via osascript) instead.
#   It also caches the password for a sliding idle window so you aren't
#   prompted on every single command (sudo's own credential cache does NOT
#   persist across Claude's separate, tty-less processes, so we cache here).
#
# CACHE
#   Location : $TMPDIR/claude-sudo.cache  (per-user, private dir; falls back to /tmp)
#   Mode     : 0600
#   Lifetime : sliding window of CLAUDE_SUDO_TTL seconds of INACTIVITY
#              (default 3600 = 1 hour). Re-prompts only after that idle gap.
#   Clear    : rm -f "${TMPDIR:-/tmp}/claude-sudo.cache"
#
# SECURITY
#   The password is held in plaintext in the cache file (mode 0600) inside your
#   private per-user $TMPDIR for the window above. Lower CLAUDE_SUDO_TTL (or set
#   it to 0 to disable caching) if that is not acceptable for your threat model.

TTL="${CLAUDE_SUDO_TTL:-3600}"
RUNDIR="${TMPDIR:-/tmp}"
RUNDIR="${RUNDIR%/}"
CACHE="$RUNDIR/claude-sudo.cache"

serve() { printf '%s\n' "$1"; }

# --- serve from cache if still fresh (and refresh the idle window) ----------
if [ "$TTL" -gt 0 ] && [ -f "$CACHE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt "$TTL" ]; then
    touch "$CACHE" 2>/dev/null
    serve "$(cat "$CACHE")"
    exit 0
  fi
  rm -f "$CACHE"
fi

# --- otherwise prompt with a native dialog (AppleScript) --------------------
# osascript needs a logged-in Aqua (GUI) session; it has no tty dependency.
# A user "Cancel" raises AppleScript error -128 -> non-zero exit -> we abort.
ask_password() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript <<'OSA' 2>/dev/null
set dlg to display dialog "Enter your macOS password so Claude Code can run sudo:" with title "sudo password (Claude Code)" default answer "" with hidden answer with icon caution
return text returned of dlg
OSA
}

pw=$(ask_password) || exit 1
[ -z "$pw" ] && exit 1

# Cache for next time (unless caching is disabled).
if [ "$TTL" -gt 0 ]; then
  ( umask 077; printf '%s' "$pw" > "$CACHE" )
fi

serve "$pw"
exit 0
