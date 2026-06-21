#!/usr/bin/env sh

# Graphical SUDO_ASKPASS helper for Claude Code, with a time-limited cache.
#
# WHY THIS EXISTS
#   Claude Code runs Bash commands with NO controlling tty, so `sudo` cannot
#   prompt for a password the normal way. This helper lets `sudo -A` read the
#   password from a graphical dialog instead. It also caches the password for
#   a sliding idle window so you aren't prompted on every single command
#   (sudo's own credential cache does NOT persist across Claude's separate,
#   tty-less processes, so we cache here).
#
# CACHE
#   Location : $XDG_RUNTIME_DIR/claude-sudo.cache  (falls back to /run/user/<uid>)
#              tmpfs = RAM only, user-owned, wiped on reboot/logout.
#   Mode     : 0600
#   Lifetime : sliding window of CLAUDE_SUDO_TTL seconds of INACTIVITY
#              (default 3600 = 1 hour). Re-prompts only after that idle gap.
#   Clear    : rm -f "$XDG_RUNTIME_DIR/claude-sudo.cache"
#
# SECURITY
#   The password is held in plaintext in the tmpfs cache for the window above.
#   It is user-only and gone on reboot. Lower CLAUDE_SUDO_TTL (or set it to 0
#   to disable caching) if that is not acceptable for your threat model.

TTL="${CLAUDE_SUDO_TTL:-3600}"
RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
CACHE="$RUNDIR/claude-sudo.cache"
TITLE="sudo password (Claude Code)"

serve() { printf '%s\n' "$1"; }

# --- serve from cache if still fresh (and refresh the idle window) ----------
if [ "$TTL" -gt 0 ] && [ -f "$CACHE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt "$TTL" ]; then
    touch "$CACHE" 2>/dev/null
    serve "$(cat "$CACHE")"
    exit 0
  fi
  rm -f "$CACHE"
fi

# --- otherwise prompt graphically (auto-detect an available dialog) ---------
ask_password() {
  if [ -n "$WAYLAND_DISPLAY$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
    zenity --password --title="$TITLE" 2>/dev/null
  elif [ -n "$WAYLAND_DISPLAY$DISPLAY" ] && command -v kdialog >/dev/null 2>&1; then
    kdialog --password "$TITLE" 2>/dev/null
  elif [ -n "$DISPLAY" ] && command -v ssh-askpass >/dev/null 2>&1; then
    ssh-askpass "$TITLE" 2>/dev/null
  else
    return 1
  fi
}

pw=$(ask_password) || exit 1
[ -z "$pw" ] && exit 1

# Cache for next time (unless caching is disabled).
if [ "$TTL" -gt 0 ]; then
  ( umask 077; printf '%s' "$pw" > "$CACHE" )
fi

serve "$pw"
exit 0
