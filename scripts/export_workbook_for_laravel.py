#!/usr/bin/env python3
"""Validate the canonical 352-key workbook and export a Laravel import manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

from openpyxl import load_workbook

EXPECTED_SHEETS = [
    "README_PRODUCTION", "TEMPLATES", "GLOBAL", "TENANTS_MASTER",
    "DEVICES", "SERVICES", "APP_CONFIG_EXPORT",
]
EXPECTED_COUNTS = {"global": 1, "template": 3, "tenant": 100, "service": 140, "device": 108}
EXPECTED_TEMPLATES = {"BASIC", "PRO", "ENTERPRISE"}
EXPECTED_TOTAL = 352
EXPECTED_KEYSET_MD5 = "1fd3d64219ecc7c333453c20da80e295"
DEFAULT_WORKBOOK = Path(__file__).resolve().parents[1] / "config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx"


def rows(ws) -> list[dict[str, Any]]:
    values = list(ws.iter_rows(values_only=True))
    if not values:
        return []
    headers = [str(v).strip() if v is not None else "" for v in values[0]]
    output = []
    for raw in values[1:]:
        if not any(v is not None for v in raw):
            continue
        output.append({headers[i]: raw[i] for i in range(min(len(headers), len(raw))) if headers[i]})
    return output


def text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def parse_object(raw: Any, label: str) -> dict[str, Any]:
    if isinstance(raw, dict):
        value = dict(raw)
    elif isinstance(raw, str):
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{label}: invalid JSON: {exc}") from exc
    else:
        raise ValueError(f"{label}: expected JSON object")
    if not isinstance(value, dict):
        raise ValueError(f"{label}: expected JSON object")
    version = value.get("version", 1)
    if isinstance(version, bool) or not str(version).isdigit() or int(version) < 1:
        raise ValueError(f"{label}: version must be a positive integer")
    value["version"] = int(version)
    return value


def flag(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return text(value).lower() in {"true", "1", "yes", "active", "enabled"}


def build_manifest(workbook: Path) -> dict[str, Any]:
    wb = load_workbook(workbook, data_only=True, read_only=True)
    try:
        if wb.sheetnames != EXPECTED_SHEETS:
            raise ValueError(f"Unexpected sheet order/layout: {wb.sheetnames!r}")
        export_rows = rows(wb["APP_CONFIG_EXPORT"])
        by_key: dict[str, dict[str, Any]] = {}
        for row in export_rows:
            key = text(row.get("key"))
            if not key or key in by_key:
                raise ValueError(f"Empty or duplicate config key: {key!r}")
            status = text(row.get("sync_status")).upper()
            if status not in {"READY", "ACTIVE", ""}:
                raise ValueError(f"{key}: sync_status is not ready ({status})")
            by_key[key] = {"key": key, "config": parse_object(row.get("value_jsonb"), key)}

        keys = set(by_key)
        counts = {
            "global": sum(key == "global" for key in keys),
            "template": sum(key.startswith("template:") for key in keys),
            "tenant": sum(key.startswith("tenant:") and ":service:" not in key for key in keys),
            "service": sum(key.startswith("tenant:") and ":service:" in key for key in keys),
            "device": sum(key.startswith("device:") for key in keys),
        }
        if counts != EXPECTED_COUNTS or len(keys) != EXPECTED_TOTAL:
            raise ValueError(f"Expected {EXPECTED_COUNTS} / 352 keys, got {counts} / {len(keys)}")
        key_hash = hashlib.md5("\n".join(sorted(keys)).encode("utf-8")).hexdigest()
        if key_hash != EXPECTED_KEYSET_MD5:
            raise ValueError(f"Canonical keyset MD5 mismatch: {key_hash}")

        template_rows = rows(wb["TEMPLATES"])
        template_ids = {text(r.get("template_id") or r.get("template")).upper() for r in template_rows}
        if len(template_rows) != 3 or template_ids != EXPECTED_TEMPLATES:
            raise ValueError(f"Expected BASIC/PRO/ENTERPRISE templates, got {sorted(template_ids)}")
        templates = [
            {"id": template_id, "config": by_key[f"template:{template_id}"]["config"]}
            for template_id in sorted(EXPECTED_TEMPLATES)
        ]

        tenant_rows = rows(wb["TENANTS_MASTER"])
        tenants, tenant_ids = [], set()
        for row in tenant_rows:
            tenant_id = text(row.get("tenant_id"))
            template_id = text(row.get("template_id") or row.get("effective_template")).upper()
            if not tenant_id or tenant_id in tenant_ids:
                raise ValueError(f"Empty/duplicate tenant: {tenant_id!r}")
            if template_id not in EXPECTED_TEMPLATES:
                raise ValueError(f"{tenant_id}: unsupported template {template_id!r}")
            key = f"tenant:{tenant_id}"
            if key not in by_key:
                raise ValueError(f"{tenant_id}: missing workbook key {key}")
            tenant_ids.add(tenant_id)
            tenants.append({
                "tenant_id": tenant_id, "template_id": template_id,
                "config": by_key[key]["config"],
                "name": text(row.get("nama_toko")),
            })
        if len(tenants) != EXPECTED_COUNTS["tenant"]:
            raise ValueError(f"TENANTS_MASTER must contain 100 tenant rows, got {len(tenants)}")

        service_rows = rows(wb["SERVICES"])
        services, service_pairs = [], set()
        for row in service_rows:
            tenant_id = text(row.get("tenant_id"))
            service = text(row.get("service")).lower()
            pair = (tenant_id, service)
            if tenant_id not in tenant_ids or service not in {"pos", "akuntansi"} or pair in service_pairs:
                raise ValueError(f"Invalid or duplicate service mapping: {pair}")
            service_pairs.add(pair)
            key = text(row.get("app_config_key")) or f"tenant:{tenant_id}:service:{service}"
            if key not in by_key:
                raise ValueError(f"Service {pair} references missing config key {key}")
            services.append({
                "tenant_id": tenant_id, "service": service,
                "enabled": flag(row.get("enabled")), "config": by_key[key]["config"],
            })
        if len(services) != EXPECTED_COUNTS["service"]:
            raise ValueError(f"SERVICES must contain 140 rows, got {len(services)}")

        devices, device_ids = [], set()
        for row in rows(wb["DEVICES"]):
            device_id, tenant_id = text(row.get("device_id")), text(row.get("tenant_id"))
            key = text(row.get("app_config_key")) or f"device:{device_id}"
            if not device_id or device_id in device_ids or tenant_id not in tenant_ids or key not in by_key:
                raise ValueError(f"Invalid device mapping: {device_id}/{tenant_id}/{key}")
            device_ids.add(device_id)
            devices.append({
                "device_id": device_id, "tenant_id": tenant_id,
                "active": flag(row.get("is_active")), "config": by_key[key]["config"],
            })
        if len(devices) != EXPECTED_COUNTS["device"]:
            raise ValueError(f"DEVICES must contain 108 rows, got {len(devices)}")

        return {
            "schema_version": 1,
            "source_workbook": workbook.name,
            "counts": counts,
            "keyset_md5": key_hash,
            "global_config": by_key["global"]["config"],
            "templates": templates,
            "tenants": tenants,
            "services": services,
            "devices": devices,
        }
    finally:
        wb.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK)
    parser.add_argument("--output", type=Path, default=Path("build/central-config-import.json"))
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    try:
        manifest = build_manifest(args.workbook)
        print(f"PASS: {sum(manifest['counts'].values())} keys; counts={manifest['counts']}; keyset_md5={manifest['keyset_md5']}")
        if not args.validate_only:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"Wrote import manifest: {args.output}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
