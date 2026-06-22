# claude-code-root-hook — macOS

Let **Claude Code** run `sudo` commands on macOS — with a native password
dialog and a time‑limited password cache — even though Claude's shell has no
terminal.

> TL;DR: a PreToolUse hook rewrites `sudo …` → `SUDO_ASKPASS=… sudo -A …` so
> sudo authenticates through an AppleScript dialog (`osascript`) instead of a
> tty, and the password is cached for ~1h so you aren't prompted every time.

This is the macOS port of the Linux/Ubuntu hook in `../linux`. Same idea,
adapted to macOS tools.

---

## The problem this solves

Claude Code executes Bash tool commands in a shell with **no controlling tty**
(`tty` prints `not a tty`). With no tty, `sudo` errors with
`sudo: a terminal is required to authenticate` (or hangs), and a `sudo -v` you
run in *another* Terminal is keyed to that terminal and is invisible to
Claude's tty‑less context.

## How it works

macOS `sudo` supports `-A` / `SUDO_ASKPASS` — a password helper program that
needs no tty. The pieces:

```
┌─ Claude runs:  sudo installer -pkg foo.pkg -target /
│
├─ PreToolUse hook (sudo-check.sh) intercepts the Bash command and rewrites it
│   via Claude Code's `updatedInput` to:
│       export SUDO_ASKPASS=~/.claude/hooks/askpass.sh; sudo -A installer ...
│
├─ sudo -A runs askpass.sh to get the password (no tty needed)
│
└─ askpass.sh:
     • fresh cache?  -> prints cached password silently
     • otherwise     -> pops a native osascript dialog, caches the password
```

Two scripts:

| file | role |
|------|------|
| `hooks/sudo-check.sh` | PreToolUse hook (matcher `Bash`). Rewrites any sudo command to use askpass. |
| `hooks/askpass.sh`    | `SUDO_ASKPASS` helper. Native AppleScript prompt + sliding 1h password cache. |

### What's different from the Linux version

| concern | Linux (`../linux`) | macOS (here) |
|---------|--------------------|--------------|
| password dialog | `zenity` / `kdialog` / `ssh-askpass` (needs `DISPLAY`/`WAYLAND_DISPLAY`) | `osascript` (AppleScript `display dialog`) — built in, needs a logged‑in GUI session |
| cache file dir | `$XDG_RUNTIME_DIR` (tmpfs) | `$TMPDIR` (per‑user private dir) |
| file mtime read | `stat -c %Y` (GNU) | `stat -f %m` (BSD) |
| `jq` install | `apt install jq` | `brew install jq` |

## Requirements

- **macOS** with a logged‑in GUI (Aqua) session — i.e. you're at the desktop,
  not a headless `ssh` shell. `osascript` is built in.
- **`jq`** on `PATH` — `brew install jq`.
- Works with the system `sudo` (supports `-A`).

## Install

```sh
./install.sh
```

This copies the scripts to `~/.claude/hooks/` and adds a PreToolUse hook to
`~/.claude/settings.json` (backing it up to `settings.json.bak`). It is
idempotent. **Restart Claude Code** (or start a new session) so it reloads
`settings.json`.

## Verify

Ask Claude Code to run:

```sh
sudo id
```

Expected: one native password dialog the first time, then `uid=0(root) …`.
Subsequent `sudo` commands run **without** a prompt until the cache goes idle.

Check the cache exists and is private:

```sh
ls -l "${TMPDIR:-/tmp}claude-sudo.cache"   # -rw------- you
```

## Configuration

| Setting | How | Default |
|---------|-----|---------|
| Cache lifetime (idle) | `CLAUDE_SUDO_TTL` env var, in seconds | `3600` (1h) |
| Disable caching (prompt every time) | `CLAUDE_SUDO_TTL=0` | — |
| Clear cache now | `rm -f "${TMPDIR:-/tmp}/claude-sudo.cache"` | — |

The cache window is **sliding**: every sudo use refreshes it, so it only
re‑prompts after `CLAUDE_SUDO_TTL` seconds of *no* sudo activity.

## Security

- The password is cached in **plaintext** in your per‑user `$TMPDIR`
  (`claude-sudo.cache`, mode `0600`). That directory is user‑only.
- Anything able to read your files **as your user** could read it during the
  cache window. If that is unacceptable, set a short `CLAUDE_SUDO_TTL`, use
  `CLAUDE_SUDO_TTL=0`, or clear the cache when done.
- This grants Claude Code the ability to obtain root via your password. That is
  the point — make sure it matches your intent. To revoke, run `./uninstall.sh`.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `sudo: a terminal is required to authenticate` | Hook not applied. Restart Claude Code so `settings.json` reloads; confirm the hook path in settings is correct and `sudo-check.sh` is executable. |
| Command runs unmodified (no rewrite) | `updatedInput` must be nested under `hookSpecificOutput`. Update Claude Code if older versions lack `updatedInput`. |
| No dialog appears / deny message | No logged‑in GUI session (e.g. plain `ssh`), or `osascript` unavailable. Run from a desktop session. |
| Wrong password cached after you changed it | `rm -f "${TMPDIR:-/tmp}/claude-sudo.cache"` and retry. |

## Uninstall

```sh
./uninstall.sh
```

Removes the hook registration from `settings.json`, deletes the installed
scripts, and clears the cached password. Restart Claude Code afterwards.

## Files

```
macos/
├── README.md
├── install.sh          # copy scripts + register hook (idempotent)
├── uninstall.sh        # remove hook + scripts + cache
└── hooks/
    ├── sudo-check.sh    # PreToolUse Bash hook: rewrites sudo -> sudo -A
    └── askpass.sh       # SUDO_ASKPASS helper: native prompt + 1h cache
```
