#!/usr/bin/env python3
"""Validate schema-only pre-history fixtures used by the disposable historical replay."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "supabase/reconciliation/historical-replay-bootstrap/20260929000000_legacy_licences.sql"
ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def table_block(sql: str, schema: str, table: str) -> str:
    pattern = rf"CREATE TABLE {re.escape(schema)}\.{re.escape(table)}\s*\((.*?)\);"
    match = re.search(pattern, sql, flags=re.IGNORECASE | re.DOTALL)
    return match.group(1) if match else ""


def main() -> int:
    try:
        sql = BOOTSTRAP.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"FAIL: cannot read pre-history bootstrap: {exc}", file=sys.stderr)
        return 2

    clean_sql = "\n".join(line for line in sql.splitlines() if not line.lstrip().startswith("--"))
    if re.search(r"^\s*(?:INSERT\s+INTO|COPY|UPDATE|DELETE\s+FROM|TRUNCATE)\b", clean_sql, re.IGNORECASE | re.MULTILINE):
        fail("pre-history bootstrap must be schema-only; row-data or destructive DML is forbidden")

    required = {
        "licences": ("toko_address text NOT NULL DEFAULT ''::text", "CONSTRAINT licences_pkey PRIMARY KEY (device_id)"),
        "app_config": (
            "key text NOT NULL",
            "value jsonb NOT NULL DEFAULT '{}'::jsonb",
            "updated_at timestamp with time zone NOT NULL DEFAULT now()",
            "CONSTRAINT app_config_pkey PRIMARY KEY (key)",
        ),
        "client_status": (
            "device_id text NOT NULL",
            "app_version text NOT NULL DEFAULT 'unknown'::text",
            "CONSTRAINT client_status_pkey PRIMARY KEY (device_id)",
            "CONSTRAINT client_status_hardware_mode_check",
            "CONSTRAINT client_status_sales_today_check",
        ),
    }
    blocks = {name: table_block(sql, "public", name) for name in required}
    for name, fragments in required.items():
        if not blocks[name]:
            fail(f"missing pre-history relation public.{name}")
            continue
        for fragment in fragments:
            if fragment.lower() not in blocks[name].lower():
                fail(f"public.{name} is missing expected current-staging DDL fragment: {fragment}")
    if "references public.licences" in blocks["client_status"].lower():
        fail("pre-history public.client_status must not reintroduce the obsolete licences foreign key")
    if "check (length(btrim(key)) > 0)" in blocks["app_config"].lower():
        fail("pre-history public.app_config must match staging; it has no key-length check constraint")

    if ERRORS:
        for error in ERRORS:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: pre-history bootstrap contains the three observed relations with current staging DDL shape.")
    print("PASS: bootstrap is schema-only and contains no row-data or destructive DML.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
