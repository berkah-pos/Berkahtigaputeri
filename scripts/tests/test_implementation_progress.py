import json
import tempfile
import unittest
from pathlib import Path

from scripts.implementation_progress import calculate_progress, load_progress


class ImplementationProgressTests(unittest.TestCase):
    def fixture(self):
        return {
            "schema_version": 1,
            "gates": [
                {"id": "A", "weight": 60, "implementation": "present", "verified": False, "evidence_sha": None, "evidence_url": None},
                {"id": "B", "weight": 40, "implementation": "partial", "verified": False, "evidence_sha": None, "evidence_url": None},
            ],
        }

    def test_global_progress_weights_implementation_and_verification_equally(self):
        scores = calculate_progress(self.fixture())
        self.assertEqual(scores["source_coverage_percent"], 80.0)
        self.assertEqual(scores["verified_acceptance_percent"], 0)
        self.assertEqual(scores["global_delivery_percent"], 40.0)

    def test_verified_gate_counts_only_with_exact_revision_evidence_fields(self):
        data = self.fixture()
        data["gates"][0]["verified"] = True
        with self.assertRaisesRegex(ValueError, "requires evidence_sha and evidence_url"):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "progress.json"
                path.write_text(json.dumps(data), encoding="utf-8")
                load_progress(path)

    def test_register_rejects_weights_that_do_not_total_100(self):
        data = self.fixture()
        data["gates"][0]["weight"] += 1
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "progress.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "total exactly 100"):
                load_progress(path)

if __name__ == "__main__":
    unittest.main()
