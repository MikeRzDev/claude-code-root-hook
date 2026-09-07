#!/usr/bin/env python3
"""Shared fixed-duration sudo password cache for both harnesses (Python 3.9+)."""
import argparse
import base64
import contextlib
import fcntl
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

DEFAULTS = {"cache": {"enabled": True, "ttl_seconds": 7200}}


def config_path():
    return Path(os.environ.get("HARNESS_ROOT_HOOK_CONFIG") or
                str(Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") /
                    "harness-root-hook/config.json")).expanduser()


def load_config(path=None):
    path = path or config_path()
    data = json.loads(path.read_text()) if path.exists() else DEFAULTS
    if not isinstance(data, dict) or set(data) - {"cache"}:
        raise ValueError("Config must contain only a cache object")
    cache = data.get("cache", {})
    if not isinstance(cache, dict) or set(cache) - {"enabled", "ttl_seconds"}:
        raise ValueError("Unknown cache setting")
    enabled = cache.get("enabled", True)
    ttl = cache.get("ttl_seconds", 7200)
    if type(enabled) is not bool or type(ttl) is not int or not 0 <= ttl <= 31536000:
        raise ValueError("cache.enabled must be boolean; ttl_seconds must be an integer from 0 to 31536000")
    return ttl if enabled else 0


def init_config():
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        load_config(path)  # Never replace customized settings.
    else:
        with os.fdopen(fd, "w") as stream:
            json.dump(DEFAULTS, stream, indent=2)
            stream.write("\n")
    return path


def fresh(record, ttl, now):
    if not isinstance(record, dict) or ttl <= 0:
        return False
    created, original_ttl = record.get("created_at"), record.get("ttl_seconds")
    if type(created) not in (int, float) or not math.isfinite(created):
        return False
    if type(original_ttl) is not int or original_ttl <= 0:
        return False
    return 0 <= now - created < min(ttl, original_ttl)


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("Cache directory must be owned by the current user with mode 0700")
    return path


class LinuxCache:
    """Store secrets only in the desktop Secret Service, never in a file."""
    def __init__(self, harness):
        self.attributes = ["application", "harness-root-hook", "harness", harness,
                           "account", pwd.getpwuid(os.getuid()).pw_name]

    def load(self):
        result = subprocess.run(["secret-tool", "lookup", *self.attributes],
                                capture_output=True, text=True)
        if result.returncode == 1 and not result.stderr.strip():
            return None  # No matching item.
        if result.returncode:
            raise RuntimeError("Could not read Secret Service cache")
        try:
            return json.loads(result.stdout)
        except (ValueError, UnicodeError):
            return None

    def metadata(self):
        return self.load()

    def store(self, record):
        result = subprocess.run(["secret-tool", "store", "--label=Harness sudo password",
                                 *self.attributes], input=json.dumps(record), text=True,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            raise RuntimeError("Could not store the password in Secret Service")

    def clear(self):
        result = subprocess.run(["secret-tool", "clear", *self.attributes],
                                capture_output=True, text=True)
        if result.returncode and (result.returncode != 1 or result.stderr.strip()):
            raise RuntimeError("Could not clear Secret Service cache")


class MacCache:
    """Use security's stdin interface so a secret never appears in process argv."""
    def __init__(self, harness):
        self.service = "harness-root-hook." + harness
        self.account = pwd.getpwuid(os.getuid()).pw_name

    def run(self, action, *args):
        return subprocess.run(["/usr/bin/security", action, "-s", self.service,
                               "-a", self.account, *args], capture_output=True, text=True)

    def metadata(self):
        result = self.run("find-generic-password")
        match = re.search(r'"icmt"<blob>="([0-9.]+) ([0-9]+)"', result.stdout)
        if result.returncode or not match:
            return None
        return {"created_at": float(match[1]), "ttl_seconds": int(match[2])}

    def load(self):
        result = self.run("find-generic-password", "-w")
        if result.returncode:
            return None
        try:
            return json.loads(base64.b64decode(result.stdout.strip(), validate=True))
        except (ValueError, UnicodeError):
            return None

    def store(self, record):
        # Base64 avoids literal newlines and arbitrary password characters in
        # security's line parser. It is encoding, not encryption; Keychain encrypts.
        encoded = base64.b64encode(json.dumps(record).encode()).decode()
        args = ["add-generic-password", "-U", "-T", "/usr/bin/security", "-s", self.service,
                "-a", self.account, "-j", f'{record["created_at"]} {record["ttl_seconds"]}',
                "-w", encoded]
        def quote(value):
            return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
        command = " ".join(quote(arg) for arg in args) + "\n"
        if len(command.encode()) >= 4096:
            raise ValueError("Password record exceeds the Keychain command input limit")
        result = subprocess.run(["/usr/bin/security", "-i"], input=command,
                                text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            raise RuntimeError("Could not store the password in Keychain")

    def clear(self):
        result = self.run("delete-generic-password")
        if result.returncode not in (0, 44):  # errSecItemNotFound
            raise RuntimeError("Could not clear the Keychain cache")


def prompt(harness, retry=False):
    name = "Codex" if harness == "codex" else "Claude Code"
    title = ("Incorrect password — " if retry else "") + f"sudo password ({name})"
    if platform.system() == "Darwin":
        script = ('on run argv\nreturn text returned of (display dialog '
                  '"Enter your sudo password:" with title (item 1 of argv) '
                  'default answer "" with hidden answer with icon caution)\nend run')
        command = ["/usr/bin/osascript", "-e", script, title]
    elif platform.system() == "Linux":
        if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            raise RuntimeError("A logged-in graphical desktop is required")
        if shutil.which("zenity"):
            command = ["zenity", "--password", "--title=" + title]
        elif shutil.which("kdialog"):
            command = ["kdialog", "--password", title]
        elif os.environ.get("DISPLAY") and shutil.which("ssh-askpass"):
            command = ["ssh-askpass", title]
        else:
            raise RuntimeError("Install zenity, kdialog, or ssh-askpass")
    else:
        raise RuntimeError("Only Linux and macOS are supported")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Password dialog cancelled or unavailable")
    password = result.stdout.removesuffix("\n")
    if not password or "\n" in password or "\r" in password or "\0" in password:
        raise RuntimeError("An empty or multiline password cannot be used with sudo")
    return password


def verify(password):
    # -S sends the secret through stdin; -k ignores all sudo timestamps.
    env = dict(os.environ)
    env.pop("SUDO_ASKPASS", None)
    result = subprocess.run(["/usr/bin/sudo", "-S", "-k", "-p", "", "/usr/bin/true"],
                            input=password + "\n", text=True, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, env=env)
    return result.returncode == 0


def authenticate(cache, ttl, ask, check=verify, clock=time.time):
    metadata = cache.metadata()
    if fresh(metadata, ttl, clock()):
        record = cache.load()
        if (fresh(record, ttl, clock()) and isinstance(record.get("password"), str)
                and record["password"] and check(record["password"])):
            return record["password"]  # Never refresh the original deadline.
    cache.clear()
    for attempt in range(3):
        password = ask(attempt > 0)
        if check(password):
            if ttl > 0:
                cache.store({"password": password, "created_at": clock(), "ttl_seconds": ttl})
            return password
    raise RuntimeError("Password authentication failed")


@contextlib.contextmanager
def cache_lock(harness):
    # Lock contains no secret. Serialize concurrent calls so only one prompts.
    root = (Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
            if platform.system() == "Linux" else Path(tempfile.gettempdir()))
    directory = private_dir(root / f"harness-root-hook-locks-{os.getuid()}")
    fd = os.open(directory / harness, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def reaper(harness, remove=False):
    if platform.system() != "Darwin":
        return
    label = "com.harness-root-hook." + harness + ".reaper"
    agent_dir = Path.home() / "Library/LaunchAgents"
    plist = agent_dir / (label + ".plist")
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", domain + "/" + label],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if remove:
        plist.unlink(missing_ok=True)
        return
    agent_dir.mkdir(parents=True, exist_ok=True)
    data = {"Label": label, "ProgramArguments": [sys.executable, str(Path(__file__).resolve()),
            "--harness", harness, "purge-expired"], "StartInterval": 300, "RunAtLoad": True,
            "ProcessType": "Background", "EnvironmentVariables": {
                "HARNESS_ROOT_HOOK_CONFIG": str(config_path().resolve())}}
    with plist.open("wb") as stream:
        plistlib.dump(data, stream)
    subprocess.run(["launchctl", "bootstrap", domain, str(plist)], check=True)


def check_dependencies():
    if sys.version_info < (3, 9):
        print("Python 3.9 or newer is required.", file=sys.stderr)
        raise RuntimeError("Unsupported Python version")
    required = ["/usr/bin/sudo"]
    if platform.system() == "Linux":
        required.append("secret-tool")
    elif platform.system() == "Darwin":
        required.extend(["/usr/bin/security", "/usr/bin/osascript", "launchctl"])
    else:
        raise RuntimeError("Only Linux and macOS are supported")
    missing = [name for name in required if not shutil.which(name)]
    if missing:
        print("Missing required tools: " + ", ".join(missing) +
              ". On Ubuntu, install libsecret-tools for secret-tool.", file=sys.stderr)
        raise RuntimeError("Required credential-store tools are missing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", choices=("codex", "claude-code"), required=True)
    parser.add_argument("action", choices=("askpass", "init-config", "clear", "purge-expired",
                                            "install-reaper", "remove-reaper", "check"))
    args = parser.parse_args()
    if args.action == "check":
        check_dependencies()
        return
    if args.action == "init-config":
        print(init_config())
        return
    if args.action in ("install-reaper", "remove-reaper"):
        reaper(args.harness, args.action == "remove-reaper")
        return
    with cache_lock(args.harness):
        cache = (MacCache(args.harness) if platform.system() == "Darwin"
                 else LinuxCache(args.harness))
        if args.action == "clear":
            cache.clear()
            return
        ttl = load_config()
        if args.action == "purge-expired":
            if not fresh(cache.metadata(), ttl, time.time()):
                cache.clear()
            return
        print(authenticate(cache, ttl, lambda retry: prompt(args.harness, retry)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError):
        # Do not print exception payloads: subprocess/config errors can contain secrets.
        print("harness-root-hook: authentication/cache operation failed; check config, desktop, and cache permissions.", file=sys.stderr)
        sys.exit(1)
