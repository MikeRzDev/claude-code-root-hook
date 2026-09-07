# Claude Code — Linux

Part of [harness-root-hook](../../README.md). For the other harness, see
[Codex](../../codex/README.md).

Use a desktop password dialog for sudo commands executed without a terminal.
A Claude Code PreToolUse hook rewrites sudo commands to use `sudo -A -k` and
`SUDO_ASKPASS`. The shared helper validates the password and caches it in the
OS Secret Service for **two hours** by default.

## Requirements and installation

- Python 3.9+ and `jq`.
- `sudo` with askpass (`-A`) and stdin (`-S`) support.
- `secret-tool` and an active desktop Secret Service provider, such as GNOME Keyring.
- A logged-in desktop, with `DISPLAY` or `WAYLAND_DISPLAY`, and `zenity`, `kdialog`,
  or `ssh-askpass` for the password dialog. `ssh-askpass` requires X11 `DISPLAY`.

On Ubuntu, the CLI dependency is available in `libsecret-tools`:

```sh
sudo apt install python3 jq libsecret-tools zenity
```

From the repository root:

```sh
./claude-code/linux/install.sh
```

The installer copies the hooks and shared cache module to `~/.claude/hooks/`,
merges the PreToolUse hook into `~/.claude/settings.json`, and creates the shared
JSON cache settings if missing. Existing settings are preserved. Restart Claude
Code after installation.

## Cache configuration and storage

Edit `~/.config/harness-root-hook/config.json`:

```json
{
  "cache": {
    "enabled": true,
    "ttl_seconds": 7200
  }
}
```

This file contains **settings only**. The password lives in the Secret Service
secret value; there is no plaintext file fallback. Use a password-protected
keyring. OS storage encryption and unlocking are managed by your Secret Service
provider. The two-hour window starts at successful authentication and is never
extended by repeated commands. Expired entries are deleted on the next use.

Both harnesses share these settings but have separate credential entries. Set
`enabled` to `false` or `ttl_seconds` to `0` to disable caching. See the
[shared cache guide](../../CACHE.md) for alternate configuration paths, expiry,
credential-store access, and clearing the cache.

## Verify

Ask Claude Code to run:

```sh
sudo id -u
```

After applicable harness approval, enter your sudo password in the desktop dialog.
Expect `0`. Repeat within two hours: no additional sudo-password dialog should
appear unless the password changed or the OS credential store needs unlocking.
After expiry, the next command prompts again. Incorrect passwords are never
cached; cancellation aborts the action.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Terminal required | Restart Claude Code and confirm the hook is registered. |
| No password dialog | Ensure the harness has a desktop environment and an installed dialog tool. |
| Credential-store failure | Install `libsecret-tools`; ensure a Secret Service provider is running in your desktop D-Bus session and the keyring is unlocked. |
| Authentication/cache operation failed | Check JSON syntax, field types, desktop access, and OS credential-store availability. |
| Command not rewritten | Use a normal sudo invocation; the existing shell rewrite does not parse every possible shell expression. |

## Upgrade and uninstall

Reinstall to upgrade. The installer deletes the old `claude-sudo.cache` plaintext
file, and new passwords go only to Secret Service. Migrate `CLAUDE_SUDO_TTL` to the
JSON file; the legacy environment variable is no longer used.

From the repository root:

```sh
./claude-code/linux/uninstall.sh
```

This removes the hook and helper files and clears this harness's credential.
Restart Claude Code afterward. Shared JSON settings and Codex's cache remain.
