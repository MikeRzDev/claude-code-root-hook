#!/usr/bin/env sh

# Graphical SUDO_ASKPASS helper for Claude Code on macOS, with a time-limited
# cache. Two storage backends, chosen via CLAUDE_SUDO_BACKEND:
#
#   keychain (default)
#       The password is stored in the macOS login Keychain (encrypted at rest,
#       not a plaintext file). A small NON-secret "stamp" file tracks last-use
#       so the idle TTL can slide. Because the Keychain has no expiry of its
#       own, a launchd reaper (reaper.sh, installed by install.sh) GUARANTEES
#       the item is deleted after CLAUDE_SUDO_TTL seconds of inactivity even if
#       sudo is never invoked again.
#
#   file
#       The password is stored in a 0600 file under $TMPDIR. No Keychain, no
#       reaper; the stale cache is only wiped lazily on the next sudo call.
#
# WHY THIS EXISTS
#   Claude Code runs Bash with NO controlling tty, so `sudo` cannot prompt for
#   a password the normal way. `sudo -A` runs this helper instead, which pops a
#   native AppleScript dialog (no tty needed) and caches the result so you
#   aren't prompted on every single command.
#
# TTL
#   CLAUDE_SUDO_TTL seconds of INACTIVITY (default 3600 = 1 hour). The window is
#   sliding: every use refreshes it. CLAUDE_SUDO_TTL=0 disables caching (prompt
#   every time, store nothing).
#
# SECURITY
#   keychain: encrypted at rest in your login Keychain; readable by processes
#             running as you (item is created with -A so the tty-less askpass
#             can read it without an extra prompt). Deleted on idle by the
#             reaper, and by uninstall.sh.
#   file:     plaintext, mode 0600, in your private per-user $TMPDIR.

TTL="${CLAUDE_SUDO_TTL:-3600}"
BACKEND="${CLAUDE_SUDO_BACKEND:-keychain}"
SERVICE="claude-sudo"
ACCOUNT="$(id -un)"
TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"
STAMP="$TMP/claude-sudo.stamp"        # non-secret idle clock (mtime) + TTL (content)
CACHE="$TMP/claude-sudo.cache"        # file backend only (0600 secret)

serve() { printf '%s\n' "$1"; }
now()   { date +%s; }
mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

# Idle clock lives in the stamp file: mtime = last use, content = the TTL that
# was in effect when the secret was cached (so the reaper honors the same TTL).
mark()    { ( umask 077; printf '%s' "$TTL" > "$STAMP" ); }
read_ttl() {                          # TTL recorded at cache time, else env TTL
  t=$(cat "$STAMP" 2>/dev/null)
  case "$t" in ''|*[!0-9]*) t="$TTL" ;; esac
  printf '%s' "$t"
}

# --- Keychain helpers -------------------------------------------------------
kc_get() { security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null; }
kc_set() { security add-generic-password -U -A -s "$SERVICE" -a "$ACCOUNT" -w "$1" 2>/dev/null; }
kc_del() { security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; }

# --- native password dialog (no tty needed; needs a logged-in GUI session) --
# A user "Cancel" raises AppleScript error -128 -> non-zero exit -> we abort.
prompt_pw() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript <<'OSA' 2>/dev/null
set dlg to display dialog "Enter your macOS password so Claude Code can run sudo:" with title "sudo password (Claude Code)" default answer "" with hidden answer with icon caution
return text returned of dlg
OSA
}

case "$BACKEND" in
  keychain)
    eff=$(read_ttl)
    # Serve from the Keychain only while the idle window is still open.
    if [ "$eff" -gt 0 ] && [ -f "$STAMP" ] && [ "$(( $(now) - $(mtime "$STAMP") ))" -lt "$eff" ]; then
      pw=$(kc_get)
      if [ -n "$pw" ]; then
        touch "$STAMP" 2>/dev/null     # slide the window
        serve "$pw"; exit 0
      fi
    fi
    # Stale / missing / unverifiable -> scrub any leftover secret, then prompt.
    kc_del; rm -f "$STAMP"
    pw=$(prompt_pw) || exit 1
    [ -z "$pw" ] && exit 1
    if [ "$TTL" -gt 0 ]; then kc_set "$pw"; mark; fi
    serve "$pw"; exit 0
    ;;

  file|*)
    if [ "$TTL" -gt 0 ] && [ -f "$CACHE" ] && [ "$(( $(now) - $(mtime "$CACHE") ))" -lt "$TTL" ]; then
      touch "$CACHE" 2>/dev/null       # slide the window
      serve "$(cat "$CACHE")"; exit 0
    fi
    rm -f "$CACHE"
    pw=$(prompt_pw) || exit 1
    [ -z "$pw" ] && exit 1
    if [ "$TTL" -gt 0 ]; then ( umask 077; printf '%s' "$pw" > "$CACHE" ); fi
    serve "$pw"; exit 0
    ;;
esac
