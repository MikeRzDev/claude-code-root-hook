#!/usr/bin/env sh

# Claude Code PreToolUse hook (matcher: Bash) — macOS.
#
# PROBLEM
#   Claude Code runs Bash with no controlling tty. Without one `sudo` cannot
#   prompt for a password and fails with
#   "sudo: a terminal is required to authenticate" (or hangs). A `sudo -v` run
#   in another terminal is keyed to that terminal and is invisible here.
#
# SOLUTION
#   This hook REWRITES any Bash command that invokes sudo so that each sudo
#   call authenticates through a native askpass helper (askpass.sh, which pops
#   an AppleScript dialog) that needs no tty. It uses Claude Code's PreToolUse
#   `updatedInput` mechanism to replace the command before it runs:
#
#       sudo <args>   ->   export SUDO_ASKPASS=<helper>; sudo -A <args>
#
#   askpass.sh additionally caches the password so you aren't prompted every
#   time (see that file).
#
# REQUIREMENTS
#   * jq on PATH (brew install jq)
#   * a logged-in macOS GUI session so osascript can display a dialog

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

# Without the helper or a GUI session there is no way to authenticate here.
if [ ! -x "$ASKPASS" ] || ! command -v osascript >/dev/null 2>&1; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"sudo needs a password but no macOS GUI askpass (osascript) is available in this context."}}'
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
