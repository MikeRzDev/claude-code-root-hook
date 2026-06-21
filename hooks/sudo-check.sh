#!/usr/bin/env sh

# Claude Code PreToolUse hook (matcher: Bash).
#
# PROBLEM
#   Claude Code runs Bash with no controlling tty. Modern Ubuntu uses sudo-rs,
#   whose credential tickets are per-tty/per-process, so:
#     * `sudo` can't prompt for a password here, and
#     * a `sudo -v` run in another terminal is never visible to this context.
#   The result is that every `sudo` command fails with
#   "a terminal is required to authenticate" (or hangs).
#
# SOLUTION
#   This hook REWRITES any Bash command that invokes sudo so that each sudo
#   call authenticates through a graphical askpass helper (askpass.sh) which
#   needs no tty. It uses Claude Code's PreToolUse `updatedInput` mechanism to
#   replace the command before it runs:
#
#       sudo <args>   ->   export SUDO_ASKPASS=<helper>; sudo -A <args>
#
#   askpass.sh additionally caches the password so you aren't prompted every
#   time (see that file).
#
# REQUIREMENTS
#   * jq on PATH
#   * a graphical session (DISPLAY or WAYLAND_DISPLAY) + an askpass dialog
#     (zenity / kdialog / ssh-askpass)

# Resolve askpass.sh sitting next to this script (location-independent).
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ASKPASS="$HOOK_DIR/askpass.sh"

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Act only on commands that actually invoke sudo (standalone word).
if ! printf '%s' "$COMMAND" | grep -qw 'sudo'; then
  exit 0
fi

# Already wired for askpass -> leave untouched (avoids double-rewriting).
if printf '%s' "$COMMAND" | grep -q 'SUDO_ASKPASS'; then
  exit 0
fi

# Without a graphical session / helper there is no way to authenticate here.
if [ ! -x "$ASKPASS" ] || { [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; }; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"sudo needs a password but no graphical askpass/display is available in this context."}}'
  exit 0
fi

# Insert -A after each sudo invocation at a command-segment start
# (start of line, or after ; & | ( ), so prose/paths are left alone) and
# export the askpass helper.
NEWCMD=$(printf '%s' "$COMMAND" | sed -E 's/(^|[;&|(])([[:space:]]*)sudo([[:space:]]+)/\1\2sudo -A\3/g')
NEWCMD="export SUDO_ASKPASS='$ASKPASS'; $NEWCMD"

# Hand the rewritten command back to Claude Code via updatedInput.
jq -cn --arg cmd "$NEWCMD" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$cmd}}}'
exit 0
