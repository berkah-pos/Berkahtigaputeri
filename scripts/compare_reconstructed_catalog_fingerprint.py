#!/usr/bin/env python3
"""Compare a disposable replay's structural fingerprint to the read-only staging source."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "supabase/reconciliation/reconstructed/staging-baseline"
EXPECTED_PATH = BASELINE / "source-catalog-fingerprint.json"
ERRORS: list[str] = []
ANON_FUNCTION_REVOKES = {
    "public.log_config_change()",
    "public.set_updated_at()",
}
EXPECTED_TARGET_POLICIES = {
    "private.tenant_accounting_links.tenant_accounting_links_deny_anon_reconstructed",
    "private.tenant_accounting_links.tenant_accounting_links_read_member_reconstructed",
}
RLS_ENABLEMENT_EXCEPTION = "private.tenant_accounting_links"


def fail(message: str) -> None:
    ERRORS.append(message)


def by_id(items: list[dict], key: str = "id") -> dict[str, dict]:
    return {str(item[key]): item for item in items}


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, list) and len(value) == 1:
            value = value[0]
        if isinstance(value, dict) and "manifest" in value:
            value = value["manifest"]
        if not isinstance(value, dict):
            raise ValueError("expected JSON object")
        return value
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"ERROR: unable to parse fingerprint at {path}: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc


def compare_map(label: str, expected: list[dict], actual: list[dict]) -> tuple[dict[str, dict], dict[str, dict]]:
    expected_map = by_id(expected)
    actual_map = by_id(actual)
    missing = sorted(set(expected_map) - set(actual_map))
    extra = sorted(set(actual_map) - set(expected_map))
    if missing:
        fail(f"{label} missing objects: {', '.join(missing[:12])}" + (" …" if len(missing) > 12 else ""))
    if extra:
        fail(f"{label} has unexpected objects: {', '.join(extra[:12])}" + (" …" if len(extra) > 12 else ""))
    return expected_map, actual_map


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: compare_reconstructed_catalog_fingerprint.py <psql-json-output>", file=sys.stderr)
        return 2
    expected = read_json(EXPECTED_PATH)
    actual = read_json(Path(sys.argv[1]))

    # Relation metadata is identical except for the intended RLS enablement hardening on one table.
    exp_rel, act_rel = compare_map("application relation", expected.get("relations", []), actual.get("relations", []))
    for object_id in sorted(set(exp_rel) & set(act_rel)):
        e, a = exp_rel[object_id], act_rel[object_id]
        for field in ("kind", "columns_md5", "constraints_md5", "indexes_md5", "force_rls"):
            if e.get(field) != a.get(field):
                fail(f"relation {object_id} has a different {field}")
        source_rls = bool(e.get("rls_enabled"))
        replay_rls = bool(a.get("rls_enabled"))
        if object_id == RLS_ENABLEMENT_EXCEPTION:
            if source_rls or not replay_rls:
                fail("tenant-accounting link RLS change is not the expected source-off / target-on hardening")
        elif source_rls != replay_rls:
            fail(f"relation {object_id} unexpectedly differs in RLS enablement")

    exp_fn, act_fn = compare_map("application routine", expected.get("functions", []), actual.get("functions", []))
    for object_id in sorted(set(exp_fn) & set(act_fn)):
        e, a = exp_fn[object_id], act_fn[object_id]
        for field in ("returns", "language", "security_definer", "definition_md5", "authenticated_execute"):
            if e.get(field) != a.get(field):
                fail(f"routine {object_id} has a different {field}")
        source_anon = bool(e.get("anon_execute"))
        replay_anon = bool(a.get("anon_execute"))
        if object_id in ANON_FUNCTION_REVOKES:
            if not source_anon or replay_anon:
                fail(f"target anon execute hardening was not applied to {object_id}")
        elif source_anon != replay_anon:
            fail(f"routine {object_id} unexpectedly differs in anon EXECUTE privilege")

    exp_pol = expected.get("policies", [])
    act_pol = actual.get("policies", [])
    exp_policy, act_policy = by_id(exp_pol), by_id(act_pol)
    missing = sorted(set(exp_policy) - set(act_policy))
    if missing:
        fail("source policies missing from replay: " + ", ".join(missing[:12]))
    extra = sorted(set(act_policy) - set(exp_policy))
    if set(extra) != EXPECTED_TARGET_POLICIES:
        fail("unexpected reconstructed target policy delta: " + ", ".join(extra[:12]))
    for object_id in sorted(set(exp_policy) & set(act_policy)):
        for field in ("fingerprint_md5", "command", "roles"):
            if exp_policy[object_id].get(field) != act_policy[object_id].get(field):
                fail(f"policy {object_id} has a different {field}")

    exp_trg, act_trg = compare_map("application trigger", expected.get("triggers", []), actual.get("triggers", []))
    for object_id in sorted(set(exp_trg) & set(act_trg)):
        for field in ("enabled", "definition_md5"):
            if exp_trg[object_id].get(field) != act_trg[object_id].get(field):
                fail(f"trigger {object_id} has a different {field}")

    if len(expected.get("relations", [])) != 67:
        fail("source reference no longer has the expected 67 audited relations")
    if len(expected.get("functions", [])) != 169:
        fail("source reference no longer has the expected 169 routines")
    if len(expected.get("policies", [])) != 42:
        fail("source reference no longer has the expected 42 source RLS policies")
    if len(expected.get("triggers", [])) != 49:
        fail("source reference no longer has the expected 49 non-internal triggers")

    if ERRORS:
        for error in ERRORS:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: reconstructed relation columns, constraints and indexes match the staging structural fingerprint.")
    print("PASS: all 169 routine definitions and security modes match; only two intended trigger-helper anon EXECUTE grants changed.")
    print("PASS: all 42 source policies and 49 source triggers match; two reviewed tenant-accounting RLS policies are added.")
    print("PASS: private.tenant_accounting_links is the only intended source-RLS flag difference (disabled in source, enabled in target).")
    print("NOTICE: row data, extension-version parity, cron jobs, full historical migration bodies and clone equivalence are not certified by this comparison.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
