# Claude Code

Claude Code integration for [harness-root-hook](../README.md), with graphical
sudo authentication and a fixed two-hour password cache. For Codex, use the separate
[`codex/` integration](../codex/README.md).

## Choose your operating system

| Platform | Dialog | Cache | Guide |
| --- | --- | --- | --- |
| Linux | zenity, kdialog, or ssh-askpass | Desktop Secret Service | [Linux](linux/README.md) |
| macOS | Native osascript dialog | Login Keychain with launchd expiry task | [macOS](macos/README.md) |

Run the appropriate installer from the repository root:

```sh
# Linux
./claude-code/linux/install.sh

# macOS
./claude-code/macos/install.sh
```

Both require Python 3.9+, `jq`, and a logged-in desktop session. Linux additionally
requires `secret-tool` and an active Secret Service provider. They install into
`~/.claude/hooks/` and register a PreToolUse Bash hook in
`~/.claude/settings.json`. Restart Claude Code after installation.

The hook rewrites sudo commands to authenticate through `SUDO_ASKPASS`.
Both harnesses read `~/.config/harness-root-hook/config.json`. The default
`cache.ttl_seconds` is 7200 (two hours), with a fixed deadline from successful
authentication. See [password caching](../CACHE.md) for configuration and storage.

## Existing installations

The source folders moved from `linux/` and `macos/` into this directory when the
repository became `harness-root-hook`. Installed hook paths and Claude settings remain the same. Reinstall to obtain
the shared cache implementation; the installer removes legacy cached credentials.
See the [cache migration guide](../CACHE.md#upgrading-from-the-original-claude-code-cache).
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
