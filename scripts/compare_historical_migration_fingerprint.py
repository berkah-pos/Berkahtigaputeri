#!/usr/bin/env python3
"""Compare a clean historical migration replay to the staging structural fingerprint."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "supabase/reconciliation/reconstructed/staging-baseline"
EXPECTED_PATH = BASELINE / "source-catalog-fingerprint.json"
ERRORS: list[str] = []

def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list) and len(data) == 1:
            data = data[0]
        if isinstance(data, dict) and "manifest" in data:
            data = data["manifest"]
        if not isinstance(data, dict):
            raise ValueError("expected JSON object")
        return data
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: cannot load {path}: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc

def fail(message: str) -> None:
    ERRORS.append(message)

def map_by_id(items: list[dict]) -> dict[str, dict]:
    return {str(item.get("id")): item for item in items}

def compare_exact(label: str, expected: list[dict], actual: list[dict], fields: tuple[str, ...]) -> None:
    exp = map_by_id(expected)
    act = map_by_id(actual)
    missing = sorted(set(exp) - set(act))
    extra = sorted(set(act) - set(exp))
    if missing:
        fail(f"{label} missing: {', '.join(missing[:10])}")
    if extra:
        fail(f"{label} unexpected: {', '.join(extra[:10])}")
    for obj_id in sorted(set(exp) & set(act)):
        for field in fields:
            if exp[obj_id].get(field) != act[obj_id].get(field):
                fail(f"{label} {obj_id} differs in {field}")

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: compare_historical_migration_fingerprint.py <psql-json-output>", file=sys.stderr)
        return 2
    expected = load(EXPECTED_PATH)
    actual = load(Path(sys.argv[1]))
    compare_exact("relation", expected.get("relations", []), actual.get("relations", []),
                  ("kind", "columns_md5", "constraints_md5", "indexes_md5", "rls_enabled", "force_rls"))
    compare_exact("routine", expected.get("functions", []), actual.get("functions", []),
                  ("returns", "language", "security_definer", "definition_md5", "anon_execute", "authenticated_execute"))
    compare_exact("policy", expected.get("policies", []), actual.get("policies", []),
                  ("fingerprint_md5", "command", "roles"))
    compare_exact("trigger", expected.get("triggers", []), actual.get("triggers", []),
                  ("enabled", "definition_md5"))

    expected_counts = (len(expected.get("relations", [])), len(expected.get("functions", [])),
                       len(expected.get("policies", [])), len(expected.get("triggers", [])))
    if expected_counts != (67, 169, 42, 49):
        fail(f"source reference counts changed unexpectedly: {expected_counts}")

    # Rows, app_config values, secrets, cron job records and extension versions are intentionally
    # outside this schema-only compare. This verifies structure and routine security modes only.
    if ERRORS:
        for error in ERRORS:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: clean replay matches all 67 staging relations, including exact RLS enablement and DDL fingerprints.")
    print("PASS: all 169 routine definitions/security modes, 42 source policies, and 49 triggers match staging exactly.")
    print("NOTICE: row data, app_config values, extension versions, cron job records, clone equivalence and production restore are not certified.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
