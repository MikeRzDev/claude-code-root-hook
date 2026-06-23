#!/usr/bin/env sh

# Graphical SUDO_ASKPASS helper for Claude Code on macOS. KEYCHAIN ONLY.
#
# Stores NOTHING on disk. The sudo password is cached in the macOS login
# Keychain; the sliding-idle clock (last-use epoch + TTL) lives in the SAME
# Keychain item's comment attribute. A launchd reaper (reaper.sh) deletes the
# item after the idle window even if sudo is never run again.
#
# WHY THIS EXISTS
#   Claude Code runs Bash with NO controlling tty, so `sudo` cannot prompt for
#   a password the normal way. `sudo -A` runs this helper, which pops a native
#   AppleScript dialog (no tty needed) and caches the result so you aren't
#   prompted on every command.
#
# TTL
#   CLAUDE_SUDO_TTL seconds of INACTIVITY (default 3600 = 1h). Sliding: every
#   use refreshes it. CLAUDE_SUDO_TTL=0 disables caching (prompt every time,
#   store nothing).
#
# SECURITY
#   The password is encrypted at rest in your login Keychain. The item is
#   created with -A so the tty-less helper can read it without a second prompt;
#   it is readable by processes running as you. Deleted on idle by the reaper,
#   and by uninstall.sh. No plaintext file is ever written.

TTL="${CLAUDE_SUDO_TTL:-3600}"
SERVICE="claude-sudo"
ACCOUNT="$(id -un)"

serve() { printf '%s\n' "$1"; }
now()   { date +%s; }

# --- Keychain is the only storage (no files) --------------------------------
kc_secret() { security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null; }
kc_meta()   { security find-generic-password -s "$SERVICE" -a "$ACCOUNT" 2>/dev/null \
                | sed -n 's/.*"icmt"<blob>="\(.*\)"/\1/p'; }
# store secret ($1) with comment "<epoch> <ttl>" ($2); -U updates in place.
kc_store()  { security add-generic-password -U -A -s "$SERVICE" -a "$ACCOUNT" -j "$2" -w "$1" 2>/dev/null; }
kc_del()    { security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; }

# --- native password dialog (no tty needed; needs a logged-in GUI session) --
# A user "Cancel" raises AppleScript error -128 -> non-zero exit -> we abort.
prompt_pw() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript <<'OSA' 2>/dev/null
set dlg to display dialog "Enter your macOS password so Claude Code can run sudo:" with title "sudo password (Claude Code)" default answer "" with hidden answer with icon caution
return text returned of dlg
OSA
}

# --- serve from the Keychain if the idle window is still open ----------------
meta=$(kc_meta)                       # "<lastuse-epoch> <ttl>" or empty
case "$meta" in
  *' '*) ts=${meta%% *}; cttl=${meta##* } ;;
  *)     ts=''; cttl='' ;;
esac
case "$ts"   in *[!0-9]*|'') ts=0 ;; esac
case "$cttl" in *[!0-9]*|'') cttl=0 ;; esac

if [ "$cttl" -gt 0 ] && [ "$ts" -gt 0 ] && [ "$(( $(now) - ts ))" -lt "$cttl" ]; then
  pw=$(kc_secret)
  if [ -n "$pw" ]; then
    kc_store "$pw" "$(now) $cttl"     # slide the window (rewrite the timestamp)
    serve "$pw"; exit 0
  fi
fi

# --- stale / missing / unverifiable: scrub, then prompt ---------------------
kc_del
pw=$(prompt_pw) || exit 1
[ -z "$pw" ] && exit 1
[ "$TTL" -gt 0 ] && kc_store "$pw" "$(now) $TTL"
serve "$pw"
exit 0
