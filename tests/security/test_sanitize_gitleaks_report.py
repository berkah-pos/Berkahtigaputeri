#!/usr/bin/env python3
"""Regression test: sensitive Gitleaks report fields must never be emitted."""
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "security" / "sanitize_gitleaks_report.py"
spec = importlib.util.spec_from_file_location("sanitize_gitleaks_report", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


class SanitizeGitleaksReportTest(unittest.TestCase):
    def test_drops_secret_match_raw_and_author_fields(self):
        synthetic_secret = "SYNTHETIC_NEVER_PRINT_THIS_VALUE"
        result = module.sanitize_findings([{
            "RuleID": "generic-api-key",
            "Description": "Generic API Key",
            "File": "fixtures/fake.env",
            "StartLine": 3,
            "EndLine": 3,
            "Commit": "0123456789abcdef",
            "Fingerprint": "safe-fingerprint",
            "Secret": synthetic_secret,
            "Match": synthetic_secret,
            "Raw": synthetic_secret,
            "Author": "synthetic@example.invalid",
            "Email": "synthetic@example.invalid",
        }])
        rendered = json.dumps(result)
        self.assertIn("generic-api-key", rendered)
        self.assertIn("fixtures/fake.env", rendered)
        self.assertNotIn(synthetic_secret, rendered)
        self.assertNotIn('"Secret"', rendered)
        self.assertNotIn('"Match"', rendered)
        self.assertNotIn('"Raw"', rendered)
        self.assertNotIn("synthetic@example.invalid", rendered)

    def test_non_list_report_is_rejected(self):
        with self.assertRaises(ValueError):
            module.sanitize_findings({"Secret": "SYNTHETIC_NEVER_PRINT_THIS_VALUE"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
