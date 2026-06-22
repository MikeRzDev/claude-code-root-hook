# claude-code-root-hook

> Run `sudo` from **Claude Code** even though its Bash tool has no terminal.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue)
![Shell: sh / bash](https://img.shields.io/badge/shell-sh%20%2F%20bash-green)
![Claude Code: PreToolUse hook](https://img.shields.io/badge/Claude%20Code-PreToolUse%20hook-8A2BE2)
[![GitHub stars](https://img.shields.io/github/stars/MikeRzDev/claude-code-root-hook?style=social)](https://github.com/MikeRzDev/claude-code-root-hook/stargazers)

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

## Keywords

Claude Code · Anthropic Claude · sudo · `SUDO_ASKPASS` · askpass · PreToolUse
hook · `updatedInput` · no tty / "a terminal is required to authenticate" ·
sudo-rs · zenity / kdialog / ssh-askpass · macOS `osascript` password dialog ·
AI agent · LLM agent · CLI · developer tools · automation · macOS · Linux ·
Ubuntu.
