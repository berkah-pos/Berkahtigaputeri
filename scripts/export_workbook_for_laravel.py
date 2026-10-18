#!/usr/bin/env python3
"""Validate the canonical 352-key workbook and export an offline Laravel import manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from io import BytesIO
from pathlib import Path
from typing import Any, Iterable

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


def normalize_header(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(value).strip().lower()).strip("_") if value is not None else ""


def row_dicts(ws) -> list[dict[str, Any]]:
    values = list(ws.iter_rows(values_only=True))
    if not values:
        return []
    headers = [normalize_header(value) for value in values[0]]
    nonempty_headers = [header for header in headers if header]
    if len(nonempty_headers) != len(set(nonempty_headers)):
        raise ValueError(f"{ws.title}: duplicate normalized column headers")
    rows: list[dict[str, Any]] = []
    for raw in values[1:]:
        if not any(value is not None for value in raw):
            continue
        rows.append({headers[i]: raw[i] for i in range(min(len(headers), len(raw))) if headers[i]})
    return rows


def text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def normalized_identifier(value: Any, label: str, *, uppercase: bool = False) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"{label}: identifier must be a non-empty, already-trimmed string")
    pattern = r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$" if uppercase else r"^[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*$"
    if not re.fullmatch(pattern, value):
        raise ValueError(f"{label}: identifier is not in canonical normalized form: {value!r}")
    return value


def bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None or text(value) == "":
        raise ValueError("Required boolean flag is empty")
    normalized = text(value).lower()
    if normalized in {"true", "1", "yes", "active", "enabled"}:
        return True
    if normalized in {"false", "0", "no", "inactive", "disabled"}:
        return False
    raise ValueError(f"Invalid boolean flag: {value!r}")


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




def _assert_exact_inventory(
    label: str,
    expected: Iterable[Any],
    actual: Iterable[Any],
    *,
    exception_type: type[Exception] = RuntimeError,
) -> None:
    expected_set = set(expected)
    actual_set = set(actual)
    missing = expected_set - actual_set
    extra = actual_set - expected_set
    if missing or extra:
        missing_sample = sorted(str(value) for value in missing)[:10]
        extra_sample = sorted(str(value) for value in extra)[:10]
        raise exception_type(
            f"Exact inventory mismatch for {label}; "
            f"missing={missing_sample}; extra={extra_sample}"
        )


def canonical_manifest_bytes(manifest: dict[str, Any]) -> bytes:
    """Return the one canonical UTF-8 representation used for hashing and export."""
    encoded = json.dumps(
        manifest,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )
    return (encoded + "\n").encode("utf-8")


def _atomic_write_bytes(destination: Path, content: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=f".{destination.name}.",
            suffix=".tmp",
            dir=destination.parent,
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, destination)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def write_manifest(manifest: dict[str, Any], output: Path) -> str:
    """Write canonical manifest bytes and a detached SHA-256 checksum sidecar."""
    output = Path(output)
    payload = canonical_manifest_bytes(manifest)
    digest = hashlib.sha256(payload).hexdigest()
    _atomic_write_bytes(output, payload)
    checksum_path = output.with_name(output.name + ".sha256")
    _atomic_write_bytes(checksum_path, f"{digest}  {output.name}\n".encode("ascii"))
    return digest


def build_manifest(workbook: Path) -> dict[str, Any]:
    workbook_bytes = workbook.read_bytes()
    source_sha256 = hashlib.sha256(workbook_bytes).hexdigest()
    wb = load_workbook(BytesIO(workbook_bytes), data_only=True, read_only=True)
    try:
        if wb.sheetnames != EXPECTED_SHEETS:
            raise ValueError(
                f"Unexpected sheet order/layout: got {wb.sheetnames!r}, expected {EXPECTED_SHEETS!r}"
            )
        templates = row_dicts(wb["TEMPLATES"])
        tenant_rows = row_dicts(wb["TENANTS_MASTER"])
        device_rows = row_dicts(wb["DEVICES"])
        service_rows = row_dicts(wb["SERVICES"])
        global_rows = row_dicts(wb["GLOBAL"])
        readme_rows = row_dicts(wb["README_PRODUCTION"])
        export_rows = row_dicts(wb["APP_CONFIG_EXPORT"])

        if not readme_rows:
            raise ValueError("README_PRODUCTION must contain a header row and at least one documented row")
        if not global_rows:
            raise ValueError("GLOBAL sheet must contain a header row and at least one configuration row")
        required_headers = {
            "TEMPLATES": ({"template_id", "template"},),
            "TENANTS_MASTER": ({"tenant_id"}, {"template_id"}),
            "DEVICES": ({"device_id"}, {"tenant_id"}, {"is_active"}),
            "SERVICES": ({"tenant_id"}, {"service"}, {"enabled"}),
            "APP_CONFIG_EXPORT": ({"key"}, {"type"}, {"value_jsonb"}, {"sync_status"}),
        }
        for sheet_name, header_alternatives in required_headers.items():
            headers = {normalize_header(value) for value in next(wb[sheet_name].iter_rows(values_only=True))}
            for alternatives in header_alternatives:
                if not (headers & alternatives):
                    raise ValueError(f"{sheet_name} is missing required header from {sorted(alternatives)}")

        by_key: dict[str, dict[str, Any]] = {}
        for row in export_rows:
            raw_key = row.get("key")
            key = text(raw_key)
            if not key:
                raise ValueError("APP_CONFIG_EXPORT contains an empty key")
            if not isinstance(raw_key, str) or raw_key != key:
                raise ValueError(f"APP_CONFIG_EXPORT key is not normalized: {raw_key!r}")
            if key in by_key:
                raise ValueError(f"Duplicate canonical config key: {key}")
            if text(row.get("sync_status")).upper() not in {"READY", "ACTIVE", ""}:
                raise ValueError(f"{key}: sync_status is not ready")
            key_type = text(row.get("type")).lower()
            if key == "global":
                expected_type = "global"
            elif key.startswith("template:"):
                expected_type = "template"
            elif ":service:" in key:
                expected_type = "service"
            elif key.startswith("tenant:"):
                expected_type = "tenant"
            elif key.startswith("device:"):
                expected_type = "device"
            else:
                raise ValueError(f"Unknown canonical config key: {key!r}")
            if key_type != expected_type:
                raise ValueError(f"{key}: APP_CONFIG_EXPORT type={key_type!r} does not match expected {expected_type!r}")
            by_key[key] = {
                "key": key,
                "config": parse_value(row.get("value_jsonb"), key),
            }

        keys = set(by_key)
        for key in keys:
            if key == "global":
                continue
            valid = (
                re.fullmatch(r"template:(BASIC|PRO|ENTERPRISE)", key)
                or re.fullmatch(r"tenant:[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*", key)
                or re.fullmatch(r"tenant:[a-z][a-z0-9]*(?:_[a-z0-9]+)*:service:(pos|akuntansi)", key)
                or re.fullmatch(r"device:[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*", key)
            )
            if not valid:
                raise ValueError(f"Non-canonical or malformed configuration key: {key!r}")
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
        template_ids = {
            normalized_identifier(row.get("template_id") or row.get("template"), "TEMPLATES.template_id", uppercase=True)
            for row in templates
        }
        if template_ids != EXPECTED_TEMPLATES or len(templates) != EXPECTED_COUNTS["template"]:
            raise ValueError(f"Template inventory mismatch: {sorted(template_ids)}")

        tenants: list[dict[str, Any]] = []
        tenant_ids: set[str] = set()
        for row in tenant_rows:
            tenant_id = normalized_identifier(row.get("tenant_id"), "TENANTS_MASTER.tenant_id")
            raw_template_id = row.get("template_id")
            template_id = text(raw_template_id)
            if raw_template_id != template_id or template_id not in EXPECTED_TEMPLATES:
                raise ValueError(f"{tenant_id}: template_id must be a canonical uppercase template ID")
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
            tenant_id = normalized_identifier(row.get("tenant_id"), "SERVICES.tenant_id")
            raw_service = row.get("service")
            service = text(raw_service)
            if raw_service != service or tenant_id not in tenant_ids or service not in {"pos", "akuntansi"}:
                raise ValueError(f"Invalid SERVICES mapping: {tenant_id}/{service}")
            pair = (tenant_id, service)
            if pair in service_pairs:
                raise ValueError(f"Duplicate service mapping: {pair}")
            service_pairs.add(pair)
            expected_key = f"tenant:{tenant_id}:service:{service}"
            key = text(row.get("app_config_key")) or expected_key
            if key != expected_key:
                raise ValueError(f"SERVICE row {pair} must map to its exact canonical key {expected_key}")
            if key not in by_key:
                raise ValueError(f"SERVICE row {pair} references missing key {key}")
            services.append({"tenant_id": tenant_id, "service": service, "enabled": bool_value(row.get("enabled")), "config": by_key[key]["config"]})
        if len(services) != EXPECTED_COUNTS["service"]:
            raise ValueError(f"SERVICES must contain 140 rows; got {len(services)}")

        devices: list[dict[str, Any]] = []
        seen_devices: set[str] = set()
        for row in device_rows:
            device_id = normalized_identifier(row.get("device_id"), "DEVICES.device_id")
            tenant_id = normalized_identifier(row.get("tenant_id"), "DEVICES.tenant_id")
            expected_key = f"device:{device_id}"
            key = text(row.get("app_config_key")) or expected_key
            if key != expected_key:
                raise ValueError(f"Device {device_id} must map to its exact canonical key {expected_key}")
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

        expected_keys = {"global"}
        expected_keys.update(f"template:{template_id}" for template_id in EXPECTED_TEMPLATES)
        expected_keys.update(f"tenant:{tenant_id}" for tenant_id in tenant_ids)
        expected_keys.update(f"tenant:{tenant_id}:service:{service}" for tenant_id, service in service_pairs)
        expected_keys.update(f"device:{device_id}" for device_id in seen_devices)
        _assert_exact_inventory(
            "APP_CONFIG_EXPORT versus relational sheet scopes",
            expected_keys,
            keys,
            exception_type=ValueError,
        )
        if keyset_md5 != EXPECTED_KEYSET_MD5:
            raise ValueError(f"Keyset hash mismatch: {keyset_md5}")

        tenants.sort(key=lambda row: row["tenant_id"])
        services.sort(key=lambda row: (row["tenant_id"], row["service"]))
        devices.sort(key=lambda row: row["device_id"])

        template_payload = [
            {"id": template_id, "config": by_key[f"template:{template_id}"]["config"]}
            for template_id in sorted(EXPECTED_TEMPLATES)
        ]
        global_config = by_key["global"]["config"]
        if len(services) != counts["service"] or len(devices) != counts["device"]:
            raise ValueError("Relational projection counts differ from canonical key inventory")

        return {
            "schema_version": 1,
            "source_workbook": workbook.name,
            "source_sha256": source_sha256,
            "counts": counts,
            "keyset_md5": keyset_md5,
            "global_config": global_config,
            "templates": template_payload,
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
        encoded_manifest = canonical_manifest_bytes(manifest)
        manifest_sha256 = hashlib.sha256(encoded_manifest).hexdigest()
        print(
            f"PASS: {sum(manifest['counts'].values())} keys; "
            f"counts={manifest['counts']}; keyset_md5={manifest['keyset_md5']}; "
            f"source_sha256={manifest['source_sha256']}; manifest_sha256={manifest_sha256}"
        )
        if args.validate_only:
            return 0
        actual_digest = write_manifest(manifest, args.output)
        if actual_digest != manifest_sha256:
            raise RuntimeError("Manifest digest changed between validation and writing.")
        print(
            f"Wrote local import manifest: {args.output}; "
            f"SHA-256={actual_digest}; checksum={args.output.name}.sha256"
        )
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
