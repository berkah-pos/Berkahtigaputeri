#!/usr/bin/env python3
"""Validate source-recovery provenance and reconstructed DDL artifacts without network access."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "supabase/reconciliation/source-recovery-manifest-2026-10-14.json"
BASELINE = ROOT / "supabase/reconciliation/reconstructed/staging-baseline"
ACTIVE_MIGRATIONS = ROOT / "supabase/migrations"
ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def git_blob_sha(path: Path) -> str:
    data = path.read_bytes()
    header = b"blob " + str(len(data)).encode("ascii") + b"\0"
    return hashlib.sha1(header + data).hexdigest()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
        return ""


def count(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, flags=re.IGNORECASE | re.MULTILINE))


def main() -> int:
    if not MANIFEST_PATH.is_file():
        fail("source recovery manifest is missing")
        manifest = {}
    else:
        try:
            manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"source recovery manifest is invalid: {exc}")
            manifest = {}

    search = manifest.get("repository_search", {})
    if search.get("primary_repository") != "berkah-pos/Berkahtigaputeri":
        fail("primary repository provenance does not match the audited repository")
    if search.get("mirror_repository") != "Andisatriawan/Berkahtigaputeri":
        fail("mirror repository provenance does not match the audited source")
    if search.get("reachable_primary_branches_scanned") != 19:
        fail("expected an auditable record of all 19 reachable primary branches")
    if search.get("reachable_mirror_branches_scanned") != 1:
        fail("expected an auditable record of the mirror's only reachable branch")

    histories = {x.get("environment"): x for x in manifest.get("remote_environments", [])}
    for environment, wanted_total, wanted_candidates, wanted_missing in (
        ("staging", 139, 2, 137),
        ("staging-clone", 12, 7, 5),
    ):
        record = histories.get(environment)
        if not record:
            fail(f"remote history for {environment} is missing")
            continue
        entries = record.get("entries", [])
        if record.get("registry_count") != wanted_total or len(entries) != wanted_total:
            fail(f"{environment} migration registry count no longer matches captured evidence")
        counts = manifest.get("counts", {}).get(environment, {})
        if counts.get("exact_git_version_and_sql_matches") != 0:
            fail(f"{environment} incorrectly claims an exact historical Git SQL/version match")
        if counts.get("recovered_remote_sql_bodies") != wanted_total:
            fail(f"{environment} recovered body count is inconsistent")
        if counts.get("candidate_not_exact") != wanted_candidates:
            fail(f"{environment} candidate classification count is inconsistent")
        if counts.get("missing_git_source") != wanted_missing:
            fail(f"{environment} missing-Git-source count is inconsistent")
        if any(entry.get("remote_body_status") != "RECOVERED_FROM_SUPABASE_MIGRATION_LEDGER" for entry in entries):
            fail(f"{environment} contains an entry without recovered remote SQL body evidence")
        if any(entry.get("source_status") == "EXACT_MATCH" for entry in entries):
            fail(f"{environment} contains an unsupported exact-source claim")

    # Verify each currently tracked migration against its captured Git blob SHA.
    for record in manifest.get("current_source_files", []):
        path = ROOT / record.get("path", "")
        if not path.is_file():
            fail(f"tracked source candidate is missing: {record.get('path')}")
        elif git_blob_sha(path) != record.get("blob_sha"):
            fail(f"source candidate blob SHA changed: {record.get('path')}")

    # The additional recovered files must be byte-identical to their source-branch blobs.
    for record in manifest.get("archived_feature_branch_sources", []):
        path = ROOT / record.get("path", "")
        if not path.is_file():
            fail(f"archived candidate is missing: {record.get('path')}")
        elif git_blob_sha(path) != record.get("blob_sha"):
            fail(f"archived candidate is not byte-identical to recorded source blob: {record.get('path')}")
        if record.get("status") not in ("CANDIDATE_NOT_EXACT", "VERIFICATION_SCRIPT_NOT_MIGRATION"):
            fail(f"unexpected source classification for {record.get('path')}")

    active_files = sorted(p.name for p in ACTIVE_MIGRATIONS.glob("*.sql"))
    expected_active = [
        "20261008131700_p0_rls_identity_config_runtime_prep.sql",
        "20261013120000_phase5_tenant_isolation_hardening.sql",
    ]
    if active_files != expected_active:
        fail("recovered/reconstructed source must remain outside supabase/migrations/ until a reviewed baseline is approved")

    required = [
        "config.toml",
        "010_tables_and_sequences.sql",
        "020_constraints_and_indexes.sql",
        "031_sql_functions.sql",
        "040_rls_policies_and_triggers.sql",
        "050_object_acl.sql",
        "060_target_default_privilege_hardening.sql",
        "replay_validation.test.sql",
        "source-catalog-fingerprint.json",
    ]
    for name in required:
        if not (BASELINE / name).is_file():
            fail(f"required reconstructed baseline artifact is missing: {name}")
    plpgsql_files = sorted(BASELINE.glob("030_plpgsql_*.sql"))
    if len(plpgsql_files) != 13:
        fail(f"expected 13 PL/pgSQL routine fragments, found {len(plpgsql_files)}")

    table_sql = read_text(BASELINE / "010_tables_and_sequences.sql")
    constraint_sql = read_text(BASELINE / "020_constraints_and_indexes.sql")
    plpgsql_sql = "\n".join(read_text(p) for p in plpgsql_files)
    sql_function_sql = read_text(BASELINE / "031_sql_functions.sql")
    security_sql = read_text(BASELINE / "040_rls_policies_and_triggers.sql")
    overlay_sql = read_text(BASELINE / "060_target_default_privilege_hardening.sql")
    test_sql = read_text(BASELINE / "replay_validation.test.sql")

    counts = {
        "tables": count(r"^CREATE\s+(?:UNLOGGED\s+)?TABLE\b", table_sql),
        "constraints": count(r"^ALTER TABLE ONLY .* ADD CONSTRAINT\b", constraint_sql) + count(r"^CREATE CONSTRAINT TRIGGER\b", security_sql),
        "indexes": count(r"^CREATE\s+(?:UNIQUE\s+)?INDEX\b", constraint_sql),
        "plpgsql_routines": count(r"^CREATE OR REPLACE FUNCTION\b", plpgsql_sql),
        "sql_routines": count(r"^CREATE OR REPLACE FUNCTION\b", sql_function_sql),
        "function_terminators": count(r"\$function\$;", plpgsql_sql + "\n" + sql_function_sql),
        "source_policies": count(r"^CREATE POLICY\b", security_sql),
        "target_extra_policies": count(r"^CREATE POLICY\b", overlay_sql),
        "triggers": count(r"^CREATE (?:CONSTRAINT\s+)?TRIGGER\b", security_sql),
        "pgtap_assertions": count(r"^SELECT extensions\.ok\(", test_sql),
    }
    for key, expected in {
        "tables": 67,
        "constraints": 615,
        "indexes": 49,
        "plpgsql_routines": 147,
        "sql_routines": 22,
        "function_terminators": 169,
        "source_policies": 42,
        "target_extra_policies": 2,
        "triggers": 49,
        "pgtap_assertions": 16,
    }.items():
        if counts[key] != expected:
            fail(f"reconstructed artifact count mismatch: {key}={counts[key]}, expected {expected}")

    # Ensure no transaction/business rows have been exported as part of the schema snapshot.
    for name in ("010_tables_and_sequences.sql", "020_constraints_and_indexes.sql"):
        text = read_text(BASELINE / name)
        if count(r"^\s*(?:INSERT INTO|COPY)\b", text):
            fail(f"row-data statements are forbidden in schema-only artifact {name}")
    if "ALTER DEFAULT PRIVILEGES" not in overlay_sql:
        fail("target overlay is missing least-privilege default ACL hardening")
    if "tenant_accounting_links ENABLE ROW LEVEL SECURITY" not in overlay_sql:
        fail("target overlay must close the source-staging tenant_accounting_links RLS gap")
    if 'project_id = "berkah-pos-reconstructed-staging-replay"' not in read_text(BASELINE / "config.toml"):
        fail("replay config must identify itself as disposable and unlinked")
    if "352 canonical app_config" in test_sql:
        # The replay deliberately contains schema only; workbook seed data is a separate gate.
        pass

    if not (ROOT / "supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json").is_file():
        fail("hosted remote migration SQL archive is missing")
    archive_info = manifest.get("recovered_remote_sql_archive", {})
    if archive_info.get("total_records") != 151 or archive_info.get("total_sql_bytes") != 988256:
        fail("manifest does not attest to all 151 recovered hosted migration SQL bodies")
    if manifest.get("clean_replay", {}).get("historical_ordered_replay") not in {"PENDING_DISPOSABLE_REPLAY", "PASS"}:
        fail("invalid historical replay status")

    if ERRORS:
        for error in ERRORS:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: recovered candidate blobs match their recorded source commit blobs.")
    print("PASS: 151 exact SQL bodies are archived from remote migration ledgers; Git still has 0 exact historical-source matches.")
    print("PASS: all reconstructed source remains outside supabase/migrations/; no historical source is silently promoted.")
    print("PASS: schema-only target baseline has 67 tables, 615 constraints, 49 extra indexes, 169 functions, 42 source policies, 49 triggers.")
    print("PASS: target overlay adds two tenant-accounting RLS policies and 16 replay assertions.")
    print("NOTICE: recovered historical SQL requires its separate 139-entry disposable ordered-replay gate.")
    print("COUNTS: " + json.dumps(counts, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
