"""Guardrails ensuring CI never runs the prohibited Supabase workbook writer."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_ROOT = ROOT / ".github" / "workflows"
PROHIBITED_LEGACY_SCRIPTS = (
    "scripts/sync_excel_to_supabase.py",
    "scripts/sync_excel_to_supabase_legacy.py",
)


class WorkflowSecurityContractTests(unittest.TestCase):
    def test_workflows_do_not_reference_prohibited_legacy_sync_scripts(self):
        workflow_files = sorted(
            path
            for path in WORKFLOW_ROOT.rglob("*")
            if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
        )
        self.assertTrue(workflow_files, "GitHub Actions workflows should be present")

        violations = [
            f"{path.relative_to(ROOT)} references {script}"
            for path in workflow_files
            for script in PROHIBITED_LEGACY_SCRIPTS
            if script in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(
            violations,
            [],
            "Legacy Supabase sync code is prohibited, including dry-run use:\n"
            + "\n".join(violations),
        )

    def test_canonical_workbook_ci_uses_the_offline_exporter(self):
        workflow = (
            WORKFLOW_ROOT / "canonical-workbook-validate.yml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "scripts/export_workbook_for_laravel.py --validate-only",
            workflow,
        )
        self.assertIn("Prove deterministic manifest export", workflow)
        self.assertIn("cmp --silent", workflow)
        self.assertIn("sha256sum", workflow)
        self.assertNotIn("pip install --disable-pip-version-check openpyxl requests", workflow)
        self.assertNotIn("curl ", workflow)


if __name__ == "__main__":
    unittest.main()
