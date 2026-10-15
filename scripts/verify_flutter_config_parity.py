#!/usr/bin/env python3
"""Fail-closed 352-entry workbook and effective-config parity harness.

Full verification requires an authorized read-only Laravel inventory snapshot
and an authenticated staging API token. This script performs no database writes.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import export_workbook_for_laravel as exporter  # noqa: E402


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def without_version(config: dict[str, Any]) -> dict[str, Any]:
    result = dict(config)
    result.pop("version", None)
    return result


def canonical_inventory_entries(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = [
        {"key": "global", "config": manifest["global_config"]}
    ]
    entries.extend({"key": "template:" + row["id"], "config": row["config"]}
                   for row in manifest["templates"])
    entries.extend({"key": "tenant:" + row["tenant_id"], "config": row["config"]}
                   for row in manifest["tenants"])
    entries.extend({
        "key": "tenant:" + row["tenant_id"] + ":service:" + row["service"],
        "config": row["config"],
    } for row in manifest["services"])
    entries.extend({"key": "device:" + row["device_id"], "config": row["config"]}
                   for row in manifest["devices"])
    return sorted(entries, key=lambda item: item["key"])


def compare_inventory(
    expected_entries: list[dict[str, Any]], actual_snapshot: dict[str, Any]
) -> dict[str, Any]:
    actual_entries = actual_snapshot.get("entries")
    if not isinstance(actual_entries, list):
        raise ValueError("Actual inventory snapshot must contain an entries list.")
    if len(expected_entries) != 352:
        raise ValueError("Workbook-derived inventory is not exactly 352 entries.")
    if len(actual_entries) != 352:
        raise ValueError(
            "Actual inventory snapshot must contain exactly 352 entries; got "
            + str(len(actual_entries)) + "."
        )
    expected_by_key = {item["key"]: item for item in expected_entries}
    actual_by_key: dict[str, dict[str, Any]] = {}
    for entry in actual_entries:
        if not isinstance(entry, dict):
            raise ValueError("Every actual inventory entry must be an object.")
        key, config = entry.get("key"), entry.get("config")
        if not isinstance(key, str) or not key or not isinstance(config, dict):
            raise ValueError("Every inventory entry needs string key and object config.")
        if key in actual_by_key:
            raise ValueError("Duplicate actual inventory key: " + key)
        actual_by_key[key] = {"key": key, "config": config}
    missing = sorted(set(expected_by_key) - set(actual_by_key))
    extra = sorted(set(actual_by_key) - set(expected_by_key))
    changed = sorted(
        key for key in set(expected_by_key) & set(actual_by_key)
        if canonical_json(expected_by_key[key]["config"])
        != canonical_json(actual_by_key[key]["config"])
    )
    return {
        "status": "PASS" if not missing and not extra and not changed else "FAIL",
        "expected_count": len(expected_entries),
        "actual_count": len(actual_entries),
        "missing_keys": missing,
        "extra_keys": extra,
        "config_mismatch_keys": changed,
        "keyset_md5": exporter.EXPECTED_KEYSET_MD5,
    }


def build_valid_fixtures(manifest: dict[str, Any]) -> list[dict[str, str]]:
    tenants = {
        row["tenant_id"]: row for row in manifest["tenants"]
        if row.get("is_active") is True
    }
    devices_by_tenant: dict[str, list[dict[str, Any]]] = {}
    for device in manifest["devices"]:
        if device.get("active") is True and device.get("tenant_id") in tenants:
            devices_by_tenant.setdefault(device["tenant_id"], []).append(device)

    fixtures: set[tuple[str, str, str]] = set()
    for service_row in manifest["services"]:
        tenant_id = service_row["tenant_id"]
        if service_row.get("enabled") is not True or tenant_id not in tenants:
            continue
        for device in devices_by_tenant.get(tenant_id, []):
            fixtures.add((tenant_id, device["device_id"], service_row["service"]))
    result = [
        {"tenant_id": tenant, "device_id": device, "service": service}
        for tenant, device, service in sorted(fixtures)
    ]
    by_service = {
        service: sum(1 for fixture in result if fixture["service"] == service)
        for service in ("pos", "akuntansi")
    }
    for service in ("pos", "akuntansi"):
        if by_service[service] < 1:
            raise ValueError("No valid active tenant/device fixture for " + service)
    return result


def expected_effective_config(
    manifest: dict[str, Any], fixture: dict[str, str]
) -> dict[str, Any]:
    tenant_id, device_id, service = (
        fixture["tenant_id"], fixture["device_id"], fixture["service"]
    )
    tenants = {row["tenant_id"]: row for row in manifest["tenants"]}
    tenant = tenants[tenant_id]
    templates = {row["id"]: row for row in manifest["templates"]}
    if tenant.get("template_id") not in templates:
        raise ValueError("Tenant has no valid canonical template: " + tenant_id)
    services = {(row["tenant_id"], row["service"]): row for row in manifest["services"]}
    if (tenant_id, service) not in services:
        raise ValueError("Missing requested service: " + tenant_id + "/" + service)
    devices = {
        row["device_id"]: row for row in manifest["devices"]
        if row.get("tenant_id") == tenant_id
    }
    if device_id not in devices:
        raise ValueError("Device does not belong to fixture tenant: " + device_id)

    layers = [
        manifest["global_config"],
        templates[tenant["template_id"]]["config"],
        tenant["config"],
        services[(tenant_id, service)]["config"],
        devices[device_id]["config"],
    ]
    merged: dict[str, Any] = {}
    # DOC_00 canonical behavior is top-level overwrite; resolve one service only.
    for layer in layers:
        merged.update(without_version(layer))
    return merged


def fetch_effective_config(
    base_url: str, token: str, fixture: dict[str, str], timeout: float
) -> dict[str, Any]:
    endpoint = urljoin(base_url.rstrip("/") + "/", "api/v1/effective-config")
    request = Request(
        endpoint + "?" + urlencode(fixture),
        headers={"Accept": "application/json", "Authorization": "Bearer " + token},
        method="GET",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raise RuntimeError(
            "Effective-config API returned HTTP " + str(exc.code) + " for "
            + fixture["tenant_id"] + "/" + fixture["device_id"] + "/"
            + fixture["service"]
        ) from exc
    except URLError as exc:
        raise RuntimeError("Effective-config API request failed: " + str(exc.reason)) from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("effective_config"), dict):
        raise RuntimeError("API response has no effective_config object.")
    return payload["effective_config"]


def compare_effective_configs(
    manifest: dict[str, Any], base_url: str, token: str,
    *, delay_seconds: float = 0.55, timeout_seconds: float = 20,
) -> dict[str, Any]:
    fixtures = build_valid_fixtures(manifest)
    mismatches: list[dict[str, Any]] = []
    checked = {"pos": 0, "akuntansi": 0}
    last_request = 0.0
    for fixture in fixtures:
        remaining = delay_seconds - (time.monotonic() - last_request)
        if last_request and remaining > 0:
            time.sleep(remaining)
        actual = fetch_effective_config(base_url, token, fixture, timeout_seconds)
        last_request = time.monotonic()
        expected = expected_effective_config(manifest, fixture)
        checked[fixture["service"]] += 1
        if canonical_json(actual) != canonical_json(expected):
            mismatches.append({**fixture, "expected": expected, "actual": actual})
    return {
        "status": "PASS" if not mismatches else "FAIL",
        "fixture_count": len(fixtures),
        "checked_by_service": checked,
        "mismatches": mismatches,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workbook", type=Path, default=exporter.DEFAULT_WORKBOOK)
    parser.add_argument("--actual-inventory", type=Path,
                        help="Authorized read-only Laravel-side inventory snapshot JSON.")
    parser.add_argument("--base-url", help="Laravel Central API base URL for staging.")
    parser.add_argument("--token", default=os.environ.get("BERKAH_CONFIG_PARITY_TOKEN"),
                        help="Short-lived staging bearer token; alternatively set BERKAH_CONFIG_PARITY_TOKEN.")
    parser.add_argument("--delay-seconds", type=float, default=0.55)
    parser.add_argument("--timeout-seconds", type=float, default=20)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    report: dict[str, Any] = {
        "status": "NOT VERIFIED",
        "inventory_status": "NOT VERIFIED",
        "effective_config_status": "NOT VERIFIED",
        "source_workbook": str(args.workbook),
        "evidence_gaps": [],
    }
    exit_code = 2
    try:
        manifest = exporter.build_manifest(args.workbook)
        entries = canonical_inventory_entries(manifest)
        report["workbook"] = {
            "status": "PASS",
            "entry_count": len(entries),
            "counts": manifest["counts"],
            "keyset_md5": manifest["keyset_md5"],
        }
        if args.actual_inventory is None:
            report["evidence_gaps"].append(
                "Authorized Laravel-side 352-entry inventory snapshot not supplied."
            )
        else:
            try:
                actual_snapshot = json.loads(args.actual_inventory.read_text(encoding="utf-8"))
                inventory = compare_inventory(entries, actual_snapshot)
                report["inventory"] = inventory
                report["inventory_status"] = inventory["status"]
            except Exception as exc:
                report["inventory_status"] = "FAIL"
                report["inventory_error"] = str(exc)

        if not args.base_url or not args.token:
            report["evidence_gaps"].append(
                "Authenticated staging Laravel API base URL/token not supplied."
            )
        else:
            try:
                effective = compare_effective_configs(
                    manifest, args.base_url, args.token,
                    delay_seconds=args.delay_seconds,
                    timeout_seconds=args.timeout_seconds,
                )
                report["effective_config"] = effective
                report["effective_config_status"] = effective["status"]
            except Exception as exc:
                report["effective_config_status"] = "FAIL"
                report["effective_config_error"] = str(exc)

        statuses = [report["inventory_status"], report["effective_config_status"]]
        if all(status == "PASS" for status in statuses):
            report["status"] = "PASS"
            exit_code = 0
        elif any(status == "FAIL" for status in statuses):
            report["status"] = "FAIL"
            exit_code = 1
    except Exception as exc:
        report["status"] = "FAIL"
        report["error"] = str(exc)
        exit_code = 1

    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
