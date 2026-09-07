import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        # Installer side effects outside its destination are exercised separately.
        for name in ("cache_action", "check_dependencies"):
            mock = patch.object(installer, name)
            mock.start()
            self.addCleanup(mock.stop)

    def test_install_repeat_remove_preserves_other_hooks(self):
        with tempfile.TemporaryDirectory(prefix="codex test '") as temp:
            home = Path(temp)
            settings = home / "hooks.json"
            original = {"description": "mine", "hooks": {
                "SessionStart": [{"hooks": [{"type": "command", "command": "echo mine"}]}],
                "Stop": [{"hooks": [{"type": "command", "command": "true"}]}]}}
            settings.write_text(json.dumps(original))
            installer.configure(home)
            first = settings.read_text()
            installer.configure(home)
            self.assertEqual(first, settings.read_text())
            config = json.loads(first)
            command = config["hooks"]["SessionStart"][-1]["hooks"][0]["command"]
            result = subprocess.run(command, shell=True, input=json.dumps({
                "hook_event_name": "SessionStart"}), text=True, capture_output=True, check=True)
            output = json.loads(result.stdout)["hookSpecificOutput"]
            self.assertIn("codex-sudo", output["additionalContext"])
            self.assertNotIn("permissionDecision", output)
            (home / "root-hook" / "unrelated").write_text("keep")
            installer.configure(home, uninstall=True)
            installer.configure(home, uninstall=True)
            self.assertEqual(json.loads(settings.read_text()), original)
            self.assertEqual(json.loads((home / "hooks.json.before-root-hook").read_text()), original)
            self.assertTrue((home / "root-hook" / "unrelated").exists())
            self.assertFalse((home / "root-hook" / "codex-sudo").exists())

    def test_bad_config_not_modified(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            for invalid in ("{", "[]", '{"hooks": []}', '{"hooks": {"SessionStart": {}}}'):
                (home / "hooks.json").write_text(invalid)
                with self.assertRaises(ValueError):
                    installer.configure(home)
                self.assertEqual((home / "hooks.json").read_text(), invalid)
                self.assertFalse((home / "root-hook").exists())

    def test_context_ignores_other_events(self):
        result = subprocess.run(["python3", str(ROOT / "context.py")],
                                input='{"hook_event_name":"PermissionRequest"}',
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "")

    def test_wrapper_arguments_and_exit_status(self):
        # Substitute only sudo's executable path in an isolated test copy.
        # Production deliberately uses /usr/bin/sudo instead of PATH lookup.
        with tempfile.TemporaryDirectory(prefix="sudo args ") as temp:
            base = Path(temp)
            fake = base / "fake-sudo"
            fake.write_text('#!/usr/bin/python3\nimport json, os, sys\n'
                            'print(json.dumps([sys.argv[1:], os.environ["SUDO_ASKPASS"]]))\n'
                            'sys.exit(23)\n')
            fake.chmod(0o700)
            wrapper = base / "codex-sudo"
            wrapper.write_text((ROOT / "codex-sudo").read_text().replace(
                '/usr/bin/sudo', '"' + str(fake) + '"'))
            args = ["-u", "root", "printf", "%s", "a b", "$(touch nope)", ""]
            result = subprocess.run(["sh", str(wrapper), *args], text=True, capture_output=True)
            self.assertEqual(result.returncode, 23)
            self.assertEqual(json.loads(result.stdout), [["-A", "-k", *args], str(base / "askpass.sh")])



if __name__ == "__main__":
    unittest.main()
