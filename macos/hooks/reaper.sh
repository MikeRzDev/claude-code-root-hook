#!/usr/bin/env sh

# Claude Code sudo-cache reaper (macOS, Keychain backend).
#
# Guarantees the cached sudo password is deleted after the idle TTL even if
# `sudo` is never invoked again. The askpass helper can only clean up lazily on
# the *next* sudo call; the Keychain itself has no expiry. This script is run
# periodically by the com.claude.sudo-reaper launchd agent (every 5 min) so the
# secret is gone within TTL + ~5 min of the last use, with no further activity.
#
# It reads only NON-secret state (the stamp file's mtime and the existence of
# the Keychain item), so it never accesses the password and never prompts.
# Safe no-op when nothing is cached.

SERVICE="claude-sudo"
ACCOUNT="$(id -un)"
TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"
STAMP="$TMP/claude-sudo.stamp"

# Nothing cached -> nothing to do.
security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || exit 0

# No stamp but the item exists -> we can't vouch for its age -> scrub it.
if [ ! -f "$STAMP" ]; then
  security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
  exit 0
fi

# TTL recorded by askpass when the secret was cached (falls back to 1h).
TTL=$(cat "$STAMP" 2>/dev/null)
case "$TTL" in ''|*[!0-9]*) TTL=3600 ;; esac

age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || echo 0) ))
if [ "$TTL" -le 0 ] || [ "$age" -ge "$TTL" ]; then
  security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
  rm -f "$STAMP"
fi
exit 0
