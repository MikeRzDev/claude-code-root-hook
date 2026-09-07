# Codex — Linux and macOS

Part of [harness-root-hook](../README.md). See [Claude Code support](../claude-code/README.md) for the other harness.

Authenticate terminal-less sudo commands through a desktop password dialog.
Install alongside either existing Claude Code integration; those files and
hook registrations are independent, with a shared JSON cache configuration.

## Install

Requires Python 3.9+, `/usr/bin/sudo`, and a local desktop session. Linux also
requires `secret-tool` (`sudo apt install libsecret-tools` on Ubuntu) and an active
Secret Service provider such as GNOME Keyring. On Linux,
install `zenity`, `kdialog`, or `ssh-askpass`; macOS uses `osascript`.

From the repository root, run in your terminal:

```sh
python3 codex/install.py
```

This installs the helpers and shared cache module in `$CODEX_HOME/root-hook` (default
`~/.codex/root-hook`) and merges a SessionStart hook into `hooks.json`, preserving
unrelated hooks. An existing file is backed up once as
`hooks.json.before-root-hook`. Re-running installation does not duplicate hooks.
Use `--codex-home /absolute/path` for another Codex home. The installer also
creates the shared cache JSON settings if missing and registers a Keychain cleanup
task on macOS. See [password caching](../CACHE.md).

In a Codex version supporting SessionStart hooks, open `/hooks`, review and trust
the new hook, then start a new session. The hook tells Codex how to use the helper,
including after compaction. It never executes sudo or prompts for a password
itself. See the [official Codex hook documentation](https://learn.chatgpt.com/docs/hooks).

## Usage

Ask Codex to perform the administrative task. Its command should use:

```sh
"${CODEX_HOME:-$HOME/.codex}/root-hook/codex-sudo" id -u
```

After the normal Codex approval, if required, sudo displays a password dialog.
Enter your password there. The command above should print `0`; it makes no system
changes. Never run `askpass.sh` directly: its stdout is reserved for sudo's
password pipe. Never paste your password into chat.

For versions without hooks, the same helper works explicitly: tell Codex its
absolute path in your prompt or your existing AGENTS.md. Automatic command
rewriting is not provided: the SessionStart hook supplies instructions for the
model, so inspect the resulting command. No shell alias, regex replacement,
permission allow hook, sudoers modification, or sandbox change is installed.

Successful authentication is cached for two hours by default in Linux Secret
Service or macOS Keychain. Both harnesses use the same JSON settings, with separate
credential entries. Repeated commands do not extend the deadline. No password is
written to a plaintext file or passed in command-line arguments. See
[password caching](../CACHE.md) for configuration, storage, and clearing entries.

Cancel aborts authentication. Incorrect passwords are checked before caching and
retried up to three times. Shell argument boundaries are preserved; operators such
as `&&` stay outside the helper.

## Troubleshooting

- **Credential-store error:** install `libsecret-tools` on Linux and ensure your
  desktop Secret Service is available and unlocked. There is no file-cache fallback.
- **No dialog:** use a logged-in desktop and ensure Codex inherits `DISPLAY` or
  `WAYLAND_DISPLAY` on Linux. SSH/headless/cloud sessions need a different
  authentication method.
- **Sandbox or no-new-privileges error:** request normal Codex escalation for the
  exact command. The helper supplies authentication, not permission to escape a
  sandbox.
- **Plain sudo still used:** check `/hooks` and start a new session, or tell Codex
  to use the installed helper explicitly.
- **Managed environment:** administrator policy may disable user hooks.

## Uninstall and tests

```sh
python3 codex/install.py --uninstall
python3 -m unittest discover -s codex/tests -v
```

Uninstallation removes only this hook and its helper files, cached credential,
and macOS cleanup task. It preserves unrelated settings and files, including the
backup and shared JSON cache settings. Tests use temporary directories and mocked
desktop dialogs and credential stores; they never request a real password or run root commands.
Linux and macOS GUI authentication still need a manual smoke test on each platform.
