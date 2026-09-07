# Claude Code

Claude Code integration for [harness-root-hook](../README.md), with graphical
sudo authentication and a sliding password cache. For Codex, use the separate
[`codex/` integration](../codex/README.md).

## Choose your operating system

| Platform | Dialog | Cache | Guide |
| --- | --- | --- | --- |
| Linux | zenity, kdialog, or ssh-askpass | User-only tmpfs file | [Linux](linux/README.md) |
| macOS | Native osascript dialog | Login Keychain with launchd expiry task | [macOS](macos/README.md) |

Run the appropriate installer from the repository root:

```sh
# Linux
./claude-code/linux/install.sh

# macOS
./claude-code/macos/install.sh
```

Both require `jq` and a logged-in desktop session. They install into
`~/.claude/hooks/` and register a PreToolUse Bash hook in
`~/.claude/settings.json`. Restart Claude Code after installation.

The hook rewrites sudo commands to authenticate through `SUDO_ASKPASS`.
`CLAUDE_SUDO_TTL` controls the sliding idle cache window (default: 3600 seconds).
Read the platform guide before changing caching settings.

## Existing installations

The source folders moved from `linux/` and `macos/` into this directory when the
repository became `harness-root-hook`. Installed hook paths, settings, and cache
names remain the same, so existing installations do not need migration.
Installer scripts resolve their sources relative to their own location and
can be called from any working directory.

## Uninstall

From the repository root:

```sh
# Linux
./claude-code/linux/uninstall.sh

# macOS
./claude-code/macos/uninstall.sh
```

Restart Claude Code afterward. The corresponding uninstaller removes the
installed hook and cached password; the macOS uninstaller also removes its
launchd task. Codex uses separate installation files and settings.
