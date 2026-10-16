#!/usr/bin/env python3
"""Unit tests for parity logic. These are not staging parity evidence."""

from __future__ import annotations

import contextlib
from datetime import datetime, timezone
import io
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import verify_flutter_config_parity as parity  # noqa: E402


def manifest_fixture():
    return {
        "global_config": {"version": 1, "color": "global", "inherited": "yes"},
        "templates": [{"id": "PRO", "config": {"version": 1, "color": "template", "template": True}}],
        "tenants": [{
            "tenant_id": "t1", "template_id": "PRO", "is_active": True,
            "config": {"version": 1, "color": "tenant", "tenant": True},
        }],
        "services": [
            {"tenant_id": "t1", "service": "pos", "enabled": True,
             "config": {"version": 1, "color": "pos", "pos_only": True}},
            {"tenant_id": "t1", "service": "akuntansi", "enabled": True,
             "config": {"version": 1, "color": "akuntansi", "accounting_only": True}},
        ],
        "devices": [{"device_id": "d1", "tenant_id": "t1", "active": True,
                     "config": {"version": 1, "color": "device", "device": True}}],
    }


class FlutterConfigParityTest(unittest.TestCase):
    def test_inventory_export_covers_each_scope_and_separate_service_key(self):
        entries = parity.canonical_inventory_entries(manifest_fixture())
        self.assertEqual(
            ["device:d1", "global", "template:PRO", "tenant:t1",
             "tenant:t1:service:akuntansi", "tenant:t1:service:pos"],
            [row["key"] for row in entries],
        )

    def test_inventory_diff_detects_missing_extra_and_value_changes(self):
        expected = [{"key": "global", "config": {"a": 1}}]
        expected.extend({"key": "fixture:" + str(i), "config": {"i": i}} for i in range(351))
        actual = json.loads(json.dumps({"entries": expected}))
        actual["entries"][-1]["config"]["i"] = -1
        actual["entries"].pop(0)
        actual["entries"].append({"key": "extra:bad", "config": {}})
        result = parity.compare_inventory(expected, actual)
        self.assertEqual("FAIL", result["status"])
        self.assertEqual(["global"], result["missing_keys"])
        self.assertEqual(["extra:bad"], result["extra_keys"])
        self.assertEqual(["fixture:350"], result["config_mismatch_keys"])

    def test_json_object_order_does_not_change_inventory_parity(self):
        expected = [{"key": "global", "config": {"a": 1, "nested": {"x": True, "y": 2}}}]
        expected.extend({"key": "fixture:" + str(i), "config": {}} for i in range(351))
        actual_entries = json.loads(json.dumps(expected))
        actual_entries[0] = {
            "key": "global", "config": {"nested": {"y": 2, "x": True}, "a": 1}
        }
        result = parity.compare_inventory(expected, {"entries": list(reversed(actual_entries))})
        self.assertEqual("PASS", result["status"])

    def test_effective_config_parity_keeps_pos_and_akuntansi_separate(self):
        manifest = manifest_fixture()
        # A nested object survives across layers exactly as Laravel deepMerge does.
        manifest["global_config"]["nested"] = {"inherited": True, "overridden": "global"}
        manifest["templates"][0]["config"]["nested"] = {"overridden": "template", "template_only": 1}
        manifest["tenants"][0]["config"]["nested"] = {"tenant_only": 2}
        fixtures = parity.build_valid_fixtures(manifest)
        self.assertEqual({"pos", "akuntansi"}, {row["service"] for row in fixtures})
        pos = parity.expected_effective_config(
            manifest, {"tenant_id": "t1", "device_id": "d1", "service": "pos"}
        )
        accounting = parity.expected_effective_config(
            manifest, {"tenant_id": "t1", "device_id": "d1", "service": "akuntansi"}
        )
        self.assertEqual("device", pos["color"])
        self.assertIn("pos_only", pos)
        self.assertNotIn("accounting_only", pos)
        self.assertIn("accounting_only", accounting)
        self.assertNotIn("pos_only", accounting)
        self.assertEqual(
            {"inherited": True, "overridden": "template", "template_only": 1, "tenant_only": 2},
            pos["nested"],
        )
        self.assertEqual(pos["nested"], accounting["nested"])

    def test_valid_fixtures_exclude_suspended_and_expired_subscriptions(self):
        manifest = manifest_fixture()
        manifest["tenants"].extend([
            {
                "tenant_id": "t2", "template_id": "PRO", "is_active": True,
                "subscription_status": "suspended", "expires_at": "2026-12-01T00:00:00Z",
                "config": {},
            },
            {
                "tenant_id": "t3", "template_id": "PRO", "is_active": True,
                "subscription_status": "active", "expires_at": "2026-09-01T00:00:00Z",
                "config": {},
            },
        ])
        manifest["services"].extend([
            {"tenant_id": tenant, "service": service, "enabled": True, "config": {}}
            for tenant in ("t2", "t3")
            for service in ("pos", "akuntansi")
        ])
        manifest["devices"].extend([
            {"device_id": "d2", "tenant_id": "t2", "active": True, "config": {}},
            {"device_id": "d3", "tenant_id": "t3", "active": True, "config": {}},
        ])
        fixtures = parity.build_valid_fixtures(
            manifest, now_utc=datetime(2026, 10, 15, tzinfo=timezone.utc)
        )
        self.assertEqual({"t1"}, {fixture["tenant_id"] for fixture in fixtures})
        self.assertEqual({"pos", "akuntansi"}, {fixture["service"] for fixture in fixtures})

    def test_laravel_merge_semantics_replace_lists_and_nested_empty_maps(self):
        merged = parity.merge_effective_layers([
            {"root": {"keep": True, "replace": "base"}, "items": [1, 2]},
            {},
            {"root": {"replace": "override"}, "items": [9], "empty_map": {"old": True}},
            {"empty_map": {}},
        ])
        self.assertEqual({"keep": True, "replace": "override"}, merged["root"])
        self.assertEqual([9], merged["items"])
        self.assertEqual({}, merged["empty_map"])

    def test_missing_staging_evidence_is_not_verified_and_returns_exit_two(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = parity.main(["--workbook", str(parity.exporter.DEFAULT_WORKBOOK)])
        report = json.loads(output.getvalue())
        self.assertEqual(2, code)
        self.assertEqual("NOT VERIFIED", report["status"])
        self.assertEqual("PASS", report["workbook"]["status"])
        self.assertEqual("NOT VERIFIED", report["inventory_status"])
        self.assertEqual("NOT VERIFIED", report["effective_config_status"])


if __name__ == "__main__":
    unittest.main()
