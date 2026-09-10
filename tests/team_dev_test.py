import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("team_dev", ROOT / "scripts/team_dev.py")
team = importlib.util.module_from_spec(spec)
spec.loader.exec_module(team)


class TeamDevTest(unittest.TestCase):
    def test_only_full_commit_refs_can_execute(self):
        for ref in ("main", "abc123", "a" * 40 + ";touch /tmp/unsafe"):
            with self.assertRaises(ValueError):
                team.firstboot("JW", {}, ref)

    def test_identity_is_data_not_shell_code(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "injected"
            name = f"James O'Name $(touch {marker}) `touch {marker}`"
            script = "git() { printf '%s\\n' \"$*\"; }\n" + team.identity_script("JW", {"name": name, "email": "jw@example.test"})
            result = subprocess.run(["bash"], input=script, text=True, capture_output=True,
                                    env={"HOME": directory, "PATH": "/usr/bin:/bin"}, check=True)
            self.assertIn(name, result.stdout)
            self.assertFalse(marker.exists())
            self.assertEqual(json.loads((Path(directory)/'.config/team-dev/identity.json').read_text())["name"], name)

    def test_dry_run_is_offline_and_does_not_create_files(self):
        with tempfile.TemporaryDirectory() as directory:
            roster = Path(directory)/"roster.json"
            result = subprocess.run([str(ROOT/"team-dev.sh"), "--roster", str(roster), "create", "JW",
                                     "--ref", "a"*40, "--dry-run"], text=True, capture_output=True, check=True)
            self.assertIn("--cpu 4 --memory 8GB --disk 100GB", result.stdout)
            self.assertIn("--tailscale off", result.stdout)
            self.assertIn("--no-email", result.stdout)
            self.assertLess(len(result.stdout.encode()), 10240)
            self.assertEqual(list(Path(directory).iterdir()), [])
            subprocess.run(["bash", "-n"], input=result.stdout.split("\n", 1)[1], text=True, check=True)

    def test_existing_vm_cannot_be_replaced(self):
        with patch('sys.argv', ['team-dev', 'create', 'JW', '--ref', 'a'*40]), \
             patch.object(team, 'inventory', return_value=[{'vm_name':'dev-jw'}]), \
             patch.object(team, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'already exists'):
                team.main()
            run.assert_not_called()

    def test_failed_setup_never_records_base_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory)/'.local/share/exe-setup'
            (dest/'.git').mkdir(parents=True)
            setup = dest/'setup.sh'
            setup.write_text('#!/bin/bash\nexit 42\n')
            setup.chmod(0o755)
            result = subprocess.run(['bash'], input='git() { return 0; }\n' + team.firstboot('JW', {'name':'', 'email':''}, 'a'*40),
                                    text=True, env={'HOME':directory, 'PATH':'/usr/bin:/bin'})
            self.assertEqual(result.returncode, 42)
            self.assertEqual((Path(directory)/'.local/state/team-dev/install-status').read_text(), 'failed')

    def test_incomplete_roster_cannot_grant_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                team.roster_entry(Path(directory)/'missing', 'JW', required=True)


if __name__ == '__main__':
    unittest.main()
