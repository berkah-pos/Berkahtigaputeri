#!/usr/bin/env python3
"""Regression tests for the canonical workbook, export manifest, and financial schema."""

from __future__ import annotations

from datetime import date, datetime
import re
import sys
import unittest
from pathlib import Path
from typing import Any

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import export_workbook_for_laravel as exporter  # noqa: E402


def normalize(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(value or "").strip().lower()).strip("_")


def workbook_rows(path: Path, sheet: str) -> list[dict[str, Any]]:
    book = load_workbook(path, data_only=True, read_only=True)
    try:
        values = list(book[sheet].iter_rows(values_only=True))
        headers = [normalize(item) for item in values[0]] if values else []
        result = []
        for row in values[1:]:
            if not any(value is not None and str(value).strip() for value in row):
                continue
            result.append({headers[i]: row[i] for i in range(min(len(headers), len(row)) if headers else 0) if headers[i]})
        return result
    finally:
        book.close()


def get(row: dict[str, Any], *names: str) -> Any:
    for name in names:
        value = row.get(normalize(name))
        if value is not None and str(value).strip() != "":
            return value
    return None


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and value in (0, 1):
        return bool(value)
    value = str(value).strip().lower()
    if value in {"true", "1", "yes", "y", "active", "enabled", "aktif"}:
        return True
    if value in {"false", "0", "no", "n", "inactive", "disabled", "nonaktif", "suspended"}:
        return False
    raise AssertionError(f"Invalid boolean in canonical workbook: {value!r}")


def as_date(value: Any) -> str | None:
    if value is None or str(value).strip() == "":
        return None
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    try:
        return datetime.fromisoformat(str(value).strip().replace("Z", "+00:00")).isoformat(sep=" ")
    except ValueError:
        return date.fromisoformat(str(value).strip()).isoformat()


class CanonicalWorkbookContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workbook = exporter.DEFAULT_WORKBOOK
        cls.manifest = exporter.build_manifest(cls.workbook)

    def test_352_entry_breakdown_templates_and_canonical_keyset_md5(self) -> None:
        self.assertEqual("FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx", self.manifest["source_workbook"])
        self.assertEqual({"global": 1, "template": 3, "tenant": 100, "service": 140, "device": 108}, self.manifest["counts"])
        self.assertEqual(352, sum(self.manifest["counts"].values()))
        self.assertEqual("1fd3d64219ecc7c333453c20da80e295", self.manifest["keyset_md5"])
        self.assertEqual({"BASIC", "PRO", "ENTERPRISE"}, {row["id"] for row in self.manifest["templates"]})
        self.assertEqual((100, 140, 108), (len(self.manifest["tenants"]), len(self.manifest["services"]), len(self.manifest["devices"])))

    def test_tenant_store_name_boolean_expiry_and_max_users_map_correctly(self) -> None:
        source = {str(get(row, "tenant_id")).strip(): row for row in workbook_rows(self.workbook, "TENANTS_MASTER")}
        target = {row["tenant_id"]: row for row in self.manifest["tenants"]}
        self.assertEqual(set(source), set(target))
        for tenant_id, row in source.items():
            actual = target[tenant_id]
            store = get(row, "store_name", "nama_toko", "name", "tenant_name")
            if store is not None:
                self.assertEqual(str(store).strip(), actual["store_name"], tenant_id)
            max_users = get(row, "max_users", "max_user", "maksimal_user", "batas_user")
            if max_users is not None:
                self.assertEqual(int(max_users), actual["max_users"], tenant_id)
            expiry = get(row, "expires_at", "expiry_date", "subscription_expires_at", "tanggal_kedaluwarsa", "tanggal_berakhir")
            if expiry is not None:
                self.assertEqual(as_date(expiry), actual["expires_at"], tenant_id)
            active = get(row, "is_active", "active", "enabled")
            if active is not None:
                self.assertEqual(as_bool(active), actual["is_active"], tenant_id)

    def test_service_and_device_flags_platforms_and_hardware_mode(self) -> None:
        services = {(row["tenant_id"], row["service"]): row for row in self.manifest["services"]}
        for row in workbook_rows(self.workbook, "SERVICES"):
            key = (str(get(row, "tenant_id")).strip(), str(get(row, "service")).strip().lower())
            self.assertIn(key, services)
            self.assertEqual(as_bool(get(row, "enabled", "is_enabled")), services[key]["enabled"])
        devices = {row["device_id"]: row for row in self.manifest["devices"]}
        for row in workbook_rows(self.workbook, "DEVICES"):
            device_id = str(get(row, "device_id")).strip()
            target = devices[device_id]
            self.assertEqual(as_bool(get(row, "is_active", "active", "enabled")), target["active"])
            for field, aliases in (
                ("platform", ("platform", "device_platform", "os_platform")),
                ("hardware_mode", ("hardware_mode", "hardware", "mode_hardware")),
                ("device_model", ("device_model", "model", "hardware_model")),
            ):
                raw = get(row, *aliases)
                if raw is not None:
                    expected = str(raw).strip()
                    if field in ("platform", "hardware_mode"):
                        expected = expected.lower()
                    self.assertEqual(expected, target[field], device_id)

    def test_unknown_boolean_values_fail_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "unrecognized boolean"):
            exporter.flag("perhaps", "test-fixture")

    def test_manifests_are_deterministic_and_money_never_uses_binary_float(self) -> None:
        self.assertEqual(self.manifest, exporter.build_manifest(self.workbook))
        php_files = list((ROOT / "database/migrations").rglob("*.php")) + list((ROOT / "app/Models").rglob("*.php"))
        issues = []
        for path in php_files:
            text = path.read_text(encoding="utf-8")
            if re.search(r"->\s*(?:float|double|doublePrecision)\s*\(", text, re.IGNORECASE):
                issues.append(str(path.relative_to(ROOT)))
            if re.search(r"""['"][A-Za-z_][A-Za-z0-9_]*['"]\s*=>\s*['"](?:float|double)['"]""", text, re.IGNORECASE):
                issues.append(str(path.relative_to(ROOT)) + " (cast)")
        self.assertEqual([], issues)
        monetary = (ROOT / "database/migrations/tenant/2026_10_15_000001_create_tenant_pos_tables.php").read_text(encoding="utf-8")
        for field in ("price", "unit_cost", "subtotal", "tax_amount", "total_amount", "unit_price", "line_total", "debit", "credit"):
            self.assertRegex(monetary, rf"->decimal\('{field}',\s*18,\s*2\)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
