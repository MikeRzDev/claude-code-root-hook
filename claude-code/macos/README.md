# Claude Code — macOS

Part of [harness-root-hook](../../README.md). For the other harness, see
[Codex](../../codex/README.md).

Use a native desktop password dialog for sudo commands executed without a
terminal. A Claude Code PreToolUse hook rewrites sudo commands to use
`sudo -A -k` and `SUDO_ASKPASS`. The shared helper validates the password and
caches it in macOS Keychain for **two hours** by default.

## Requirements and installation

Requires Python 3.9+, `jq`, and a logged-in macOS desktop. `security`, `osascript`,
and `launchctl` are supplied by macOS. Install Python and jq if missing:

```sh
brew install python jq
```

From the repository root:

```sh
./claude-code/macos/install.sh
```

The installer copies the hooks and shared cache module to `~/.claude/hooks/`,
merges the PreToolUse hook into `~/.claude/settings.json`, and creates the shared
JSON cache settings if missing. It registers a launchd cleanup task. Existing
settings are preserved. Restart Claude Code after installation.

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

This file contains **settings only**. Passwords are stored in the Keychain's
secret value, encrypted by Keychain. Secrets pass over stdin, never command-line
arguments or plaintext password files. The keychain may ask to unlock or grant
access; keep your login keychain password-protected.

The two-hour window starts at successful authentication and is never extended
by repeated commands. Both harnesses share the settings but have separate
credential entries. Set `enabled` to `false` or `ttl_seconds` to `0` to disable
caching. See the [shared cache guide](../../CACHE.md) for alternate configuration
paths, store access, clearing entries, and expiry behavior.

## Verify and cleanup

Ask Claude Code to run:

```sh
sudo id -u
```

After applicable harness approval, enter your sudo password in the desktop dialog.
Expect `0`. Repeat within two hours: no additional sudo-password dialog should
appear unless the password changed or the OS credential store needs unlocking.
After expiry, the next command prompts again. Incorrect passwords are never
cached; cancellation aborts the action.

The `com.harness-root-hook.claude-code.reaper` launchd task runs every five minutes.
It checks the Keychain item's non-secret timestamp and TTL metadata and deletes
expired credentials without reading the password. OS scheduling or sleep may
delay deletion, but the helper never reuses expired entries.

```sh
launchctl print "gui/$(id -u)/com.harness-root-hook.claude-code.reaper"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Terminal required | Restart Claude Code and confirm the hook is registered. |
| No password dialog | Run in a logged-in desktop session with `osascript`. |
| Credential-store failure | Ensure your default keychain is available and unlocked. |
| Authentication/cache operation failed | Check JSON syntax, field types, desktop access, and Keychain availability. |
| Expired item remains | Check the launchd task above; reinstall to register it again. |

## Upgrade and uninstall

Reinstall to upgrade. The installer removes the old `claude-sudo` Keychain item
and `com.claude.sudo-reaper` task. Migrate `CLAUDE_SUDO_TTL` to the JSON file;
new entries use a fixed two-hour default rather than a sliding one-hour window.

From the repository root:

```sh
./claude-code/macos/uninstall.sh
```

This removes the hook, helper files, this harness's credential, and its cleanup
task. Restart Claude Code afterward. Shared JSON settings and Codex's cache remain.
