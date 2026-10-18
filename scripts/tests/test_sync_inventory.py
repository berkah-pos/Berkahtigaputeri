"""Regression tests for workbook-owned relational inventory verification."""

import unittest

from scripts.export_workbook_for_laravel import _assert_exact_inventory


class ExactInventoryTests(unittest.TestCase):
    def test_accepts_exact_inventory(self) -> None:
        _assert_exact_inventory("devices", ["d1", "d2"], ["d2", "d1"])

    def test_rejects_missing_workbook_rows(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "missing=.*d2"):
            _assert_exact_inventory("devices", ["d1", "d2"], ["d1"])

    def test_rejects_extra_database_rows(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "extra=.*legacy-device"):
            _assert_exact_inventory(
                "devices",
                ["d1", "d2"],
                ["d1", "d2", "legacy-device"],
            )

    def test_rejects_missing_and_extra_rows_together(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "missing=.*expected"):
            _assert_exact_inventory(
                "devices",
                ["expected"],
                ["stale"],
            )


if __name__ == "__main__":
    unittest.main()
