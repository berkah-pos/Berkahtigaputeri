"""Fail-closed regression tests for canonical Supabase workbook synchronization."""

from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

import sync_excel_to_supabase as sync  # noqa: E402
import sync_excel_to_supabase_legacy as legacy  # noqa: E402


class FakeResponse:
    def __init__(self, *, status_code: int, payload, text: str = "") -> None:
        self.status_code = status_code
        self.ok = 200 <= status_code < 300
        self._payload = payload
        self.text = text

    def json(self):
        return self._payload


class SyncFailClosedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.payloads = legacy.load_workbook_payloads()
        cls.keys = [str(row["key"]) for row in cls.payloads.app_config]

    def test_canonical_workbook_key_manifest_matches_expected_md5(self):
        digest = legacy._assert_canonical_key_manifest("test workbook", self.keys)
        self.assertEqual(digest, legacy.EXPECTED_KEYSET_MD5)
        self.assertEqual(len(self.keys), 352)

    def test_same_count_but_different_workbook_key_manifest_is_rejected(self):
        changed = list(self.keys)
        changed[0] = "tenant:unauthorized-inventory-replacement"
        with self.assertRaisesRegex(ValueError, "key manifest MD5 mismatch"):
            legacy._assert_canonical_key_manifest("mutated workbook", changed)

    def test_missing_credentials_returns_nonzero_without_invoking_sync(self):
        stdout, stderr = StringIO(), StringIO()
        with (
            patch.dict(os.environ, {"SUPABASE_URL": "", "SUPABASE_SERVICE_KEY": ""}),
            patch.object(sync.legacy, "load_workbook_payloads", return_value=self.payloads),
            patch.object(sync.legacy, "_print_inventory"),
            patch.object(sync, "sync") as sync_mock,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = sync.main(["--expect-keys", "352"])
        self.assertEqual(result, 2)
        self.assertIn("SUPABASE_URL and SUPABASE_SERVICE_KEY are required", stderr.getvalue())
        sync_mock.assert_not_called()

    def test_failed_sync_returns_nonzero(self):
        stdout, stderr = StringIO(), StringIO()
        with (
            patch.dict(os.environ, {
                "SUPABASE_URL": "https://invalid.example.test",
                "SUPABASE_SERVICE_KEY": "unit-test-only-not-a-secret",
            }),
            patch.object(sync.legacy, "load_workbook_payloads", return_value=self.payloads),
            patch.object(sync.legacy, "_print_inventory"),
            patch.object(sync, "sync", side_effect=RuntimeError("forced sync failure")),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = sync.main(["--expect-keys", "352"])
        self.assertEqual(result, 1)
        self.assertIn("ERROR: forced sync failure", stderr.getvalue())

    def test_expected_key_count_mismatch_fails_dry_run(self):
        stdout, stderr = StringIO(), StringIO()
        with (
            patch.object(sync.legacy, "load_workbook_payloads", return_value=self.payloads),
            patch.object(sync.legacy, "_print_inventory"),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = sync.main(["--dry-run", "--expect-keys", "351"])
        self.assertEqual(result, 1)
        self.assertIn("Expected 351 app_config keys; got 352", stderr.getvalue())
        self.assertNotIn("DRY-RUN OK", stdout.getvalue())

    def test_normal_atomic_update_fails_closed_on_version_conflict(self):
        response = FakeResponse(
            status_code=409,
            payload={"code": "40001", "message": "version conflict"},
            text="version conflict",
        )
        with patch.object(sync.requests, "post", return_value=response) as post:
            with self.assertRaisesRegex(sync.VersionConflictError, "version conflict"):
                sync._atomic_update(
                    key="global",
                    new_value={"some_setting": True},
                    expected_version=13,
                    url="https://invalid.example.test",
                    service_key="unit-test-only-not-a-secret",
                )
        sent = post.call_args.kwargs["json"]
        self.assertEqual(sent["p_expected_version"], 13)
        self.assertNotIn("version", sent["p_new_value"])

    def test_non_conflict_rpc_error_is_not_silently_ignored(self):
        response = FakeResponse(
            status_code=403,
            payload={"code": "42501", "message": "permission denied"},
            text="permission denied",
        )
        with patch.object(sync.requests, "post", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403: permission denied"):
                sync._atomic_update(
                    key="global",
                    new_value={"some_setting": True},
                    expected_version=13,
                    url="https://invalid.example.test",
                    service_key="unit-test-only-not-a-secret",
                )

    def test_wrong_rpc_version_increment_is_rejected(self):
        response = FakeResponse(
            status_code=200,
            payload={"some_setting": True, "version": 15},
        )
        with patch.object(sync.requests, "post", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "expected 14, got 15"):
                sync._atomic_update(
                    key="global",
                    new_value={"some_setting": True},
                    expected_version=13,
                    url="https://invalid.example.test",
                    service_key="unit-test-only-not-a-secret",
                )

    def test_post_sync_verification_checks_exact_inventory_and_key_manifest_hash(self):
        def fake_fetch_rows(*, table, **_kwargs):
            if table == "app_config":
                return [{"key": key} for key in self.keys]
            if table == "tenants":
                return [{"tenant_id": row["tenant_id"]} for row in self.payloads.tenants]
            if table == "devices":
                return [{"device_id": row["device_id"]} for row in self.payloads.devices]
            if table == "tenant_services":
                return [
                    {"tenant_id": row["tenant_id"], "service": row["service"]}
                    for row in self.payloads.services
                ]
            raise AssertionError(f"Unexpected verification table: {table}")

        stdout = StringIO()
        with patch.object(legacy, "_fetch_rows", side_effect=fake_fetch_rows), redirect_stdout(stdout):
            legacy.verify_remote(self.payloads, "https://invalid.example.test", "unit-test-only-not-a-secret")
        self.assertIn(
            f"VERIFIED canonical app_config key manifest MD5: {legacy.EXPECTED_KEYSET_MD5}",
            stdout.getvalue(),
        )
        self.assertIn("VERIFIED exact workbook-owned inventories: app_config=352", stdout.getvalue())

    def test_post_sync_verification_rejects_same_count_wrong_key(self):
        def fake_fetch_rows(*, table, **_kwargs):
            if table == "app_config":
                rows = [{"key": key} for key in self.keys]
                rows[0]["key"] = "tenant:extra-wrong-key"
                return rows
            if table == "tenants":
                return [{"tenant_id": row["tenant_id"]} for row in self.payloads.tenants]
            if table == "devices":
                return [{"device_id": row["device_id"]} for row in self.payloads.devices]
            if table == "tenant_services":
                return [
                    {"tenant_id": row["tenant_id"], "service": row["service"]}
                    for row in self.payloads.services
                ]
            raise AssertionError(f"Unexpected verification table: {table}")

        with patch.object(legacy, "_fetch_rows", side_effect=fake_fetch_rows):
            with self.assertRaisesRegex(RuntimeError, "missing=.*extra"):
                legacy.verify_remote(self.payloads, "https://invalid.example.test", "unit-test-only-not-a-secret")


if __name__ == "__main__":
    unittest.main()
