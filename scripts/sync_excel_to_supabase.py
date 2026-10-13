#!/usr/bin/env python3
"""Validate and sync the FINAL Pos workbook as a versioned administrative replacement.

Workbook parsing and relational projections remain in sync_excel_to_supabase_legacy.
Existing app_config rows are replaced only through update_app_config_atomic(), so a
successful replacement always increments the live database version by exactly one.
Missing canonical rows bootstrap at version 1.

Normal mode is fail-closed on a version conflict. --force-version is an explicit
administrative override for workbook replacement: after SQLSTATE 40001 it refreshes
the latest live version and retries the atomic RPC. It never writes a caller-chosen
version and never disables the database compare-and-swap check.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any

import requests

import sync_excel_to_supabase_legacy as legacy

REQUEST_TIMEOUT_SECONDS = legacy.REQUEST_TIMEOUT_SECONDS
FORCE_RETRY_LIMIT = 5


class VersionConflictError(RuntimeError):
    """Raised when update_app_config_atomic returns SQLSTATE 40001."""


def _rpc_headers(service_key: str) -> dict[str, str]:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "berkahtigaputeri-final-pos-sync/6.1",
    }


def _positive_version(value: Any, *, key: str) -> int:
    if not isinstance(value, dict):
        raise RuntimeError(f"app_config {key} value must be a JSON object")
    raw = value.get("version")
    if isinstance(raw, bool):
        raise RuntimeError(f"app_config {key} has invalid version {raw!r}")
    try:
        version = int(raw)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"app_config {key} has missing/invalid version {raw!r}") from exc
    if version < 1 or str(raw).strip() not in {str(version), f"{version}.0"}:
        raise RuntimeError(f"app_config {key} has invalid version {raw!r}")
    return version


def _error_payload(response: requests.Response) -> tuple[str, str]:
    try:
        payload = response.json()
    except ValueError:
        payload = None
    if isinstance(payload, dict):
        code = str(payload.get("code") or "")
        message = str(payload.get("message") or payload.get("details") or response.text)
        return code, message.strip().replace("\n", " ")[:1000]
    return "", response.text.strip().replace("\n", " ")[:1000]


def _atomic_update(
    *,
    key: str,
    new_value: dict[str, Any],
    expected_version: int,
    url: str,
    service_key: str,
) -> dict[str, Any]:
    response = requests.post(
        f"{url.rstrip('/')}/rest/v1/rpc/update_app_config_atomic",
        headers=_rpc_headers(service_key),
        json={
            "p_key": key,
            "p_new_value": new_value,
            "p_expected_version": expected_version,
        },
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if not response.ok:
        code, detail = _error_payload(response)
        if code == "40001":
            raise VersionConflictError(
                f"Atomic app_config version conflict for {key}: {detail}"
            )
        raise RuntimeError(
            f"Atomic app_config update failed for {key}: "
            f"HTTP {response.status_code}: {detail}"
        )

    data = response.json()
    if isinstance(data, list) and len(data) == 1:
        data = data[0]
    if not isinstance(data, dict):
        raise RuntimeError(f"Unexpected atomic RPC response for {key}")

    version = _positive_version(data, key=key)
    if version != expected_version + 1:
        raise RuntimeError(
            f"Atomic RPC returned wrong version for {key}: "
            f"expected {expected_version + 1}, got {version}"
        )
    return data


def _bootstrap_insert(
    *,
    key: str,
    new_value: dict[str, Any],
    url: str,
    service_key: str,
) -> None:
    # The canonical RPC is deliberately UPDATE-only. A genuinely missing key may
    # be bootstrapped once at version 1; every subsequent replacement is atomic.
    value = dict(new_value)
    value["version"] = 1
    response = requests.post(
        f"{url.rstrip('/')}/rest/v1/app_config",
        headers={
            **_rpc_headers(service_key),
            "Prefer": "return=minimal",
        },
        json={"key": key, "value": value},
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if not response.ok:
        _, detail = _error_payload(response)
        raise RuntimeError(
            f"Bootstrap app_config insert failed for {key}: "
            f"HTTP {response.status_code}: {detail}"
        )


def _fetch_current_value(
    *,
    key: str,
    url: str,
    service_key: str,
) -> dict[str, Any]:
    response = requests.get(
        f"{url.rstrip('/')}/rest/v1/app_config",
        params={"select": "key,value", "key": f"eq.{key}", "limit": "1"},
        headers={
            **_rpc_headers(service_key),
            "Content-Type": "application/json",
        },
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if not response.ok:
        _, detail = _error_payload(response)
        raise RuntimeError(
            f"Cannot refresh app_config version for {key}: "
            f"HTTP {response.status_code}: {detail}"
        )
    data = response.json()
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise RuntimeError(f"Expected exactly one live app_config row for {key}")
    value = data[0].get("value")
    if not isinstance(value, dict):
        raise RuntimeError(f"app_config {key} value must be a JSON object")
    return value


def _sync_app_config_atomic(
    rows: list[dict[str, Any]],
    *,
    url: str,
    service_key: str,
    force_version: bool,
) -> None:
    remote_rows = legacy._fetch_rows(
        table="app_config",
        select="key,value",
        url=url,
        service_key=service_key,
    )
    remote = {
        str(row.get("key")): row
        for row in remote_rows
        if row.get("key") is not None
    }

    updated = 0
    inserted = 0
    forced_retries = 0

    for payload in rows:
        key = str(payload["key"])
        new_value = dict(payload["value"])
        new_value.pop("version", None)
        current = remote.get(key)
        if current is None:
            _bootstrap_insert(
                key=key,
                new_value=new_value,
                url=url,
                service_key=service_key,
            )
            remote[key] = {"key": key, "value": {**new_value, "version": 1}}
            inserted += 1
            continue

        expected_version = _positive_version(current.get("value"), key=key)
        retries = 0
        while True:
            try:
                stored = _atomic_update(
                    key=key,
                    new_value=new_value,
                    expected_version=expected_version,
                    url=url,
                    service_key=service_key,
                )
                remote[key] = {"key": key, "value": stored}
                updated += 1
                break
            except VersionConflictError:
                if not force_version:
                    raise
                retries += 1
                forced_retries += 1
                if retries > FORCE_RETRY_LIMIT:
                    raise RuntimeError(
                        f"--force-version retry limit exceeded for {key}; "
                        "another writer is continuously changing the row"
                    )
                live_value = _fetch_current_value(
                    key=key,
                    url=url,
                    service_key=service_key,
                )
                expected_version = _positive_version(live_value, key=key)
                print(
                    f"FORCE-VERSION refresh {key}: retry with live version "
                    f"{expected_version}"
                )

    mode = "force-version" if force_version else "compare-and-swap"
    print(
        "VERSIONED administrative replacement: "
        f"mode={mode} atomic_updates={updated} "
        f"bootstrap_inserts={inserted} forced_retries={forced_retries}"
    )


def _verify_versions(
    payloads: legacy.WorkbookPayloads,
    *,
    url: str,
    service_key: str,
) -> None:
    rows = legacy._fetch_rows(
        table="app_config",
        select="key,value",
        url=url,
        service_key=service_key,
    )
    by_key = {str(row.get("key")): row for row in rows if row.get("key") is not None}
    for payload in payloads.app_config:
        key = str(payload["key"])
        row = by_key.get(key)
        if row is None:
            raise RuntimeError(f"Post-sync app_config row missing: {key}")
        _positive_version(row.get("value"), key=key)
    print(f"VERIFIED positive versions on {len(payloads.app_config)} canonical app_config rows")


def sync(
    payloads: legacy.WorkbookPayloads,
    url: str,
    service_key: str,
    *,
    force_version: bool = False,
) -> None:
    # Relational ownership remains workbook-driven and keeps the Phase 2 merge behavior.
    legacy._upsert(
        table="tenants",
        rows=payloads.tenants,
        on_conflict="tenant_id",
        url=url,
        service_key=service_key,
    )
    legacy._upsert(
        table="tenant_services",
        rows=payloads.services,
        on_conflict="tenant_id,service",
        url=url,
        service_key=service_key,
    )
    legacy._upsert(
        table="devices",
        rows=payloads.devices,
        on_conflict="device_id",
        url=url,
        service_key=service_key,
    )

    _sync_app_config_atomic(
        payloads.app_config,
        url=url,
        service_key=service_key,
        force_version=force_version,
    )
    legacy.verify_remote(payloads, url, service_key)
    _verify_versions(payloads, url=url, service_key=service_key)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate workbook and relational payloads without credentials or writes.",
    )
    parser.add_argument(
        "--expect-keys",
        type=int,
        default=None,
        help="Require this exact canonical app_config key count in addition to workbook validation.",
    )
    parser.add_argument(
        "--force-version",
        action="store_true",
        help=(
            "Administrative replacement override: on SQLSTATE 40001, refresh the "
            "live version and retry the atomic RPC. Stored version still increments."
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        payloads = legacy.load_workbook_payloads()
        legacy._print_inventory(payloads)
        if args.expect_keys is not None:
            if args.expect_keys < 1:
                raise ValueError("--expect-keys must be a positive integer")
            actual_count = len(payloads.app_config)
            if actual_count != args.expect_keys:
                raise ValueError(
                    f"Expected {args.expect_keys} app_config keys; got {actual_count}"
                )
            print(f"EXPECTED KEY COUNT VERIFIED: {actual_count}")
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        mode = " with --force-version requested (no writes in dry-run)" if args.force_version else ""
        print(f"DRY-RUN OK{mode}: no Supabase credentials required; no network writes performed")
        return 0

    url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not service_key:
        print(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY are required for full sync. "
            "Use --dry-run for validation-only mode.",
            file=sys.stderr,
        )
        return 2

    try:
        sync(
            payloads,
            url,
            service_key,
            force_version=args.force_version,
        )
    except (RuntimeError, requests.RequestException, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        "DONE Versioned administrative replacement: "
        f"{len(payloads.app_config)} app_config keys, "
        f"{len(payloads.tenants)} tenants, "
        f"{len(payloads.services)} services, "
        f"{len(payloads.devices)} devices"
    )
    return 0


WorkbookPayloads = legacy.WorkbookPayloads
load_workbook_payloads = legacy.load_workbook_payloads


if __name__ == "__main__":
    raise SystemExit(main())
