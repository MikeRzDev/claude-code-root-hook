# claude-code-root-hook — macOS

Let **Claude Code** run `sudo` commands on macOS — with a native password
dialog and a time‑limited password cache — even though Claude's shell has no
terminal.

> TL;DR: a PreToolUse hook rewrites `sudo …` → `SUDO_ASKPASS=… sudo -A …` so
> sudo authenticates through an AppleScript dialog (`osascript`) instead of a
> tty. The password is cached (in the **macOS Keychain** by default) for a
> sliding idle window, and a `launchd` reaper **guarantees** it's deleted after
> the window — even if you never run `sudo` again.

This is the macOS port of the Linux/Ubuntu hook in `../linux`, plus a
Keychain‑backed cache with a real expiry guarantee.

---

## The problem this solves

Claude Code executes Bash tool commands in a shell with **no controlling tty**
(`tty` prints `not a tty`). With no tty, `sudo` errors with
`sudo: a terminal is required to authenticate` (or hangs), and a `sudo -v` you
run in *another* Terminal is keyed to that terminal and is invisible to
Claude's tty‑less context.

## How it works

macOS `sudo` supports `-A` / `SUDO_ASKPASS` — a password helper that needs no
tty. The pieces:

```
┌─ Claude runs:  sudo installer -pkg foo.pkg -target /
│
├─ PreToolUse hook (sudo-check.sh) rewrites the Bash command via Claude Code's
│   `updatedInput` to:
│       export SUDO_ASKPASS=~/.claude/hooks/askpass.sh; sudo -A installer ...
│
├─ sudo -A runs askpass.sh to get the password (no tty needed)
│
└─ askpass.sh:
     • idle window open?  -> returns the cached password silently
     • otherwise          -> pops a native osascript dialog, caches the result
```

Scripts:

| file | role |
|------|------|
| `hooks/sudo-check.sh` | PreToolUse hook (matcher `Bash`). Rewrites any sudo command to use askpass. |
| `hooks/askpass.sh`    | `SUDO_ASKPASS` helper. Native AppleScript prompt + sliding‑idle cache (Keychain or file). |
| `hooks/reaper.sh`     | Deletes the cached Keychain password once idle ≥ TTL. Run by a `launchd` agent. |

## Cache backends

Choose with the `CLAUDE_SUDO_BACKEND` env var:

| backend | where the password lives | wiped when |
|---------|--------------------------|------------|
| **`keychain`** (default) | macOS **login Keychain**, encrypted at rest. The idle clock is a separate **non‑secret** "stamp" file (`$TMPDIR/claude-sudo.stamp`). | by askpass on the next stale `sudo`, **and** by the `launchd` reaper after the idle window (guaranteed) |
| `file` | plaintext file `$TMPDIR/claude-sudo.cache`, mode `0600` | only lazily, by askpass on the next stale `sudo` |

The Keychain item is created with the "allow access" flag so the **tty‑less
askpass can read it without a second prompt**; it's encrypted at rest and never
written to a plaintext file.

## How expiry is *guaranteed* (the reaper)

The cache is a **sliding idle window**: `CLAUDE_SUDO_TTL` seconds (default
`3600` = 1h) of **inactivity**. Every `sudo` use refreshes it, so under
continuous use it persists; it only lapses after a full idle gap.

The subtlety: the Keychain has **no expiry of its own**, and askpass can only
clean up *lazily* on the next `sudo` call. So if Claude authenticates once and
never runs `sudo` again, nothing would ever delete the secret. That's what the
reaper fixes:

- `install.sh` installs a `launchd` agent **`com.claude.sudo-reaper`** that runs
  `reaper.sh` **every 5 minutes** (`StartInterval = 300`).
- `reaper.sh` reads only **non‑secret** state — the stamp file's mtime (= last
  use) and the stamp's recorded TTL — so it never touches the password and
  never prompts. If `now − last_use ≥ TTL`, it deletes the Keychain item and
  the stamp.

**Guarantee:** the password is gone within **`TTL` + ≤ 5 minutes** of your last
`sudo`, with no further activity required. Check the agent:

```sh
launchctl print "gui/$(id -u)/com.claude.sudo-reaper" | grep -E 'state|run interval'
```

(The `file` backend has no such guarantee — only the lazy next‑call wipe, plus
whatever macOS's periodic `$TMPDIR` cleanup does. Prefer `keychain`.)

## Requirements

- **macOS** with a logged‑in GUI (Aqua) session — `osascript` shows the dialog.
- **`jq`** on `PATH` — `brew install jq`.
- `security` and `launchctl` (both built in) for the Keychain backend + reaper.

## Install

```sh
./install.sh
```

Copies the scripts to `~/.claude/hooks/`, adds a PreToolUse hook to
`~/.claude/settings.json` (backed up to `settings.json.bak`), and loads the
reaper agent. Idempotent. **Restart Claude Code** so it reloads `settings.json`.

## Verify

Ask Claude Code to run:

```sh
sudo id
```

Expected: one native password dialog the first time, then `uid=0(root) …`.
Subsequent `sudo` commands run **without** a prompt until the cache goes idle.

Confirm what's cached (Keychain backend — secret is **not** printed):

```sh
security find-generic-password -s claude-sudo -a "$(id -un)"   # attributes only
ls -l "${TMPDIR%/}/claude-sudo.stamp"                          # non-secret idle clock
```

## Configuration

| Setting | How | Default |
|---------|-----|---------|
| Storage backend | `CLAUDE_SUDO_BACKEND=keychain` \| `file` | `keychain` |
| Cache lifetime (idle) | `CLAUDE_SUDO_TTL` env var, in seconds | `3600` (1h) |
| Disable caching (prompt every time) | `CLAUDE_SUDO_TTL=0` | — |
| Clear cache now (Keychain) | `security delete-generic-password -s claude-sudo -a "$(id -un)"` | — |
| Clear cache now (file) | `rm -f "${TMPDIR:-/tmp}/claude-sudo.cache"` | — |
| Reaper interval | edit `StartInterval` in `~/Library/LaunchAgents/com.claude.sudo-reaper.plist`, then reload | `300` (5 min) |

The TTL in effect when the secret was cached is recorded in the stamp file, so
the reaper honors the same value the askpass used.

## Security

- **Keychain backend:** the password is encrypted at rest in your login
  Keychain. Processes running **as you** can read it (the item allows access so
  the headless askpass works) — equivalent exposure to a user‑only file, but
  encrypted and not lying around as plaintext. Deleted on idle by the reaper.
- **File backend:** plaintext, mode `0600`, in your private per‑user `$TMPDIR`;
  wiped only lazily.
- Either way this grants Claude Code the ability to obtain root via **your**
  password during the cache window. That's the point — make sure it matches
  your intent. `./uninstall.sh` revokes everything (hook, scripts, reaper, and
  the cached secret).
- Want it stricter? `CLAUDE_SUDO_TTL=0` (prompt every time) or a short TTL.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `sudo: a terminal is required to authenticate` | Hook not applied. Restart Claude Code; confirm the hook path in settings and that `sudo-check.sh` is executable. |
| Command runs unmodified (no rewrite) | `updatedInput` must be nested under `hookSpecificOutput`. Update Claude Code if older versions lack it. |
| No dialog appears / deny message | No logged‑in GUI session (e.g. plain `ssh`), or `osascript` unavailable. Run from a desktop session. |
| Re‑prompts every command | `CLAUDE_SUDO_TTL=0`, or the reaper interval is shorter than your gaps between commands, or the Keychain item keeps getting denied. Check `security find-generic-password -s claude-sudo`. |
| Cached secret outlived the TTL | Confirm the agent is loaded: `launchctl print gui/$(id -u)/com.claude.sudo-reaper`. Reload with `./install.sh`. |
| Wrong password cached after you changed it | `security delete-generic-password -s claude-sudo -a "$(id -un)"` and retry. |

## Uninstall

```sh
./uninstall.sh
```

Removes the hook registration, the scripts, and the reaper agent, then clears
the cached password from **both** the Keychain and the file cache. Restart
Claude Code afterwards.

## Files

```
macos/
├── README.md
├── install.sh          # copy scripts + register hook + load reaper (idempotent)
├── uninstall.sh        # remove hook + scripts + reaper + cached secret
└── hooks/
    ├── sudo-check.sh    # PreToolUse Bash hook: rewrites sudo -> sudo -A
    ├── askpass.sh       # SUDO_ASKPASS helper: native prompt + Keychain/file cache
    └── reaper.sh        # launchd-run: deletes the Keychain secret after idle TTL
```
