# harness-root-hook

Graphical sudo authentication for **Codex** and **Claude Code** on Linux and macOS.
Run administrative commands from a harness shell without a controlling terminal,
using a desktop password dialog through `sudo -A` and `SUDO_ASKPASS`.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms: Linux and macOS](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)
![Harnesses: Codex and Claude Code](https://img.shields.io/badge/harness-Codex%20%7C%20Claude%20Code-green)
[![GitHub stars](https://img.shields.io/github/stars/MikeRzDev/harness-root-hook?style=social)](https://github.com/MikeRzDev/harness-root-hook/stargazers)

## Choose your harness

| Harness | Integration | Password storage | Setup |
| --- | --- | --- | --- |
| **Codex** | SessionStart hook introduces the explicit `codex-sudo` helper | No password cache maintained by this integration; sudo controls authentication timestamps | [Codex guide](codex/README.md) |
| **Claude Code** | PreToolUse hook rewrites sudo commands to use askpass | Sliding idle cache, default one hour: Linux tmpfs file or macOS login Keychain | [Claude Code guide](claude-code/README.md) |

Both support Linux desktop dialogs (`zenity`, `kdialog`, or `ssh-askpass`) and
native macOS dialogs (`osascript`). A logged-in graphical desktop is required.
You can install both harness integrations on the same computer.

## Quick start

```sh
git clone https://github.com/MikeRzDev/harness-root-hook.git
cd harness-root-hook
```

Choose the command for your harness and operating system. Run installation from
your terminal as your normal user.

### Codex — Linux or macOS

Requires Python 3.9+, `/usr/bin/sudo`, and a supported desktop dialog.

```sh
python3 codex/install.py
```

Open `/hooks` in Codex, review and trust the SessionStart hook, then start a new
session. The hook tells Codex to use the installed `codex-sudo` helper for
administrative commands. Normal Codex approval and sandbox rules still apply.
For versions without SessionStart hooks, use the helper explicitly as described
in the [Codex guide](codex/README.md).

### Claude Code — Linux

Requires `jq` and a supported desktop dialog.

```sh
./claude-code/linux/install.sh
```

### Claude Code — macOS

Requires `jq`; the installer also registers a launchd task to expire cached
Keychain credentials.

```sh
./claude-code/macos/install.sh
```

Restart Claude Code after installation. See the [Linux guide](claude-code/linux/README.md)
or [macOS guide](claude-code/macos/README.md) for verification and configuration.

## Repository layout

```text
harness-root-hook/
├── codex/                 # Cross-platform helper, SessionStart hook, tests
└── claude-code/
    ├── linux/             # Claude Code Linux hooks and installer
    └── macos/             # Claude Code macOS hooks, installer, Keychain reaper
```

Codex installs into `${CODEX_HOME:-~/.codex}/root-hook/` and registers its hook in
`hooks.json` in that Codex home. Claude Code installs into `~/.claude/hooks/` and
registers its hook in `~/.claude/settings.json`. Their configuration and helpers
are independent.

This repository was previously named `claude-code-root-hook`. Existing Claude
Code installations keep working: installed paths have not changed. In a source
checkout, the former `linux/` and `macos/` directories are now under `claude-code/`.

## Authentication and password handling

Enter your password only in the desktop dialog. Never run an askpass script
directly or capture its output: stdout is reserved for sudo's password pipe.
These integrations provide authentication and do not replace harness approvals.

The Codex integration does not persist passwords. Claude Code's Linux helper
stores a password in a user-only `0600` tmpfs file; the macOS helper uses the login
Keychain and a periodic expiry task. See the platform guides for cache behavior,
`CLAUDE_SUDO_TTL`, and security details.

## Uninstall

Run the command for the integration you installed:

```sh
# Codex (both operating systems)
python3 codex/install.py --uninstall

# Claude Code on Linux
./claude-code/linux/uninstall.sh

# Claude Code on macOS
./claude-code/macos/uninstall.sh
```

Restart the relevant harness afterward.

## Validation

```sh
python3 -m unittest discover -s codex/tests -v
```

Codex tests use temporary directories and mocked desktop dialogs. They do not
request real passwords or execute root commands. Real Linux and macOS desktop
authentication requires a manual smoke test; see each harness guide.

## License

[MIT](LICENSE).
