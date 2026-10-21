"""Regression tests for the no-Supabase CI operating contract."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
LEGACY_SYNC_SCRIPTS = (
    "scripts/sync_excel_to_supabase.py",
    "scripts/sync_excel_to_supabase_legacy.py",
)


class WorkflowSecurityContractTests(unittest.TestCase):
    def test_no_github_workflow_references_legacy_supabase_sync_scripts(self):
        workflow_files = sorted(
            path
            for path in WORKFLOWS.rglob("*")
            if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
        )
        self.assertTrue(workflow_files, "Expected GitHub Actions workflow files")

        violations = []
        for workflow in workflow_files:
            text = workflow.read_text(encoding="utf-8")
            for script in LEGACY_SYNC_SCRIPTS:
                if script in text:
                    violations.append(f"{workflow.relative_to(ROOT)} references {script}")

        self.assertEqual(
            violations,
            [],
            "Legacy Supabase sync code is prohibited, even with a dry-run flag:\n"
            + "\n".join(violations),
        )

    def test_canonical_workbook_workflow_uses_offline_exporter(self):
        workflow_path = WORKFLOWS / "canonical-workbook-validate.yml"
        workflow = workflow_path.read_text(encoding="utf-8")

        self.assertIn(
            "scripts/export_workbook_for_laravel.py --validate-only",
            workflow,
        )
        self.assertIn("Validate canonical workbook and 352-entry contract without network access", workflow)
        self.assertNotIn("pip install --disable-pip-version-check openpyxl requests", workflow)
        self.assertNotIn("curl ", workflow)
        self.assertNotIn("http://", workflow)
        self.assertNotIn("https://", workflow)


if __name__ == "__main__":
    unittest.main()
