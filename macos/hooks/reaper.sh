#!/usr/bin/env sh

# Claude Code sudo-cache reaper (macOS, Keychain only).
#
# Guarantees the cached sudo password is deleted after the idle TTL even if
# `sudo` is never invoked again — the Keychain itself has no expiry, and the
# askpass helper can only clean up lazily on the next sudo call. Run by the
# com.claude.sudo-reaper launchd agent (every 5 min), so the secret is gone
# within TTL + ~5 min of the last use.
#
# Reads ONLY the item's comment ("<last-use epoch> <ttl>") via attribute
# lookup, so it never accesses the password and never prompts. No files.
# Safe no-op when nothing is cached.

SERVICE="claude-sudo"
ACCOUNT="$(id -un)"

# Nothing cached -> nothing to do.
security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || exit 0

meta=$(security find-generic-password -s "$SERVICE" -a "$ACCOUNT" 2>/dev/null \
        | sed -n 's/.*"icmt"<blob>="\(.*\)"/\1/p')

case "$meta" in
  *' '*) ts=${meta%% *}; ttl=${meta##* } ;;
  *)     ts=''; ttl='' ;;
esac
case "$ts"  in *[!0-9]*|'') ts='' ;; esac
case "$ttl" in *[!0-9]*|'') ttl='' ;; esac

# Garbled/absent age -> can't vouch for freshness -> scrub.
if [ -z "$ts" ] || [ -z "$ttl" ]; then
  security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
  exit 0
fi

age=$(( $(date +%s) - ts ))
if [ "$ttl" -le 0 ] || [ "$age" -ge "$ttl" ]; then
  security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
fi
exit 0
