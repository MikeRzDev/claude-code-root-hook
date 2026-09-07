#!/usr/bin/env python3
"""Introduce the explicit sudo helper without issuing permission decisions."""
import json
from pathlib import Path
import shlex
import sys


def main():
    event = json.load(sys.stdin)
    if event.get("hook_event_name") != "SessionStart":
        return
    helper = shlex.quote(str(Path(__file__).resolve().with_name("codex-sudo")))
    context = (
        f"For authorized commands requiring sudo, use {helper} followed by the "
        "sudo options and command arguments. It authenticates via a graphical "
        "password prompt. Keep the actual command visible in the tool call. "
        "Follow normal sandbox escalation and approval requirements; this helper "
        "does not grant approval. Never run askpass.sh directly, capture its "
        "output, or ask the user to send a password in chat. If the dialog is "
        "cancelled, stop that privileged action."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart", "additionalContext": context
    }}))


if __name__ == "__main__":
    main()
