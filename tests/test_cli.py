"""The public command works outside the checkout without starting game services"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CliTests(unittest.TestCase):
    def test_each_command_exposes_its_own_help_from_another_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            for command in ('build', 'source', 'play', 'runtime', 'monitor', 'legacy'):
                with self.subTest(command=command):
                    result = subprocess.run([sys.executable, '-B', str(ROOT / 'minecraft.py'), command, '--help'],
                                            cwd=directory, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('usage:', result.stdout)
            self.assertFalse(list(Path(directory).iterdir()))

    def test_unknown_commands_fail_without_executing_a_file(self):
        result = subprocess.run([sys.executable, '-B', str(ROOT / 'minecraft.py'), '../private'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('invalid choice', result.stderr)

    def test_exported_checkout_checks_and_refreshes_its_own_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory) / 'source'

            def command(script, *args):
                return subprocess.run([sys.executable, '-B', str(script), 'source', *args],
                                      cwd=directory, capture_output=True, text=True)

            result = command(ROOT / 'minecraft.py', 'export', str(checkout))
            self.assertEqual(result.returncode, 0, result.stderr)
            script = checkout / 'minecraft.py'
            self.assertEqual(command(script, 'check').returncode, 0)
            with (checkout / 'README.md').open('a') as output:
                output.write('\nA local edit\n')
            result = command(script, 'check')
            self.assertEqual(result.returncode, 1)
            self.assertIn('inventory is stale', result.stderr)
            self.assertEqual(command(script, 'inventory').returncode, 0)
            self.assertEqual(command(script, 'check').returncode, 0)
