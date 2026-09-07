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
| **Codex** | SessionStart hook introduces the explicit `codex-sudo` helper | OS credential store; fixed two-hour cache by default | [Codex guide](codex/README.md) |
| **Claude Code** | PreToolUse hook rewrites sudo commands to use askpass | OS credential store; fixed two-hour cache by default | [Claude Code guide](claude-code/README.md) |

Both support Linux desktop dialogs (`zenity`, `kdialog`, or `ssh-askpass`) and
native macOS dialogs (`osascript`). A logged-in graphical desktop is required.
You can install both harness integrations on the same computer. Both use the
same JSON cache settings and OS-managed secret storage: Linux Secret Service or
macOS Keychain. See [password caching](CACHE.md).

## Quick start

```sh
git clone https://github.com/MikeRzDev/harness-root-hook.git
cd harness-root-hook
```

Choose the command for your harness and operating system. Run installation from
your terminal as your normal user.

### Codex — Linux or macOS

Requires Python 3.9+, `/usr/bin/sudo`, and a supported desktop dialog. Linux also
requires `secret-tool` (`sudo apt install libsecret-tools` on Ubuntu) and an active
Secret Service provider such as GNOME Keyring.

```sh
python3 codex/install.py
```

Open `/hooks` in Codex, review and trust the SessionStart hook, then start a new
session. The hook tells Codex to use the installed `codex-sudo` helper for
administrative commands. Normal Codex approval and sandbox rules still apply.
For versions without SessionStart hooks, use the helper explicitly as described
in the [Codex guide](codex/README.md).

### Claude Code — Linux

Requires Python 3.9+, `jq`, `secret-tool` (`libsecret-tools` on Ubuntu), an active
Secret Service provider, and a supported desktop dialog.

```sh
./claude-code/linux/install.sh
```

### Claude Code — macOS

Requires Python 3.9+ and `jq`; the installer also registers a launchd task to expire cached
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
├── harness_cache.py       # Shared cache logic and OS credential-store adapters
├── config.example.json    # Shared cache settings example
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

Both integrations cache verified credentials for **7200 seconds (two hours)**
from authentication, using Linux Secret Service or macOS Keychain. The deadline
does not slide with use. Settings live in `~/.config/harness-root-hook/config.json`:

```json
{
  "cache": {
    "enabled": true,
    "ttl_seconds": 7200
  }
}
```

No password is stored in this JSON file or in a plaintext cache file. See
[password caching](CACHE.md) for configuration, OS storage requirements, cleanup,
and migration from the original Claude Code cache.

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

Tests cover both harnesses and both OS credential-store adapters, using temporary
directories and mocked desktop dialogs and credential stores. They do not
request real passwords or execute root commands. Real Linux and macOS desktop
authentication requires a manual smoke test; see each harness guide.

## License

[MIT](LICENSE).
