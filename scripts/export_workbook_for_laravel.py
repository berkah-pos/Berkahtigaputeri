#!/usr/bin/env python3
"""Validate the canonical 352-key workbook and export an offline Laravel import manifest."""

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
EXPECTED_TOTAL = sum(EXPECTED_COUNTS.values())
EXPECTED_KEYSET_MD5 = "1fd3d64219ecc7c333453c20da80e295"
DEFAULT_WORKBOOK = Path(__file__).resolve().parents[1] / "config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx"


def row_dicts(ws) -> list[dict[str, Any]]:
    values = list(ws.iter_rows(values_only=True))
    if not values:
        return []
    headers = [str(value).strip() if value is not None else "" for value in values[0]]
    rows: list[dict[str, Any]] = []
    for raw in values[1:]:
        if not any(value is not None for value in raw):
            continue
        rows.append({headers[i]: raw[i] for i in range(min(len(headers), len(raw))) if headers[i]})
    return rows


def text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return text(value).lower() in {"true", "1", "yes", "active", "enabled"}


def parse_value(raw: Any, key: str) -> dict[str, Any]:
    if isinstance(raw, dict):
        parsed = raw
    elif isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{key}: value_jsonb is not valid JSON: {exc}") from exc
    else:
        raise ValueError(f"{key}: value_jsonb must be a JSON object string")
    if not isinstance(parsed, dict):
        raise ValueError(f"{key}: value_jsonb must decode to an object")
    parsed = dict(parsed)
    version = parsed.get("version", 1)
    if isinstance(version, bool) or not str(version).isdigit() or int(version) < 1:
        raise ValueError(f"{key}: version must be a positive integer")
    parsed["version"] = int(version)
    return parsed


def canonical_manifest_sha256(manifest: dict[str, Any]) -> str:
    """Return a stable digest of the manifest payload, excluding its digest field."""
    payload = {key: value for key, value in manifest.items() if key != "manifest_sha256"}
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def build_manifest(workbook: Path) -> dict[str, Any]:
    wb = load_workbook(workbook, data_only=True, read_only=True)
    try:
        if wb.sheetnames != EXPECTED_SHEETS:
            raise ValueError(
                f"Unexpected sheet order/layout: got {wb.sheetnames!r}, expected {EXPECTED_SHEETS!r}"
            )
        templates = row_dicts(wb["TEMPLATES"])
        tenant_rows = row_dicts(wb["TENANTS_MASTER"])
        device_rows = row_dicts(wb["DEVICES"])
        service_rows = row_dicts(wb["SERVICES"])
        export_rows = row_dicts(wb["APP_CONFIG_EXPORT"])

        by_key: dict[str, dict[str, Any]] = {}
        for row in export_rows:
            key = text(row.get("key"))
            if not key:
                raise ValueError("APP_CONFIG_EXPORT contains an empty key")
            if key in by_key:
                raise ValueError(f"Duplicate canonical config key: {key}")
            if text(row.get("sync_status")).upper() not in {"READY", "ACTIVE", ""}:
                raise ValueError(f"{key}: sync_status is not ready")
            by_key[key] = {
                "key": key,
                "config": parse_value(row.get("value_jsonb"), key),
            }

        keys = set(by_key)
        counts = {
            "global": sum(key == "global" for key in keys),
            "template": sum(key.startswith("template:") for key in keys),
            "tenant": sum(key.startswith("tenant:") and ":service:" not in key for key in keys),
            "service": sum(key.startswith("tenant:") and ":service:" in key for key in keys),
            "device": sum(key.startswith("device:") for key in keys),
        }
        if counts != EXPECTED_COUNTS or len(keys) != EXPECTED_TOTAL:
            raise ValueError(f"Expected {EXPECTED_COUNTS} / {EXPECTED_TOTAL} keys, got {counts} / {len(keys)}")
        unknown = [key for key in keys if not (
            key == "global" or key.startswith("template:") or key.startswith("tenant:") or key.startswith("device:")
        )]
        if unknown:
            raise ValueError(f"Unknown canonical key prefixes: {sorted(unknown)[:10]}")

        keyset_md5 = hashlib.md5("\n".join(sorted(keys)).encode("utf-8")).hexdigest()
        if keyset_md5 != EXPECTED_KEYSET_MD5:
            raise ValueError(f"Keyset hash mismatch: {keyset_md5}")

        template_ids = {text(row.get("template_id") or row.get("template")).upper() for row in templates}
        if template_ids != EXPECTED_TEMPLATES or len(templates) != EXPECTED_COUNTS["template"]:
            raise ValueError(f"Template inventory mismatch: {sorted(template_ids)}")

        tenants: list[dict[str, Any]] = []
        tenant_ids: set[str] = set()
        for row in tenant_rows:
            tenant_id = text(row.get("tenant_id"))
            template_id = text(row.get("template_id")).upper()
            if not tenant_id or tenant_id in tenant_ids:
                raise ValueError(f"Empty/duplicate tenant_id: {tenant_id!r}")
            if template_id not in EXPECTED_TEMPLATES:
                raise ValueError(f"{tenant_id}: invalid template_id {template_id!r}")
            key = f"tenant:{tenant_id}"
            if key not in by_key:
                raise ValueError(f"{tenant_id}: missing {key} in APP_CONFIG_EXPORT")
            tenant_ids.add(tenant_id)
            tenants.append({"tenant_id": tenant_id, "template_id": template_id, "config": by_key[key]["config"]})
        if len(tenants) != EXPECTED_COUNTS["tenant"]:
            raise ValueError(f"TENANTS_MASTER must contain 100 tenants; got {len(tenants)}")

        services: list[dict[str, Any]] = []
        service_pairs: set[tuple[str, str]] = set()
        for row in service_rows:
            tenant_id = text(row.get("tenant_id"))
            service = text(row.get("service")).lower()
            if tenant_id not in tenant_ids or service not in {"pos", "akuntansi"}:
                raise ValueError(f"Invalid SERVICES mapping: {tenant_id}/{service}")
            pair = (tenant_id, service)
            if pair in service_pairs:
                raise ValueError(f"Duplicate service mapping: {pair}")
            service_pairs.add(pair)
            key = text(row.get("app_config_key")) or f"tenant:{tenant_id}:service:{service}"
            if key not in by_key:
                raise ValueError(f"SERVICE row {pair} references missing key {key}")
            services.append({"tenant_id": tenant_id, "service": service, "enabled": bool_value(row.get("enabled")), "config": by_key[key]["config"]})
        if len(services) != EXPECTED_COUNTS["service"]:
            raise ValueError(f"SERVICES must contain 140 rows; got {len(services)}")

        devices: list[dict[str, Any]] = []
        seen_devices: set[str] = set()
        for row in device_rows:
            device_id = text(row.get("device_id"))
            tenant_id = text(row.get("tenant_id"))
            key = text(row.get("app_config_key")) or f"device:{device_id}"
            if not device_id or device_id in seen_devices:
                raise ValueError(f"Empty/duplicate device id: {device_id!r}")
            if tenant_id not in tenant_ids or key not in by_key:
                raise ValueError(f"Invalid device registry/config mapping: {device_id}/{tenant_id}/{key}")
            seen_devices.add(device_id)
            devices.append({
                "device_id": device_id,
                "tenant_id": tenant_id,
                "active": bool_value(row.get("is_active")),
                "config": by_key[key]["config"],
            })
        if len(devices) != EXPECTED_COUNTS["device"]:
            raise ValueError(f"DEVICES must contain 108 rows; got {len(devices)}")

        template_payload = [
            {"id": template_id, "config": by_key[f"template:{template_id}"]["config"]}
            for template_id in sorted(EXPECTED_TEMPLATES)
        ]
        global_config = by_key["global"]["config"]
        if len(services) != counts["service"] or len(devices) != counts["device"]:
            raise ValueError("Relational projection counts differ from canonical key inventory")

        manifest = {
            "schema_version": 1,
            "source_workbook": workbook.name,
            "counts": counts,
            "keyset_md5": keyset_md5,
            "global_config": global_config,
            "templates": template_payload,
            "tenants": tenants,
            "services": services,
            "devices": devices,
        }
        manifest["manifest_sha256"] = canonical_manifest_sha256(manifest)
        return manifest
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
        print(
            f"PASS: {sum(manifest['counts'].values())} keys; "
            f"counts={manifest['counts']}; keyset_md5={manifest['keyset_md5']}; "
            f"manifest_sha256={manifest['manifest_sha256']}"
        )
        if args.validate_only:
            return 0
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote local import manifest: {args.output}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
