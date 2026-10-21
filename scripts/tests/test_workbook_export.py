"""Unit tests for the offline canonical-workbook parser."""

import unittest

from scripts.export_workbook_for_laravel import bool_value, canonical_mapping_key, parse_value, row_dicts


class WorksheetDouble:
    def __init__(self, rows):
        self._rows = rows

    def iter_rows(self, values_only=False):
        if not values_only:
            raise AssertionError("row_dicts must request values_only=True")
        return iter(self._rows)


class OfflineWorkbookParserTests(unittest.TestCase):
    def test_parse_value_accepts_json_object_and_normalizes_version(self):
        self.assertEqual(
            parse_value('{"enabled": true}', "feature:pos"),
            {"enabled": True, "version": 1},
        )

    def test_parse_value_preserves_explicit_positive_integer_version(self):
        self.assertEqual(
            parse_value('{"version": "3", "enabled": false}', "feature:pos"),
            {"version": 3, "enabled": False},
        )

    def test_parse_value_rejects_invalid_json(self):
        with self.assertRaisesRegex(ValueError, "not valid JSON"):
            parse_value('{"enabled":', "feature:pos")

    def test_parse_value_rejects_non_object_json(self):
        with self.assertRaisesRegex(ValueError, "must decode to an object"):
            parse_value('[1, 2]', "feature:pos")

    def test_parse_value_rejects_boolean_version(self):
        with self.assertRaisesRegex(ValueError, "positive integer"):
            parse_value('{"version": true}', "feature:pos")

    def test_parse_value_rejects_zero_version(self):
        with self.assertRaisesRegex(ValueError, "positive integer"):
            parse_value('{"version": 0}', "feature:pos")

    def test_boolean_parser_accepts_explicit_active_values(self):
        for value in (True, "true", "1", "yes", "active", "enabled"):
            with self.subTest(value=value):
                self.assertTrue(bool_value(value))

    def test_boolean_parser_does_not_treat_arbitrary_strings_as_true(self):
        for value in (False, "false", "disabled", "no", "", None):
            with self.subTest(value=value):
                self.assertFalse(bool_value(value))

    def test_row_dicts_ignores_blank_rows_and_empty_headers(self):
        worksheet = WorksheetDouble(
            [
                ("tenant_id", "", "template_id"),
                ("tenant_001", "ignored", "BASIC"),
                (None, None, None),
            ]
        )
        self.assertEqual(
            row_dicts(worksheet),
            [{"tenant_id": "tenant_001", "template_id": "BASIC"}],
        )


    def test_canonical_mapping_key_uses_expected_key_when_workbook_cell_is_blank(self):
        self.assertEqual(
            canonical_mapping_key("", "tenant:tenant_001:service:pos", "SERVICE row"),
            "tenant:tenant_001:service:pos",
        )

    def test_canonical_mapping_key_accepts_exact_mapping(self):
        self.assertEqual(
            canonical_mapping_key("device:device_001", "device:device_001", "DEVICE row"),
            "device:device_001",
        )

    def test_canonical_mapping_key_rejects_cross_service_mapping(self):
        with self.assertRaisesRegex(ValueError, "must be.*tenant:tenant_001:service:pos"):
            canonical_mapping_key(
                "tenant:tenant_001:service:akuntansi",
                "tenant:tenant_001:service:pos",
                "SERVICE row ('tenant_001', 'pos')",
            )

    def test_canonical_mapping_key_rejects_device_mapping_to_another_device(self):
        with self.assertRaisesRegex(ValueError, "device:device_001"):
            canonical_mapping_key(
                "device:device_002",
                "device:device_001",
                "DEVICE row device_001",
            )

if __name__ == "__main__":
    unittest.main()
