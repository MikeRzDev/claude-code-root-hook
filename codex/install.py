#!/usr/bin/env python3
"""Install/remove Codex helpers and merge their SessionStart hook."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import tempfile

FILES = ("askpass.sh", "codex-sudo", "context.py")


def write_config(path, config):
    fd, temporary = tempfile.mkstemp(prefix=".root-hook-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(config, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure(home, uninstall=False):
    home = home.expanduser().resolve()
    destination = home / "root-hook"
    settings = home / "hooks.json"
    command = "python3 " + shlex.quote(str(destination / "context.py"))
    config = json.loads(settings.read_text()) if settings.exists() else {}
    # Validate before copying or changing any files.
    if not isinstance(config, dict) or not isinstance(config.get("hooks", {}), dict):
        raise ValueError("hooks.json must contain an object with a hooks object")
    hooks = config.get("hooks", {})
    groups = hooks.get("SessionStart", [])
    if not isinstance(groups, list):
        raise ValueError("SessionStart must be an array")
    cleaned = []
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks", []), list):
            raise ValueError("SessionStart groups must have a hooks array")
        handlers = group.get("hooks", [])
        kept = [h for h in handlers if not (
            isinstance(h, dict) and h.get("type") == "command"
            and h.get("command") == command
        )]
        if len(kept) == len(handlers):
            cleaned.append(group)
        elif kept:
            cleaned.append({**group, "hooks": kept})
    if not uninstall:
        cleaned.append({"hooks": [{"type": "command", "command": command,
                                   "timeout": 10}]})
    if cleaned:
        hooks["SessionStart"] = cleaned
    else:
        hooks.pop("SessionStart", None)
    if hooks or "hooks" in config:
        config["hooks"] = hooks

    if uninstall and not settings.exists() and not destination.exists():
        return
    home.mkdir(parents=True, exist_ok=True)
    if settings.exists():
        backup = settings.with_name("hooks.json.before-root-hook")
        if not backup.exists():
            shutil.copy2(settings, backup)
    if not uninstall:
        destination.mkdir(mode=0o700, exist_ok=True)
        source = Path(__file__).resolve().parent
        for name in FILES:
            target = destination / name
            if target.is_symlink():
                raise ValueError(f"Refusing to overwrite symlink: {target}")
            shutil.copyfile(source / name, target)
            target.chmod(0o700)
    write_config(settings, config)
    if uninstall:
        for name in FILES:
            (destination / name).unlink(missing_ok=True)
        if destination.exists() and not any(destination.iterdir()):
            destination.rmdir()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", type=Path,
                        default=Path(os.environ.get("CODEX_HOME", "~/.codex")))
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()
    configure(args.codex_home, args.uninstall)
    print("Removed Codex root hook." if args.uninstall else
          "Installed. Open /hooks in Codex to review and trust the SessionStart "
          "hook, then start a new session. No sudo command has been run.")
