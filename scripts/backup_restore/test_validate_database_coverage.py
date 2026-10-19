from __future__ import annotations
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate_database_coverage.py")

def lines(*values: str) -> str:
    return "\n".join(values) + "\n"

class CoverageTests(unittest.TestCase):
    def run_cli(self, expected: str, catalog: str, backed_up: str, central: str = "berkahpos_central"):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, value in (("expected.txt", expected), ("catalog.txt", catalog), ("backup.txt", backed_up)):
                (root / name).write_text(value, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--expected", str(root / "expected.txt"),
                 "--catalog", str(root / "catalog.txt"), "--backed-up", str(root / "backup.txt"),
                 "--central-db", central], text=True, capture_output=True, check=False)

    def test_exact_set_passes_independent_of_order(self):
        result = self.run_cli(
            lines("berkahpos_central", "berkahpos_tenant_a", "berkahpos_tenant_b"),
            lines("berkahpos_tenant_b", "berkahpos_central", "berkahpos_tenant_a"),
            lines("berkahpos_tenant_a", "berkahpos_tenant_b", "berkahpos_central"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("expected=3, catalog=3, checksum-verified-backups=3", result.stdout)

    def test_missing_tenant_backup_fails_closed(self):
        result = self.run_cli(
            lines("berkahpos_central", "berkahpos_tenant_a", "berkahpos_tenant_b"),
            lines("berkahpos_central", "berkahpos_tenant_a", "berkahpos_tenant_b"),
            lines("berkahpos_central", "berkahpos_tenant_a"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("verified-backup: 1 expected DB(s) missing", result.stdout)
        self.assertNotIn("berkahpos_tenant_b", result.stdout)

    def test_unexpected_database_in_catalog_fails_closed(self):
        result = self.run_cli(
            lines("berkahpos_central", "berkahpos_tenant_a"),
            lines("berkahpos_central", "berkahpos_tenant_a", "rogue_database"),
            lines("berkahpos_central", "berkahpos_tenant_a"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("catalog: 1 unexpected DB(s)", result.stdout)
        self.assertNotIn("rogue_database", result.stdout)

    def test_duplicate_names_are_rejected(self):
        result = self.run_cli(lines("berkahpos_central", "berkahpos_central"),
                              lines("berkahpos_central"), lines("berkahpos_central"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("duplicate database identifier", result.stderr)

    def test_invalid_identifier_is_rejected(self):
        result = self.run_cli(lines("berkahpos_central", "BAD-NAME"),
                              lines("berkahpos_central", "BAD-NAME"),
                              lines("berkahpos_central", "BAD-NAME"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid PostgreSQL database identifier", result.stderr)

    def test_central_database_is_mandatory(self):
        result = self.run_cli(lines("berkahpos_tenant_a"),
                              lines("berkahpos_tenant_a"), lines("berkahpos_tenant_a"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("central database absent from expected inventory", result.stdout)

if __name__ == "__main__":
    unittest.main()
