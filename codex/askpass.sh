#!/bin/sh
# Invoked only by sudo -A. stdout is the password pipe; never run directly.
set -eu
case "$(uname -s)" in
  Darwin)
    exec osascript -e 'text returned of (display dialog "Enter your password to authenticate sudo for Codex:" with title "sudo password (Codex)" default answer "" with hidden answer with icon caution)'
    ;;
  Linux)
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      echo 'Codex askpass: a logged-in graphical desktop is required.' >&2
      exit 1
    fi
    if command -v zenity >/dev/null 2>&1; then
      exec zenity --password --title='sudo password (Codex)'
    elif command -v kdialog >/dev/null 2>&1; then
      exec kdialog --password 'sudo password (Codex)'
    elif [ -n "${DISPLAY:-}" ] && command -v ssh-askpass >/dev/null 2>&1; then
      exec ssh-askpass 'sudo password (Codex)'
    fi
    echo 'Codex askpass: install zenity, kdialog, or ssh-askpass.' >&2
    exit 1
    ;;
  *) echo 'Codex askpass: supported platforms are Linux and macOS.' >&2; exit 1 ;;
esac
