# Password caching

Codex and Claude Code use the same cache implementation and JSON settings on
Linux and macOS. After you enter a valid **sudo password** in the desktop dialog,
the helper reuses it for **two hours** by default. This is normally your own
account password, not a separate root password.

The window starts at successful authentication. Repeated commands **do not extend
it**. At expiry, the next privileged command requests your password again. Each
harness has its own credential-store entry; authenticating Codex does not unlock
Claude Code's cache or vice versa. Harness approvals still apply to commands.

## Configuration

Both installers create this file if it is missing and preserve your edits:

```text
~/.config/harness-root-hook/config.json
```

```json
{
  "cache": {
    "enabled": true,
    "ttl_seconds": 7200
  }
}
```

See [config.example.json](config.example.json). The file contains settings only;
never put a password in it. `ttl_seconds` is an integer from 0 to 31536000. Set
`enabled` to `false` or `ttl_seconds` to `0` to disable caching.

The path follows `XDG_CONFIG_HOME` when set. Set `HARNESS_ROOT_HOOK_CONFIG` to an
absolute JSON file path to override it. Set the override both during installation
and in the harness environment so the macOS cleanup task uses the same settings.
Both harnesses on a computer use this shared settings file.

Settings are read on every authentication request. Reducing the duration applies
to an existing entry immediately on its next use. Increasing it takes effect
when you next authenticate; it does not extend a previously issued cache entry.
Disabling caching clears that harness's entry on its next use. Invalid JSON,
unknown settings, and invalid values fail authentication instead of silently
using defaults. No legacy `CLAUDE_SUDO_TTL` override is used; migrate that setting
to the JSON file.

## OS-managed storage

| OS | Credential store | Requirements |
| --- | --- | --- |
| Linux | Desktop Secret Service, accessed through `secret-tool` | `libsecret-tools` and an active Secret Service provider such as GNOME Keyring |
| macOS | macOS Keychain, accessed through `/usr/bin/security` | Logged-in desktop session and an available default keychain |

Passwords are stored in the credential store's **secret value**, never its
search attributes or a plaintext password file. The store manages encryption and
unlocking; configure a password-protected login keyring/keychain. An OS keyring
unlock or permission prompt can still appear if the store is locked. Processes
with access to your unlocked credential store may retrieve its secrets.

Secrets pass to sudo and storage commands through stdin pipes, not command-line
arguments or log files. On macOS, an encoded record is sent over `security -i`'s
stdin; Keychain provides encryption, not the encoding. Runtime lock files are
empty and contain no passwords. Passwords necessarily exist briefly in process
memory while authenticating; this is not a hardware-backed credential scheme.

There is **no plaintext fallback** when the OS credential store is missing or
unavailable. Linux requires a working desktop D-Bus session. Missing dependency,
locked-store failure, or storage failure stops the authentication attempt.

A cached password is validated against sudo before reuse. Wrong or changed
passwords are discarded. New passwords are checked before storing, with at most
three desktop attempts. Cancellation aborts the privileged action. Generated
sudo commands use `-k` so sudo's separate timestamp cache cannot bypass this
integration's configured expiry.

Expired credentials are never reused. Linux removes expired entries on the next
cache request, so an unused expired entry can remain encrypted in the keyring
until it is cleared. macOS additionally installs a per-harness launchd cleanup
task every five minutes; when running successfully, it deletes expired entries
without reading their password values. Sleep and OS scheduling can delay cleanup,
but do not extend the authentication window. Clear entries explicitly when needed.

## Clear cached credentials

These commands delete credentials without printing them:

```sh
# Codex
python3 "${CODEX_HOME:-$HOME/.codex}/root-hook/harness_cache.py" --harness codex clear

# Claude Code
python3 "$HOME/.claude/hooks/harness_cache.py" --harness claude-code clear
```

Uninstalling a harness integration clears its cache and removes its macOS cleanup
task. The shared JSON configuration is retained for the other harness and future
installation. Uninstall while the credential store is available; a failed clear
is reported instead of pretending the credential was removed.

## Upgrading from the original Claude Code cache

Run the new installer for your platform. The Linux installer deletes the old
`claude-sudo.cache` plaintext file. The macOS installer removes the old
`claude-sudo` Keychain item and `com.claude.sudo-reaper` task. New entries use
`harness-root-hook` names, and the default changes from a sliding one-hour window
to a fixed two-hour window. Restart the harness after reinstalling.

## References

- [Secret Service API](https://specifications.freedesktop.org/secret-service/latest-single/)
- [GNOME secret-tool implementation](https://github.com/GNOME/libsecret/blob/main/tool/secret-tool.c)
- [Apple security tool and stdin command parsing](https://github.com/apple-oss-distributions/SecurityTool/blob/main/security.c)
