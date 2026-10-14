#!/usr/bin/env python3
"""Compare a disposable replay of the 12 recorded clone migrations to the captured clone catalog."""
from __future__ import annotations
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PATH = ROOT / "supabase/reconciliation/staging-clone-catalog-fingerprint-2026-10-14.json"
ERRORS: list[str] = []

def load(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, list) and len(value) == 1:
            value = value[0]
        if isinstance(value, dict) and "manifest" in value:
            value = value["manifest"]
        if not isinstance(value, dict):
            raise ValueError("expected one JSON object")
        return value
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: cannot load {path}: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc

def by_id(items: list[dict], label: str) -> dict[str, dict]:
    result = {str(item.get("id")): item for item in items}
    if len(result) != len(items):
        ERRORS.append(f"{label}: duplicate object identity")
    return result

def compare_exact(label: str, expected: list[dict], actual: list[dict], fields: tuple[str, ...]) -> None:
    exp, got = by_id(expected, label + " expected"), by_id(actual, label + " actual")
    missing, extra = sorted(set(exp)-set(got)), sorted(set(got)-set(exp))
    if missing:
        ERRORS.append(f"{label} missing ({len(missing)}): {', '.join(missing[:10])}")
    if extra:
        ERRORS.append(f"{label} unexpected ({len(extra)}): {', '.join(extra[:10])}")
    for object_id in sorted(set(exp)&set(got)):
        for field in fields:
            if exp[object_id].get(field) != got[object_id].get(field):
                ERRORS.append(f"{label} {object_id} differs in {field}")

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: compare_clone_historical_migration_fingerprint.py <psql-json-output>", file=sys.stderr)
        return 2
    expected, actual = load(EXPECTED_PATH), load(Path(sys.argv[1]))
    compare_exact("clone relation", expected.get("relations", []), actual.get("relations", []),
        ("kind", "columns_md5", "constraints_md5", "indexes_md5", "rls_enabled", "force_rls"))
    compare_exact("clone routine", expected.get("functions", []), actual.get("functions", []),
        ("returns", "language", "security_definer", "definition_md5", "anon_execute", "authenticated_execute"))
    compare_exact("clone policy", expected.get("policies", []), actual.get("policies", []),
        ("fingerprint_md5", "command", "roles"))
    compare_exact("clone trigger", expected.get("triggers", []), actual.get("triggers", []),
        ("enabled", "definition_md5"))
    counts = tuple(len(expected.get(k, [])) for k in ("relations", "functions", "policies", "triggers"))
    if counts != (71, 134, 42, 41):
        ERRORS.append(f"reference inventory changed unexpectedly: {counts}")
    if ERRORS:
        for error in ERRORS:
            print("FAIL: " + error, file=sys.stderr)
        return 1
    print("PASS: all 71 clone relations match column, constraint, index, RLS, and force-RLS fingerprints.")
    print("PASS: all 134 clone routine definitions and effective anon/authenticated EXECUTE flags match.")
    print("PASS: all 42 clone policy identities/expressions and all 41 non-internal triggers match.")
    print("NOTICE: clone historical parity is not security approval; broad anon ACLs remain a separate hardening gate.")
    print("NOTICE: row data, production restore, cron state, and application-level Tenant A/B behavior are not certified.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
