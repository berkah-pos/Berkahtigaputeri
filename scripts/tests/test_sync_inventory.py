"""Regression tests for the canonical workbook-to-Laravel manifest parser."""

import unittest

from scripts.export_workbook_for_laravel import flag, parse_object


class ManifestParsingTests(unittest.TestCase):
    def test_parse_object_defaults_version_to_one(self) -> None:
        self.assertEqual(parse_object('{"enabled": true}', "global"), {"enabled": True, "version": 1})

    def test_parse_object_normalizes_positive_string_version(self) -> None:
        self.assertEqual(parse_object('{"version": "2"}', "tenant"), {"version": 2})

    def test_parse_object_accepts_dictionary_input(self) -> None:
        self.assertEqual(parse_object({"version": 3, "limit": 10}, "device"), {"version": 3, "limit": 10})

    def test_parse_object_rejects_invalid_json(self) -> None:
        with self.assertRaisesRegex(ValueError, "invalid JSON"):
            parse_object("{broken", "tenant:demo")

    def test_parse_object_rejects_non_object_json(self) -> None:
        with self.assertRaisesRegex(ValueError, "expected JSON object"):
            parse_object("[1, 2]", "tenant:demo")

    def test_parse_object_rejects_boolean_and_nonpositive_versions(self) -> None:
        for value in (True, 0, "0", "1.5"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "version must be a positive integer"):
                    parse_object({"version": value}, "tenant:demo")

    def test_flag_handles_supported_true_values(self) -> None:
        for value in (True, "TRUE", "1", "yes", "active", "enabled"):
            with self.subTest(value=value):
                self.assertTrue(flag(value))

    def test_flag_defaults_unknown_values_to_false(self) -> None:
        for value in (False, None, "no", "disabled", "unknown"):
            with self.subTest(value=value):
                self.assertFalse(flag(value))


if __name__ == "__main__":
    unittest.main()
