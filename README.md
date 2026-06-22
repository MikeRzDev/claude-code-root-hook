# claude-code-root-hook

Let **Claude Code** run `sudo` commands even though its shell has no terminal —
by authenticating `sudo` through a graphical askpass helper and caching the
password for a sliding ~1h window.

Claude Code runs Bash tool commands with **no controlling tty**, so plain
`sudo` fails with `a terminal is required to authenticate`. A PreToolUse hook
rewrites `sudo …` → `SUDO_ASKPASS=… sudo -A …` so sudo prompts via a GUI dialog
(no tty needed), and a tiny cache means you're only asked once in a while.

## Pick your OS

| folder | platform | password dialog |
|--------|----------|-----------------|
| [`linux/`](linux/) | Linux / Ubuntu (incl. `sudo-rs`) | `zenity` / `kdialog` / `ssh-askpass` |
| [`macos/`](macos/) | macOS | native `osascript` (AppleScript) dialog |

Both install to the same place (`~/.claude/hooks/` + a PreToolUse hook in
`~/.claude/settings.json`) — a given machine uses one or the other.

```sh
# Linux
cd linux && ./install.sh

# macOS
cd macos && ./install.sh
```

See the per‑OS README for requirements, verification, configuration, security
notes, and uninstall.

## Security in one line

This grants Claude Code the ability to obtain root via **your** password
(cached in plaintext, user‑only, mode `0600`, for the cache window). That's the
point — make sure it matches your intent. `./uninstall.sh` revokes it.
