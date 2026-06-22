# claude-code-root-hook

Let **Claude Code** run `sudo` commands on Linux — with a graphical password
prompt and a time‑limited password cache — even though Claude's shell has no
terminal.

> TL;DR: a PreToolUse hook rewrites `sudo …` → `SUDO_ASKPASS=… sudo -A …` so
> sudo authenticates through a GUI dialog (zenity/kdialog/ssh-askpass) instead
> of a tty, and the password is cached for ~1h so you aren't prompted every
> time.

---

## The problem this solves

Claude Code executes Bash tool commands in a shell with **no controlling tty**
(`tty` prints `not a tty`). That breaks `sudo` in two ways:

1. **sudo can't ask for a password.** With no tty, `sudo` errors with
   `sudo: a terminal is required to authenticate` (or hangs).
2. **Caching credentials elsewhere doesn't help.** Modern Ubuntu (25.04+)
   ships **`sudo-rs`** (a Rust reimplementation) as the default `sudo`. Its
   credential "tickets" are keyed per‑tty/per‑process, and:
   - it has **no `timestamp_type=global`** option (verified in `sudoers-rs(5)`),
     so you cannot make tickets span sessions;
   - a `sudo -v` you run in *another terminal* is keyed to *that* terminal and
     is invisible to Claude's tty‑less context;
   - even a ticket cached by the hook process is **not shared** with the
     command's process (both are separate, tty‑less children) — verified
     empirically.

A common "fix" is a hook that blocks sudo and tells you to run `sudo -v` in
another terminal. On `sudo-rs` that **can never succeed** — the cached ticket
is never visible to Claude. This package fixes the root cause instead.

## How it works

`sudo-rs` *does* support `-A` / `SUDO_ASKPASS` (a password helper program that
needs no tty). The pieces:

```
┌─ Claude runs:  sudo update-grub
│
├─ PreToolUse hook (sudo-check.sh) intercepts the Bash command and rewrites it
│   via Claude Code's `updatedInput` to:
│       export SUDO_ASKPASS=~/.claude/hooks/askpass.sh; sudo -A update-grub
│
├─ sudo -A runs askpass.sh to get the password (no tty needed)
│
└─ askpass.sh:
     • fresh cache?  -> prints cached password silently
     • otherwise     -> pops a zenity/kdialog dialog, caches the password
```

Two scripts:

| file | role |
|------|------|
| `hooks/sudo-check.sh` | PreToolUse hook (matcher `Bash`). Rewrites any sudo command to use askpass. |
| `hooks/askpass.sh`    | `SUDO_ASKPASS` helper. Graphical prompt + sliding 1h password cache. |

### Key mechanism: `updatedInput`

A Claude Code PreToolUse hook can **rewrite** the tool input by printing this
to stdout (exit 0):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": { "command": "export SUDO_ASKPASS=...; sudo -A update-grub" }
  }
}
```

`updatedInput` replaces only the fields you include. (Top‑level `updatedInput`
is **not** honored — it must be nested under `hookSpecificOutput`.)

## Requirements

- **OS:** Linux with a graphical session (`DISPLAY` or `WAYLAND_DISPLAY` set).
- **`jq`** on `PATH` — `sudo apt install jq`.
- **An askpass dialog** — one of `zenity` (GNOME), `kdialog` (KDE), or
  `ssh-askpass`. zenity is used in the original setup.
- Works with both **`sudo-rs`** and classic `sudo` (both support `-A`).

## Install

```sh
./install.sh
```

This copies the scripts to `~/.claude/hooks/` and adds a PreToolUse hook to
`~/.claude/settings.json` (backing it up to `settings.json.bak`). It is
idempotent. **Restart Claude Code** (or start a new session) so it reloads
`settings.json`.

### Manual install (from scratch)

1. Copy `hooks/askpass.sh` and `hooks/sudo-check.sh` to `~/.claude/hooks/` and
   `chmod +x` both.
2. Merge this into `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "$HOME/.claude/hooks/sudo-check.sh" }
           ]
         }
       ]
     }
   }
   ```
3. Restart Claude Code.

## Verify

Ask Claude Code to run:

```sh
sudo id
```

Expected: one graphical password prompt the first time, then
`uid=0(root) …`. Subsequent `sudo` commands run **without** a prompt until the
cache goes idle.

Check the cache exists and is private:

```sh
ls -l "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-sudo.cache"   # -rw------- you
```

## Configuration

| Setting | How | Default |
|---------|-----|---------|
| Cache lifetime (idle) | `CLAUDE_SUDO_TTL` env var, in seconds | `3600` (1h) |
| Disable caching (prompt every time) | `CLAUDE_SUDO_TTL=0` | — |
| Clear cache now | `rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-sudo.cache"` | — |

The cache window is **sliding**: every sudo use refreshes it, so it only
re‑prompts after `CLAUDE_SUDO_TTL` seconds of *no* sudo activity.

## Security

- The password is cached in **plaintext** in tmpfs
  (`$XDG_RUNTIME_DIR/claude-sudo.cache`, mode `0600`). tmpfs is RAM‑backed,
  user‑only, and wiped on reboot/logout.
- Anything able to read your processes/files **as your user** could read it
  during the cache window. If that is unacceptable, set a short
  `CLAUDE_SUDO_TTL`, use `CLAUDE_SUDO_TTL=0`, or clear the cache when done.
- This grants Claude Code the ability to obtain root via your password. That is
  the point — make sure it matches your intent. To revoke, run `./uninstall.sh`.
- This approach keeps password protection (no `NOPASSWD` sudoers changes
  required). A `NOPASSWD` rule is an alternative but removes the password gate
  entirely.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `sudo: a terminal is required to authenticate` | Hook not applied. Restart Claude Code so `settings.json` reloads; confirm the hook path in settings is correct and `sudo-check.sh` is executable. |
| Command runs unmodified (no rewrite) | `updatedInput` must be nested under `hookSpecificOutput` (see above). Older Claude Code may lack `updatedInput` support — update Claude Code. |
| No dialog appears / `no graphical askpass/display` deny message | No `DISPLAY`/`WAYLAND_DISPLAY`, or no zenity/kdialog/ssh-askpass installed. Install one (`sudo apt install zenity`). |
| Wrong password cached after you changed it | `rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-sudo.cache"` and retry. |
| Hook seems to block its own diagnostics | The hook only acts on commands containing the word `sudo`; that's expected. |

## How it gets invoked (matcher note)

The hook matches the **Bash** tool. It inspects `.tool_input.command`; if the
command contains the standalone word `sudo` (and isn't already wired for
askpass), it rewrites it. All other commands pass through untouched (exit 0,
no output).

## Uninstall

```sh
./uninstall.sh
```

Removes the hook registration from `settings.json`, deletes the installed
scripts, and clears the cached password. Restart Claude Code afterwards.

## Files

```
claude-code-root-hook/
├── README.md
├── install.sh          # copy scripts + register hook (idempotent)
├── uninstall.sh        # remove hook + scripts + cache
└── hooks/
    ├── sudo-check.sh    # PreToolUse Bash hook: rewrites sudo -> sudo -A
    └── askpass.sh       # SUDO_ASKPASS helper: GUI prompt + 1h cache
```
