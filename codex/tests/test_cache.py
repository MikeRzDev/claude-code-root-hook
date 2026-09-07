import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cache_module", ROOT / "harness_cache.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)
SECRET = "test-only 'password' \\ $() with spaces"


def result(stdout="", code=0, stderr=""):
    return subprocess.CompletedProcess([], code, stdout, stderr)


class MemoryStore:
    def __init__(self, record=None):
        self.record = record
        self.writes = 0

    def metadata(self):
        return copy.deepcopy(self.record)

    load = metadata

    def clear(self):
        self.record = None

    def store(self, record):
        self.record = copy.deepcopy(record)
        self.writes += 1


class ConfigTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "config.json"

    def test_default_two_hours(self):
        self.assertEqual(cache.load_config(self.path), 7200)
        self.assertEqual(json.loads((ROOT / 'config.example.json').read_text()), cache.DEFAULTS)

    def test_overrides_and_disable(self):
        for value, expected in (({"ttl_seconds": 60}, 60), ({"enabled": False}, 0),
                                ({"ttl_seconds": 0}, 0), ({}, 7200)):
            self.path.write_text(json.dumps({"cache": value}))
            self.assertEqual(cache.load_config(self.path), expected)

    def test_invalid_config_fails_closed(self):
        for value in ('{', '[]', '{"cache": null}', '{"cache":{"ttl_seconds":-1}}',
                      '{"cache":{"ttl_seconds":true}}', '{"cache":{"ttl_seconds":"7200"}}',
                      '{"cache":{"enabled":"false"}}', '{"cache":{"ttl_seconds":1.5}}',
                      '{"cache":{"ttl_second":7200}}', '{"other": 1}'):
            with self.subTest(value=value):
                self.path.write_text(value)
                with self.assertRaises(ValueError):
                    cache.load_config(self.path)

    def test_init_preserves_custom_settings(self):
        with patch.dict(os.environ, {"HARNESS_ROOT_HOOK_CONFIG": str(self.path)}):
            cache.init_config()
            self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
            self.path.write_text('{"cache":{"ttl_seconds":45}}')
            cache.init_config()
            self.assertEqual(cache.load_config(), 45)

    def test_xdg_and_explicit_config_path(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.path.parent)}, clear=True):
            self.assertEqual(cache.config_path(), self.path.parent / 'harness-root-hook/config.json')
            with patch.dict(os.environ, {"HARNESS_ROOT_HOOK_CONFIG": str(self.path)}):
                self.assertEqual(cache.config_path(), self.path)


class AuthenticationTests(unittest.TestCase):
    def test_initial_hit_and_fixed_expiry(self):
        store = MemoryStore()
        ask = Mock(return_value=SECRET)
        check = Mock(return_value=True)
        for now in (1000, 1001, 8100, 8199):
            self.assertEqual(cache.authenticate(store, 7200, ask, check, lambda: now), SECRET)
        self.assertEqual(ask.call_count, 1)
        self.assertEqual(store.writes, 1)
        self.assertEqual(store.record['created_at'], 1000)
        cache.authenticate(store, 7200, ask, check, lambda: 8200)
        self.assertEqual(ask.call_count, 2)
        self.assertEqual(store.record['created_at'], 8200)

    def test_reduced_ttl_and_increase_does_not_extend_existing_cache(self):
        for ttl, now in ((60, 1060), (20000, 8200)):
            store = MemoryStore({'password': SECRET, 'created_at': 1000, 'ttl_seconds': 7200})
            ask = Mock(return_value=SECRET)
            cache.authenticate(store, ttl, ask, lambda _: True, lambda: now)
            ask.assert_called_once()

    def test_disabled_clears_and_never_stores(self):
        store = MemoryStore({'password': SECRET, 'created_at': 1000, 'ttl_seconds': 7200})
        ask = Mock(return_value=SECRET)
        for _ in range(2):
            cache.authenticate(store, 0, ask, lambda _: True, lambda: 1001)
        self.assertEqual(ask.call_count, 2)
        self.assertIsNone(store.record)
        self.assertEqual(store.writes, 0)

    def test_wrong_password_is_not_cached(self):
        store = MemoryStore()
        ask = Mock(side_effect=['wrong', SECRET])
        self.assertEqual(cache.authenticate(store, 7200, ask, lambda p: p == SECRET), SECRET)
        self.assertEqual(store.writes, 1)
        self.assertEqual(store.record['password'], SECRET)
        self.assertEqual(ask.call_args_list[1].args, (True,))

    def test_three_failures_leave_no_cache(self):
        store = MemoryStore()
        ask = Mock(return_value='wrong')
        with self.assertRaises(RuntimeError):
            cache.authenticate(store, 7200, ask, lambda _: False)
        self.assertEqual(ask.call_count, 3)
        self.assertIsNone(store.record)

    def test_changed_password_invalidates_cache(self):
        store = MemoryStore({'password': 'old', 'created_at': 1000, 'ttl_seconds': 7200})
        ask = Mock(return_value=SECRET)
        cache.authenticate(store, 7200, ask, lambda p: p == SECRET, lambda: 1001)
        ask.assert_called_once()
        self.assertEqual(store.record['password'], SECRET)

    def test_cancel_aborts_without_store(self):
        store = MemoryStore()
        with self.assertRaises(RuntimeError):
            cache.authenticate(store, 7200, Mock(side_effect=RuntimeError('cancel')), lambda _: True)
        self.assertIsNone(store.record)

    def test_invalid_timestamps_and_clock_rollback(self):
        for timestamp in (None, '1000', True, float('nan'), float('inf'), 1001):
            self.assertFalse(cache.fresh({'created_at': timestamp, 'ttl_seconds': 7200}, 7200, 1000))

    def test_verify_uses_stdin_and_disables_askpass_recursion(self):
        with patch.object(cache.subprocess, 'run', return_value=result()) as run:
            with patch.dict(os.environ, {'SUDO_ASKPASS': '/do/not/recurse'}):
                self.assertTrue(cache.verify(SECRET))
        self.assertNotIn(SECRET, str(run.call_args.args))
        self.assertEqual(run.call_args.kwargs['input'], SECRET + '\n')
        self.assertNotIn('SUDO_ASKPASS', run.call_args.kwargs['env'])
        self.assertIn('-k', run.call_args.args[0])


class BackendTests(unittest.TestCase):
    def test_secure_storage_roundtrip_and_expiry_for_both_harnesses_and_os(self):
        for harness in ('codex', 'claude-code'):
            for backend in (cache.LinuxCache, cache.MacCache):
                with self.subTest(harness=harness, backend=backend.__name__):
                    stored = None
                    calls = []
                    def run(args, **kwargs):
                        nonlocal stored
                        calls.append((args, kwargs))
                        if args[0] == 'secret-tool':
                            self.assertIn(harness, args)
                            if args[1] == 'store':
                                stored = json.loads(kwargs['input'])
                                return result()
                            if args[1] == 'clear':
                                stored = None
                                return result()
                            return result(json.dumps(stored)) if stored else result(code=1)
                        if args[1] == '-i':
                            command = shlex.split(kwargs['input'])
                            stored = json.loads(base64.b64decode(command[command.index('-w') + 1]))
                            self.assertIn('harness-root-hook.' + harness, command)
                            return result()
                        if args[1] == 'delete-generic-password':
                            stored = None
                            return result()
                        if stored is None:
                            return result(code=44)
                        if '-w' in args:
                            return result(base64.b64encode(json.dumps(stored).encode()).decode())
                        return result(f'"icmt"<blob>="{stored["created_at"]} {stored["ttl_seconds"]}"')
                    with patch.object(cache.subprocess, 'run', side_effect=run):
                        store = backend(harness)
                        ask = Mock(return_value=SECRET)
                        for now in (1000, 2000, 8199, 8200):
                            cache.authenticate(store, 7200, ask, lambda _: True, lambda: now)
                        self.assertEqual(ask.call_count, 2)
                        self.assertEqual(stored['created_at'], 8200)
                    for args, kwargs in calls:
                        self.assertNotIn(SECRET, str(args))
                        self.assertNotIn(base64.b64encode(SECRET.encode()).decode(), str(args))

    def test_store_errors_do_not_fall_back_to_files(self):
        for backend in (cache.LinuxCache, cache.MacCache):
            with patch.object(cache.subprocess, 'run', return_value=result(code=2, stderr='unavailable')):
                with self.assertRaises(RuntimeError):
                    backend('codex').store({'password': SECRET, 'created_at': 1000, 'ttl_seconds': 7200})

    def test_malformed_store_record_is_ignored(self):
        for backend in (cache.LinuxCache, cache.MacCache):
            with patch.object(cache.subprocess, 'run', return_value=result('not valid json/base64')):
                self.assertIsNone(backend('codex').load())

    def test_secret_service_failure_is_not_a_cache_miss(self):
        with patch.object(cache.subprocess, 'run', return_value=result(code=1, stderr='locked')):
            with self.assertRaises(RuntimeError):
                cache.LinuxCache('codex').load()

    def test_no_generic_password_read_for_expired_mac_metadata(self):
        with patch.object(cache.subprocess, 'run', return_value=result('"icmt"<blob>="1000 7200"')) as run:
            self.assertFalse(cache.fresh(cache.MacCache('codex').metadata(), 7200, 8200))
            self.assertNotIn('-w', run.call_args.args[0])


class DesktopTests(unittest.TestCase):
    def test_dialog_selection(self):
        for osname, available, display, wayland, expected in (
                ('Linux', 'zenity', ':0', '', 'zenity'),
                ('Linux', 'kdialog', '', 'wayland-0', 'kdialog'),
                ('Linux', 'ssh-askpass', ':0', '', 'ssh-askpass'),
                ('Darwin', '', '', '', '/usr/bin/osascript')):
            with self.subTest(osname=osname, available=available):
                with patch.object(cache.platform, 'system', return_value=osname), \
                     patch.object(cache.shutil, 'which', side_effect=lambda p: p if p == available else None), \
                     patch.dict(os.environ, {'DISPLAY': display, 'WAYLAND_DISPLAY': wayland}), \
                     patch.object(cache.subprocess, 'run', return_value=result(SECRET + '\n')) as run:
                    self.assertEqual(cache.prompt('codex'), SECRET)
                    self.assertEqual(run.call_args.args[0][0], expected)

    def test_headless_and_cancel(self):
        with patch.object(cache.platform, 'system', return_value='Linux'), \
             patch.dict(os.environ, {'DISPLAY': '', 'WAYLAND_DISPLAY': ''}):
            with self.assertRaises(RuntimeError):
                cache.prompt('codex')
        with patch.object(cache.platform, 'system', return_value='Darwin'), \
             patch.object(cache.subprocess, 'run', return_value=result(code=1)):
            with self.assertRaises(RuntimeError):
                cache.prompt('claude-code')

    def test_mac_reaper_preserves_custom_config_and_removes_only_own_agent(self):
        with tempfile.TemporaryDirectory(prefix='reaper & ') as temp:
            home = Path(temp)
            with patch.object(cache.platform, 'system', return_value='Darwin'), \
                 patch.object(cache.Path, 'home', return_value=home), \
                 patch.object(cache.subprocess, 'run', return_value=result()), \
                 patch.dict(os.environ, {'HARNESS_ROOT_HOOK_CONFIG': str(home / 'custom.json')}):
                for harness in ('codex', 'claude-code'):
                    cache.reaper(harness)
                path = home / 'Library/LaunchAgents/com.harness-root-hook.codex.reaper.plist'
                data = plistlib.loads(path.read_bytes())
                self.assertEqual(data['StartInterval'], 300)
                self.assertEqual(data['EnvironmentVariables']['HARNESS_ROOT_HOOK_CONFIG'], str(home / 'custom.json'))
                cache.reaper('codex', remove=True)
                self.assertFalse(path.exists())
                self.assertTrue(path.with_name('com.harness-root-hook.claude-code.reaper.plist').exists())

    def test_concurrent_authentication_only_prompts_once(self):
        with tempfile.TemporaryDirectory() as temp, \
             patch.dict(os.environ, {'XDG_RUNTIME_DIR': temp}), \
             patch.object(cache.platform, 'system', return_value='Linux'):
            store = MemoryStore()
            ask = Mock(return_value=SECRET)
            outputs = []
            def worker():
                with cache.cache_lock('codex'):
                    outputs.append(cache.authenticate(store, 7200, ask, lambda _: True))
            threads = [threading.Thread(target=worker) for _ in range(3)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=2)
                self.assertFalse(thread.is_alive())
            self.assertEqual(outputs, [SECRET] * 3)
            ask.assert_called_once()
            for path in Path(temp).rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), b'')  # Lock files contain no secrets.


if __name__ == '__main__':
    unittest.main()
