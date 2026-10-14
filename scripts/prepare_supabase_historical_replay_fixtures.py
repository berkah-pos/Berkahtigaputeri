#!/usr/bin/env python3
"""Prepare a temp-only replay fixture from the canonical workbook and archived guards.

This is not a production seed script. With --output, it writes a one-off migration
into a disposable runner work directory; without --output it performs validation only.
It never prints or commits configuration row values.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync_excel_to_supabase_legacy as legacy  # noqa: E402

APP_CONFIG_TABLE_COUNT = 352
APP_CONFIG_KEY_DIGEST = "1fd3d64219ecc7c333453c20da80e295"
INVENTORY_GUARD_VERSION = "20261007184231"
SUPER_ADMIN_GUARD_VERSION = "20261008131537"
REPLAY_FIXTURE_VERSION = "20261007180000"


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def migration_by_version(archive: dict[str, Any], version: str) -> dict[str, Any]:
    matches = [
        row for row in archive.get("entries", [])
        if row.get("environment") == "staging" and row.get("version") == version
    ]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one staging archive entry for {version}; got {len(matches)}")
    row = matches[0]
    sql = row.get("sql")
    if not isinstance(sql, str) or not sql:
        raise ValueError(f"SQL body is missing for staging migration {version}")
    raw = sql.encode("utf-8")
    if len(raw) != row.get("sql_bytes") or hashlib.sha256(raw).hexdigest() != row.get("sql_sha256"):
        raise ValueError(f"SQL body hash/byte check failed for staging migration {version}")
    return row


def extract_inventory_contract(body: str) -> tuple[int, str]:
    match = re.search(
        r"v_count\s*<>\s*(\d+)\s+or\s+v_(?:digest|md5)\s*<>\s*'([0-9a-f]{32})'",
        body,
        re.IGNORECASE,
    )
    if not match:
        raise ValueError("could not extract the 352-key inventory guard from archived SQL")
    return int(match.group(1)), match.group(2).lower()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True, help="Verified recovered SQL archive JSON")
    parser.add_argument("--output", type=Path, help="Optional output path inside the isolated runner migration directory")
    args = parser.parse_args()

    try:
        archive = json.loads(args.archive.read_text(encoding="utf-8"))
        guard = migration_by_version(archive, INVENTORY_GUARD_VERSION)
        p0 = migration_by_version(archive, SUPER_ADMIN_GUARD_VERSION)
        expected_count, expected_digest = extract_inventory_contract(guard["sql"])
        p0_count, p0_digest = extract_inventory_contract(p0["sql"])
        if (expected_count, expected_digest) != (p0_count, p0_digest):
            raise ValueError("the two recorded migrations disagree on the canonical app_config contract")

        uid_match = re.search(
            r"v_uid\s+is\s+distinct\s+from\s+'([0-9a-f-]{36})'::uuid",
            p0["sql"],
            re.IGNORECASE,
        )
        email_match = re.search(
            r"lower\s*\(\s*email\s*\)\s*=\s*'([^']+)'",
            p0["sql"],
            re.IGNORECASE,
        )
        if not uid_match or not email_match:
            raise ValueError("could not extract the recorded local-only Auth guard identity")
        canonical_uid = uid_match.group(1)
        canonical_email = email_match.group(1).strip().lower()
        if not re.fullmatch(r"[0-9a-f-]{36}", canonical_uid) or not canonical_email:
            raise ValueError("invalid identity values extracted from the recorded migration body")

        payloads = legacy.load_workbook_payloads()
        rows = payloads.app_config
        keys = sorted(str(row["key"]) for row in rows)
        actual_digest = hashlib.md5("\n".join(keys).encode("utf-8")).hexdigest()
        if len(rows) != expected_count or len(keys) != len(set(keys)):
            raise ValueError(f"canonical workbook has {len(rows)} unique app_config keys; expected {expected_count}")
        if actual_digest != expected_digest:
            raise ValueError(
                "canonical workbook key inventory disagrees with the recorded migration guard "
                f"(count={len(keys)}, digest={actual_digest})"
            )

        print(
            "PASS: canonical workbook provides "
            f"{len(rows)} unique app_config keys matching the archived migration guard."
        )
        print("PASS: replay-only Auth guard identity was read from the archived migration; no password/token is set.")
        if args.output is None:
            return 0

        if args.output.exists():
            raise FileExistsError(f"refusing to overwrite existing temp migration file: {args.output}")
        args.output.parent.mkdir(parents=True, exist_ok=True)

        ordered = {str(row["key"]): dict(row["value"]) for row in rows}
        lines = [
            "-- DISPOSABLE REPLAY FIXTURE ONLY; generated from the canonical workbook at CI runtime.",
            "-- Not part of recorded history. Never apply to a hosted project.",
            "-- Seeds the 352 canonical keys required by the recorded 5-layer config guard.",
            "-- The guard identity below is non-authenticating: empty password, unconfirmed email, no issued session/token.",
            "BEGIN;",
            "",
            "-- Disposable replay only: remove bootstrap/legacy keys so the recorded 352-key",
            "-- guard is tested against the canonical workbook's exact inventory.",
            "DELETE FROM public.app_config;",
            "",
            "INSERT INTO public.app_config (key, value, updated_at)",
            "VALUES",
        ]
        value_rows: list[str] = []
        for key in sorted(ordered):
            value = dict(ordered[key])
            value.pop("version", None)
            value["version"] = 1
            encoded = base64.b64encode(
                json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            ).decode("ascii")
            value_rows.append(
                f"  ({sql_literal(key)}, "
                f"convert_from(decode('{encoded}', 'base64'), 'UTF8')::jsonb, now())"
            )
        lines.append(",\n".join(value_rows))
        lines.extend([
            "ON CONFLICT (key) DO UPDATE",
            "SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;",
            "",
            "-- A schema-migration guard checks the canonical administrator row exists.",
            "-- No password is set or email confirmed; this row is never used for sign-in.",
            "INSERT INTO auth.users",
            "  (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)",
            "VALUES",
            "  ("
            + sql_literal(canonical_uid) + "::uuid, "
            + "'00000000-0000-0000-0000-000000000000'::uuid, "
            + "'authenticated', 'authenticated', "
            + sql_literal(canonical_email) + ", '', '{}'::jsonb, '{}'::jsonb, now(), now())",
            "ON CONFLICT (id) DO UPDATE",
            "SET email = EXCLUDED.email, encrypted_password = '', updated_at = now();",
            "",
            "COMMIT;",
            "",
        ])
        if "DELETE FROM public.app_config;" not in "\n".join(lines):
            raise ValueError("replay-only fixture must remove noncanonical bootstrap config keys before seeding canonical workbook")
        args.output.write_text("\n".join(lines), encoding="utf-8")
        print(
            f"PASS: wrote one runner-only replay fixture ({len(rows)} app_config records and one "
            "non-authenticating auth.users guard row); values were not printed."
        )
        print(f"FIXTURE: version={REPLAY_FIXTURE_VERSION} bytes={args.output.stat().st_size}")
        return 0
    except (OSError, json.JSONDecodeError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: replay fixture preflight: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
